import SwiftUI

@main struct AgentEmailApp: App {
    @StateObject private var mail = MailController()
    var body: some Scene {
        WindowGroup("Agent Email") {
            SettingsView().environmentObject(mail).frame(minWidth: 900, minHeight: 700)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var mail: MailController
    @AppStorage("outlookClientID") private var clientID = ""
    @AppStorage("prefix") private var prefix = "[AGENT]"
    @State private var setup = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Agent Email").font(.largeTitle.bold())
                Spacer()
                if mail.busy { ProgressView().controlSize(.small) }
                Text(mail.connected ? "Outlook 已连接" : "Outlook 未连接")
                    .foregroundStyle(mail.connected ? .green : .secondary)
            }
            Text(mail.status).font(.callout).textSelection(.enabled)
            if !mail.connected {
                GroupBox("连接 Outlook") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("使用 Microsoft 网页登录，不需要将邮箱密码交给本软件。")
                        TextField("Microsoft Application (client) ID", text: $clientID)
                            .textFieldStyle(.roundedBorder).disabled(mail.busy)
                        HStack {
                            Button("连接 Outlook / 网页验证") { mail.connect(clientID: clientID) }
                                .disabled(mail.busy || UUID(uuidString: clientID.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
                            Button("恢复已保存的连接") { mail.connect(clientID: clientID, restore: true) }
                                .disabled(mail.busy || clientID.isEmpty)
                            Button("应用注册步骤") { setup.toggle() }
                            if mail.busy { Button("取消") { mail.cancelLogin() } }
                        }
                        if !mail.userCode.isEmpty {
                            Text("Microsoft 验证码：\(mail.userCode)").font(.title2.monospaced()).textSelection(.enabled)
                            if let url = mail.verificationURL { Link("重新打开 Microsoft 验证页面", destination: url) }
                        }
                        if setup {
                            Text("首次发布前由开发者完成一次：\n1. 在 Microsoft Entra → App registrations → New registration 创建 Agent Email。\n2. 账号类型选择组织目录和个人 Microsoft 账号。\n3. Authentication → Advanced settings → Allow public client flows：Yes。\n4. API permissions 添加 Microsoft Graph 的 Delegated permissions：User.Read、Mail.Read、Mail.Send、offline_access。\n5. 将 Overview 中的 Application (client) ID 填入上方；不创建 Client Secret。\n最终用户之后只需网页登录授权。")
                                .font(.callout).textSelection(.enabled)
                            Link("打开 Microsoft Entra 应用注册", destination: URL(string: "https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade")!)
                        }
                    }.padding(6)
                }
            } else {
                HStack {
                    Button("刷新真实收件箱") { mail.refresh() }.disabled(mail.busy)
                    Button("断开并删除本机授权") { mail.disconnect() }.disabled(mail.busy)
                    Spacer()
                    TextField("触发主题前缀", text: $prefix).frame(width: 160)
                }
                HSplitView {
                    List(mail.messages, selection: $mail.selected) { item in
                        VStack(alignment: .leading) {
                            Text(item.subject ?? "（无主题）").lineLimit(2)
                            Text(item.from?.emailAddress.address ?? "").font(.caption).foregroundStyle(.secondary)
                            if TriggerPolicy(ownAddress: mail.address, prefix: prefix).accepts(sender: item.from?.emailAddress.address ?? "", recipients: item.toRecipients?.compactMap { $0.emailAddress.address } ?? [], subject: item.subject ?? "") {
                                Text("符合 Agent 触发规则").font(.caption).foregroundStyle(.blue)
                            }
                        }.tag(item.id)
                    }.frame(minWidth: 260)
                    VStack(alignment: .leading, spacing: 8) {
                        if let item = mail.current {
                            Text(item.subject ?? "（无主题）").font(.headline)
                            ScrollView { Text(item.body?.content ?? item.bodyPreview ?? "").frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                            Text("回复内容")
                            TextEditor(text: $mail.replyText).frame(minHeight: 100, maxHeight: 160).border(.quaternary)
                            Button("发送回复到原邮件线程") { mail.sendReply(prefix: prefix) }.disabled(mail.busy || mail.replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        } else { ContentUnavailableView("选择一封真实邮件", systemImage: "envelope") }
                    }.padding(10).frame(minWidth: 400)
                }
            }
            Spacer(minLength: 0)
            Text("当前可实际授权、读取最近 30 封收件箱邮件及手动回复。自动监听和 Agent 执行尚未接入；QQ 邮箱接入待实现。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20)
    }
}
