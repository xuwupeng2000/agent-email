import SwiftUI

struct MailboxRootView: View {
    @AppStorage("selectedProvider") private var provider = "QQ"
    var body: some View {
        VStack(spacing: 0) {
            Picker("邮箱", selection: $provider) {
                Text("QQ 邮箱").tag("QQ")
                Text("Outlook").tag("Outlook")
            }.pickerStyle(.segmented).padding()
            if provider == "QQ" { QQView() } else { SettingsView() }
        }
    }
}

struct QQView: View {
    @EnvironmentObject private var qq: QQController
    @AppStorage("qqAddress") private var address = ""
    @AppStorage("prefix") private var prefix = "[AGENT]"
    @AppStorage("codexExecutable") private var executable = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
    @AppStorage("agentDirectory") private var directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AgentEmail/Workspace").path
    @State private var secret = ""
    @State private var confirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("QQ → Agent → 邮件回复").font(.title2.bold()); Spacer(); if qq.busy { ProgressView().controlSize(.small) } }
            Text(qq.status).font(.callout).textSelection(.enabled)
            if !qq.connected {
                GroupBox("连接你的 QQ 邮箱") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("完整邮箱地址，例如 123456@qq.com", text: $address)
                        SecureField("QQ 邮箱授权码（不是登录密码）", text: $secret)
                        HStack {
                            Button("验证并连接 QQ") { qq.connect(address: address, secret: secret, restore: false); secret = "" }.disabled(qq.busy || address.isEmpty || secret.isEmpty)
                            Button("恢复钥匙串连接") { qq.connect(address: address, secret: "", restore: true) }.disabled(qq.busy || address.isEmpty)
                            Link("打开 QQ 邮箱", destination: URL(string: "https://mail.qq.com/")!)
                        }
                        Text("在 QQ 邮箱设置中开启 IMAP/SMTP 并生成授权码。授权码仅保存到本机钥匙串；连接会同时验证收信和发信服务，不发送测试邮件。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.textFieldStyle(.roundedBorder).padding(6)
                }
            } else {
                GroupBox("自动任务") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("主题前缀", text: $prefix)
                        TextField("Codex 可执行文件", text: $executable)
                        TextField("允许只读检查的工作目录", text: $directory)
                        HStack {
                            if qq.monitoring { Button("停止监听") { qq.stop() } }
                            else { Button("开启自动处理") { confirmation = true }.disabled(qq.busy) }
                            Button("刷新收件箱") { qq.refresh() }.disabled(qq.busy)
                            Button("断开并删除授权") { qq.disconnect() }.disabled(qq.busy)
                        }
                        Text("给自己发主题为 \(prefix) 测试的邮件。首次连接前的旧邮件不执行；收到后启动一次 Codex，只读执行，结果仅回复你自己。当前每 20 秒由普通程序收信检查，不消耗 AI 调用。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.textFieldStyle(.roundedBorder).padding(6)
                }
                HSplitView {
                    List(qq.messages, selection: $qq.selected) { item in
                        VStack(alignment: .leading) {
                            Text(item.subject).lineLimit(2)
                            Text(item.sender).font(.caption).foregroundStyle(.secondary)
                        }.tag(item.id)
                    }.frame(minWidth: 240)
                    VStack(alignment: .leading, spacing: 6) {
                        if let item = qq.current {
                            Text(item.subject).font(.headline)
                            ScrollView { Text(item.body).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                            Text("回复（仅发给自己的邮箱）")
                            TextEditor(text: $qq.replyText).frame(height: 90).border(.quaternary)
                            Button("发送回复") { qq.reply(prefix: prefix) }.disabled(qq.busy || qq.replyText.isEmpty)
                        } else { ContentUnavailableView("连接后选择邮件", systemImage: "envelope") }
                    }.padding(8).frame(minWidth: 380)
                }
                if !qq.events.isEmpty {
                    ScrollView { VStack(alignment: .leading) { ForEach(Array(qq.events.enumerated()), id: \.offset) { _, event in Text(event).font(.caption).textSelection(.enabled) } }.frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 90)
                }
            }
            Spacer(minLength: 0)
        }.padding(16)
        .alert("启用邮件自动任务？", isPresented: $confirmation) {
            Button("启用") { qq.start(prefix: prefix, executable: executable, directory: directory) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只处理自己发给自己且主题带前缀的新邮件。任务正文会提交给已登录的 Codex（使用其模型服务与额度），只读运行，结果通过 QQ 邮箱自动回复你自己。From 地址和主题不能独立证明身份，建议使用专门的任务邮箱。")
        }
    }
}
