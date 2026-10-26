# Agent Email

一个独立的原生 Mac 应用：用户给自己发邮件，主题以 `[AGENT]` 开头，软件收到后触发本机 Agent，完成后通过邮件回复。

它与 Agent Mailbox 是两个产品：Agent Mailbox 用于 Agent 之间的文本交流；这里用于用户通过邮件向本机 Agent 下达任务。

## 已确认的范围

- 第一版只做 macOS，使用 SwiftUI；iPhone / iPad 暂不实现。
- 仅支持 Outlook 和 QQ 邮箱。
- 提供邮箱配置界面，用户给自己发信。
- 用可见的主题前缀触发，例如 `[AGENT] 帮我检查项目状态`，不用隐藏邮件头。
- 普通收信服务常驻；有新任务才启动 Agent，不让 AI 循环等待邮件。
- 执行结果回复原邮件线程；回复移除触发前缀并标记自动回复，避免循环。

## 当前里程碑

已实现：原生 Mac 工程、Outlook / QQ 配置选择、地址和前缀本地保存、可测试的触发判断、界面中的本地规则预览。

**尚未实现真实收发邮件或 Agent 执行。** 当前界面会明确提示未连接，不会显示伪造的邮件或执行成功状态。

## 后续阶段

1. Outlook：注册 Microsoft 公共客户端，OAuth 登录，凭据存 Keychain；接入收发与增量读取。仅有新邮件时唤起处理。
2. QQ：授权码存 Keychain，IMAP 收信、SMTP 回复；验证 IMAP IDLE 支持情况，断线重连，必要时由普通程序定时检查。AI 不参与轮询。
3. 配置本机 Agent 的可执行程序及参数，通过 stdin 提交任务，不把邮件正文拼进 shell 命令。
4. Message-ID 去重、UIDVALIDITY/UID 或服务端游标、持久任务状态、超时、失败重试与回复状态。发送结果不确定时避免自动重复发信。
5. 首次启用建立新邮件基线，不自动执行旧邮件；验证自己给自己发信及自动回复不回环。

## 权限和识别

单靠 From 地址和主题前缀不能证明真实身份。真实执行接入前，必须结合可信邮箱服务提供的来源验证、用户批准的操作范围，必要时增加任务签名。邮件正文是任务数据，不得授予高于用户配置的权限。第一版不处理附件或引用历史中的额外指令。

配置保存在本机 UserDefaults；尚未收集密码或令牌。后续凭据只存 Keychain，不能提交到仓库或日志。

## 开发运行

macOS 14+，完整 Xcode / Swift 5.9+；当前无第三方依赖。

```bash
swift run AgentEmail
```

## 参考

- [Microsoft OAuth for mail protocols](https://learn.microsoft.com/en-us/exchange/client-developer/legacy-protocols/how-to-authenticate-an-imap-pop-smtp-application-by-using-oauth/)
- [腾讯 QQ 邮箱授权码与 IMAP/SMTP](https://hiflow.tencent.com/document/applications/qq-mail/)
