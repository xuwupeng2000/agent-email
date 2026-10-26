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

## 当前里程碑：先用 QQ 打通

Mac 版本默认显示 QQ 邮箱。已加入真实 IMAP/SMTP 登录、钥匙串保存和恢复、收件箱读取、同线程回复，以及新邮件触发一次 Codex 后自动邮件回复。Outlook 授权代码保留在另一个页签。

### QQ 实际使用

1. 登录 QQ 邮箱，在设置中开启 IMAP/SMTP，生成授权码。
2. 在软件内填写完整 `@qq.com` 地址及授权码，点击「验证并连接 QQ」。授权码不是登录密码，不要提交到聊天、日志或 Git。
3. 成功时同时验证 `imap.qq.com:993` 和 `smtp.qq.com:465`（TLS）；验证本身不发送邮件。授权码仅保存在 Mac 钥匙串。
4. 核对 Codex 可执行路径和工作目录。点击「开启自动处理」，确认后才会启动监控。
5. 用相同邮箱给自己发新邮件，主题例如 `[AGENT] 请只回复：测试成功`。邮件正文可写任务补充。
6. 程序每 20 秒检查新邮件，符合条件时调用一次已登录的 Codex，完成后通过 SMTP 回复自己。不是 AI 等待循环。

第一版默认只读运行，不能修改文件。工作目录默认是应用专用空目录，可改为需要检查的项目目录。执行继承本机 Codex 登录，忽略用户配置并不指定模型。没有邮件时不调用 AI；有任务时使用 Codex 账号的模型服务与额度。Python 标准库负责邮件协议，Mac 界面负责配置和钥匙串；`/usr/bin/python3` 需可运行（本机已可用）。

首次连接建立新邮件基线，现有邮件不会自动执行。重连沿用持久游标；UIDVALIDITY 变化重新建立基线，不重放旧邮件。每个任务执行前将认领状态原子写入 Application Support，失败或发送结果不确定的任务不会自动重跑。回复使用 In-Reply-To / References、移除主题前缀，增加 Auto-Submitted 和 X-Agent-Email-Reply 防回环；仅发送给配置的自己，不跟随 Reply-To。

停止监听时，已启动的任务可能继续运行到完成或超时（180 秒）；完成后若已停止，则保留结果供界面手动回复。当前网络失败会停止监控并显示错误，需要重新开启。暂不处理附件或富文本任务正文。进程中途退出导致认领未完成时不会自动重跑；需用户检查邮箱和任务状态。

**重要边界**：From 地址、To 和主题前缀不是密码学身份验证；第一版不能防止来源伪造。自动运行只读 Codex，并且结果固定回复到配置的邮箱。不要把它视为可授权任意系统操作的通道。后续若开放写文件等能力，必须先增加任务签名或可信来源验证。

**真实 QQ 邮箱端到端验收仍需用户在软件中输入授权码。** 当前没有真实授权码，所以不能声称 QQ 登录、真实收信或真实发信已通过。

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

1. 用户在软件内完成 QQ 真实邮箱验收：连接、新邮件、Agent、同线程回复与不重复执行。
2. 增加发送失败恢复、断线重连、IMAP IDLE（当前为普通程序 20 秒检查）。
3. Outlook 完成应用注册后进行真实 OAuth 验收，再接入自动新邮件处理。
4. 扩展写操作前增加签名任务、可信来源认证和授权范围；目前只读执行。

## 权限和识别

单靠 From 地址和主题前缀不能证明真实身份。真实执行接入前，必须结合可信邮箱服务提供的来源验证、用户批准的操作范围，必要时增加任务签名。邮件正文是任务数据，不得授予高于用户配置的权限。第一版不处理附件或引用历史中的额外指令。

非敏感配置保存在 UserDefaults；QQ 授权码和 Outlook 令牌保存在 Keychain，不提交仓库、不写日志。任务游标和状态保存在 `~/Library/Application Support/AgentEmail/`，不保存邮件正文或授权码。

## 开发运行

macOS 14+，完整 Xcode / Swift 5.9+；邮件组件需要 Python 3，Agent 需要可用且已登录的 Codex CLI。无第三方 Python 或 Swift 包。

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

## QQ 本次验证（2026-10-26）

- 6 项模拟邮件传输测试通过：中文邮件、过滤回复和其他发件人、连接不发信、新邮件游标与重置、防回环线程回复、拒绝旧邮箱编号发送。
- 实际 Codex CLI 单次调用通过，返回 `AGENT_EMAIL_OK`（不访问真实邮箱）。
- Mac release 构建通过。
- 待用户验收：QQ 真正登录、钥匙串保存/恢复、真实收信、SMTP 回复、自动监控全过程。模拟测试不能替代这些结果。

```bash
python3 -m unittest discover -s tests -p 'test_qq_bridge.py' -v
bash scripts/build-macos.sh
```
