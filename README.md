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

已实现：Microsoft 设备码网页登录授权、Keychain 保存与刷新令牌、恢复连接、读取真实收件箱最近 30 封邮件、在原邮件线程中手动回复、断开并删除本机授权。无需邮箱密码或 Client Secret。

**尚未完成真实账号验收**：需要本项目的 Microsoft 应用 Client ID 和用户网页登录授权。当前已运行的自动检查使用模拟 HTTP 响应，不代表真实登录、收信或发送通过。

**尚未实现**：自动监听、Agent 执行与自动回复，以及 QQ 实际收发。

### 开发者首次注册 Outlook 应用（一次）

1. 打开 [Microsoft Entra 应用注册](https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade)，登录有应用注册权限的账号。
2. New registration：名称 `Agent Email`；支持组织目录及个人 Microsoft 账号。此设备码流程不需要 redirect URI。
3. Authentication → Advanced settings → Allow public client flows：Yes。
4. API permissions → Microsoft Graph → Delegated permissions：`User.Read`、`Mail.Read`、`Mail.Send`、`offline_access`。
5. 复制 Overview → Application (client) ID 到 Mac 应用。不创建 Client Secret。
6. 点击连接，在 Microsoft 网页输入应用显示的设备码，核对应用名与读信/发信权限后授权。

Client ID 是开发者的一次性应用注册配置，不应要求每个最终用户自行注册应用。正式分发时需配置本项目的 Client ID；当前开发构建支持手动填写。

授权成功后界面才显示“已连接”，邮箱地址由 Graph 返回。可以刷新、选择邮件、输入回复并发送。回复移除触发前缀，使用 Graph 原线程 reply 操作。自动回复头尚未实现，当前回复不自动触发 Agent。

登录失败只显示错误代码，不输出令牌或原始授权响应。Keychain 中的 refresh token 只保留本机；断开仅删除本机令牌，服务端授权需在 Microsoft 账号管理中撤销。不同开发构建重新签名可能引发钥匙串访问提示。

## 后续阶段

1. Outlook：完成真实账号验收，再接入增量读取和新邮件触发。
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

## 本次验证（2026-10-26）

- macOS release 构建与打包通过；应用已启动显示真实授权入口。
- 模拟网络检查通过：Client ID 校验、设备码响应、授权错误、邮件数据解码。
- 尚未验证：真实 OAuth 授权、令牌刷新、钥匙串写入/恢复、真实邮件读写。

```bash
xcrun swiftc Sources/AgentEmail/OutlookClient.swift tests/OutlookConnectionChecks.swift -o /tmp/agent-email-outlook-checks
/tmp/agent-email-outlook-checks
bash scripts/build-macos.sh
```
