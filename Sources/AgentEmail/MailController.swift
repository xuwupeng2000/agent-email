import SwiftUI
import AppKit

@MainActor final class MailController: ObservableObject {
    @Published var status = "尚未连接 Outlook"
    @Published var address = ""
    @Published var userCode = ""
    @Published var verificationURL: URL?
    @Published var busy = false
    @Published var messages: [MailItem] = []
    @Published var selected: String?
    @Published var replyText = ""
    @Published var connected = false
    private var client: OutlookClient?
    private var loginTask: Task<Void, Never>?

    var current: MailItem? { messages.first { $0.id == selected } }

    func connect(clientID: String, restore: Bool = false) {
        guard !busy else { return }
        busy = true
        let service = OutlookClient(clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines))
        client = service
        status = restore ? "正在恢复 Outlook 连接…" : "正在申请 Microsoft 验证码…"
        loginTask = Task {
            defer { busy = false }
            do {
                if restore { try await service.restore() }
                else {
                    let grant = try await service.beginLogin()
                    userCode = grant.user_code
                    guard let url = URL(string: grant.verification_uri), url.scheme == "https",
                          ["microsoft.com", "www.microsoft.com", "login.microsoftonline.com"].contains(url.host ?? "") else {
                        throw OutlookFailure(message: "Microsoft 返回了无法识别的验证地址。")
                    }
                    verificationURL = url
                    status = "在 Microsoft 页面输入验证码并授权。"
                    NSWorkspace.shared.open(url)
                    try await service.finishLogin(grant)
                }
                try Task.checkCancellation()
                address = try await service.address()
                messages = try await service.inbox()
                connected = true
                userCode = ""
                verificationURL = nil
                status = "已连接：\(address)，已读取 \(messages.count) 封邮件。"
            } catch is CancellationError { status = "已取消连接。" }
            catch { status = error.localizedDescription }
        }
    }
    func cancelLogin() {
        loginTask?.cancel()
        userCode = ""
        verificationURL = nil
    }
    func refresh() {
        guard connected, !busy, let client else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                messages = try await client.inbox()
                status = "已刷新：\(messages.count) 封邮件。"
            } catch { status = error.localizedDescription }
        }
    }
    func sendReply(prefix: String) {
        guard connected, !busy, let client, let item = current, !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let body = replyText
        var subject = item.subject ?? ""
        if !prefix.isEmpty && subject.hasPrefix(prefix) { subject = String(subject.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces) }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await client.reply(to: item.id, text: body, subject: subject)
                replyText = ""
                status = "回复已被 Outlook 接受发送。"
            } catch { status = error.localizedDescription + "（发送结果可能不确定，请先检查已发送邮件，不要立即重复发送。）" }
        }
    }
    func disconnect() {
        guard !busy, let client else { return }
        Task {
            do {
                try await client.disconnect()
                connected = false
                address = ""
                messages = []
                selected = nil
                replyText = ""
                status = "已删除本机授权。若要撤销 Microsoft 端权限，请在账号管理中撤销应用授权。"
            } catch { status = error.localizedDescription }
        }
    }
}
