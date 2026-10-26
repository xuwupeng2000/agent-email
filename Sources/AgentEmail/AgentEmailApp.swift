import SwiftUI

@main
struct AgentEmailApp: App {
    var body: some Scene {
        WindowGroup("Agent Email") { SettingsView().frame(minWidth: 600, minHeight: 560) }
    }
}

struct SettingsView: View {
    @AppStorage("provider") private var provider = "Outlook"
    @AppStorage("address") private var address = ""
    @AppStorage("prefix") private var prefix = "[AGENT]"
    @State private var subject = "[AGENT] 帮我检查项目状态"
    @State private var sender = ""
    @State private var result = ""

    var body: some View {
        Form {
            Section("邮箱") {
                Picker("服务商", selection: $provider) {
                    Text("Outlook").tag("Outlook")
                    Text("QQ 邮箱").tag("QQ")
                }
                TextField("自己的邮箱地址", text: $address)
                Text(provider == "Outlook" ? "计划使用 Microsoft OAuth 登录，不收集邮箱密码。" : "计划使用 QQ 邮箱授权码，不使用网页登录密码。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("尚未连接邮箱；当前只保存配置并验证触发规则。")
                    .foregroundStyle(.orange)
            }
            Section("触发规则") {
                TextField("主题前缀", text: $prefix)
                Text("仅处理自己发给自己的邮件。常驻程序收信，有任务时才启动 Agent；AI 不循环等待邮件。")
                Text("回复去掉触发前缀，并标记为自动回复。")
            }
            Section("本地规则预览（不会收发邮件或执行 Agent）") {
                TextField("模拟发件人", text: $sender)
                TextField("模拟邮件主题", text: $subject)
                Button("检查是否触发") {
                    let accepted = TriggerPolicy(ownAddress: address, prefix: prefix)
                        .accepts(sender: sender, recipients: [address], subject: subject)
                    result = accepted ? "符合触发规则；实际执行尚未接入。" : "忽略：地址、主题前缀或任务内容不符合规则。"
                }
                if !result.isEmpty { Text(result).textSelection(.enabled) }
            }
            Section("实现进度") {
                Text("已完成：独立 Mac 工程、邮箱配置界面、主题触发规则。")
                Text("待完成：真实邮箱授权与监听、Agent 调用、同线程邮件回复、去重和失败重试。")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
