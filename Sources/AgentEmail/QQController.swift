import SwiftUI

private struct QQJournal: Codable {
    var validity = ""
    var cursor = 0
    var jobs: [String: String] = [:]
}

@MainActor final class QQController: ObservableObject {
    @Published var status = "尚未连接 QQ 邮箱"
    @Published var address = ""
    @Published var connected = false
    @Published var busy = false
    @Published var monitoring = false
    @Published var messages: [QQMessage] = []
    @Published var selected: String?
    @Published var replyText = ""
    @Published var events: [String] = []
    private var watcher: Task<Void, Never>?
    private var journal = QQJournal()
    var current: QQMessage? { messages.first { $0.id == selected } }

    private func fields(_ action: String) throws -> [String: Any] {
        ["action": action, "address": address, "secret": try QQService.credentials(address)]
    }
    private var journalURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentEmail", isDirectory: true).appendingPathComponent("qq-\(address).json")
    }
    private func persist() throws {
        let url = journalURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(journal).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func event(_ value: String) {
        events.insert(value, at: 0)
        events = Array(events.prefix(30))
    }
    func connect(address input: String, secret: String, restore: Bool) {
        guard !busy && !connected else { return }
        let own = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard own.range(of: #"^[a-z0-9._+-]+@qq\.com$"#, options: .regularExpression) != nil else { status = "请输入完整的 @qq.com 地址。"; return }
        busy = true
        status = "正在验证 QQ 收信和发信服务…"
        Task {
            defer { busy = false }
            do {
                let code = restore ? try QQService.credentials(own) : secret.trimmingCharacters(in: .whitespacesAndNewlines)
                let result = try await QQService.call(["action": "connect", "address": own, "secret": code])
                _ = try QQService.credentials(own, save: code)
                address = own
                if FileManager.default.fileExists(atPath: journalURL.path) {
                    journal = try JSONDecoder().decode(QQJournal.self, from: Data(contentsOf: journalURL))
                } else { journal = QQJournal() }
                if journal.validity != result.validity {
                    journal.validity = result.validity ?? ""
                    journal.cursor = result.cursor ?? 0
                    try persist()
                }
                connected = true
                status = "QQ IMAP 和 SMTP 验证成功：\(own)"
                let inbox = try await QQService.call(fields("inbox"))
                messages = inbox.messages ?? []
            } catch { status = error.localizedDescription }
        }
    }
    func refresh() {
        guard connected, !busy, !monitoring else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                messages = try await QQService.call(fields("inbox")).messages ?? []
                status = "已读取 \(messages.count) 封真实邮件。"
            } catch { status = error.localizedDescription }
        }
    }
    func reply(prefix: String) {
        guard !busy, !monitoring, let item = current, !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        busy = true
        let text = replyText
        Task {
            defer { busy = false }
            do {
                var req = try fields("reply")
                req["id"] = item.id; req["text"] = text; req["prefix"] = prefix
                _ = try await QQService.call(req)
                replyText = ""
                status = "QQ SMTP 已接受回复。"
            } catch { status = error.localizedDescription + " 若发送结果不确定，请先检查邮箱，避免重复发送。" }
        }
    }
    func stop() {
        monitoring = false
        watcher?.cancel()
        status = "正在停止；已启动的任务会结束，未发送的结果会留在界面。"
    }
    func start(prefix: String, executable: String, directory: String) {
        let defaultWorkspace = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AgentEmail/Workspace").path
        if directory == defaultWorkspace {
            do { try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
            catch { status = "无法创建 Agent 工作目录。"; return }
        }
        guard connected, !busy, !monitoring, !prefix.isEmpty,
              FileManager.default.isExecutableFile(atPath: executable),
              FileManager.default.fileExists(atPath: directory) else {
            status = "请先连接邮箱并配置有效的 Codex 路径、工作目录和非空前缀。"; return
        }
        monitoring = true
        busy = true
        watcher = Task {
            defer { monitoring = false; busy = false }
            do {
                while !Task.isCancelled {
                    var req = try fields("scan")
                    req["cursor"] = journal.cursor; req["validity"] = journal.validity
                    let batch = try await QQService.call(req)
                    try Task.checkCancellation()
                    if batch.validity != journal.validity {
                        journal.validity = batch.validity ?? ""
                        journal.cursor = batch.cursor ?? 0
                        try persist()
                        event("邮箱编号变化，已跳过现有邮件建立新基线。")
                    }
                    for item in batch.messages ?? [] {
                        try Task.checkCancellation()
                        if !messages.contains(where: { $0.id == item.id }) { messages.insert(item, at: 0); messages = Array(messages.prefix(50)) }
                        let eligible = !item.automated && TriggerPolicy(ownAddress: address, prefix: prefix).accepts(sender: item.sender, recipients: item.recipients, subject: item.subject)
                        if eligible && journal.jobs[item.id] == nil {
                            journal.jobs[item.id] = "claimed"
                            try persist() // Persist before invoking any agent: crash recovery never replays a claim.
                            event("收到任务 \(item.id)，正在运行 Codex。")
                            status = "Codex 正在处理新任务…"
                            do {
                                let prompt = String(item.subject.dropFirst(prefix.count)) + "\n\n" + item.body
                                let result = try await QQService.call(["action": "agent", "executable": executable, "directory": directory, "prompt": prompt])
                                let text = result.text ?? ""
                                selected = item.id
                                replyText = text
                                if Task.isCancelled {
                                    journal.jobs[item.id] = "reply-held"
                                    try persist()
                                    event("任务已完成，已暂停发送；可在界面手动回复。")
                                    return
                                }
                                journal.jobs[item.id] = "sending"
                                try persist()
                                var reply = try fields("reply")
                                reply["id"] = item.id; reply["text"] = text; reply["prefix"] = prefix
                                _ = try await QQService.call(reply)
                                journal.jobs[item.id] = "sent"
                                try persist()
                                replyText = ""
                                event("任务 \(item.id) 已执行，QQ SMTP 已接受回复。")
                            } catch {
                                let state = journal.jobs[item.id] == "sending" ? "send-uncertain" : "failed"
                                journal.jobs[item.id] = state
                                try persist()
                                event("任务 \(item.id)：\(error.localizedDescription)；未自动重试。")
                            }
                        }
                        journal.cursor = max(journal.cursor, item.uid)
                        try persist()
                    }
                    status = "监听中，每 20 秒检查新邮件；没有邮件时不调用 AI。"
                    try await Task.sleep(for: .seconds(20))
                }
            } catch is CancellationError { status = "监听已停止。" }
            catch { status = "监听停止：" + error.localizedDescription }
        }
    }
    func disconnect() {
        guard !busy && !monitoring else { return }
        do {
            _ = try QQService.credentials(address, delete: true)
            connected = false; messages = []; selected = nil; replyText = ""
            status = "已删除本机 QQ 授权。"
        } catch { status = error.localizedDescription }
    }
}
