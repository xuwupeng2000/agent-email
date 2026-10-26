import Foundation
import Security

struct MailItem: Decodable, Identifiable {
    struct Person: Decodable { let address: String? }
    struct Recipient: Decodable { let emailAddress: Person }
    struct Body: Decodable { let content: String? }
    let id: String
    let subject: String?
    let bodyPreview: String?
    let from: Recipient?
    let toRecipients: [Recipient]?
    let body: Body?
}

struct OutlookFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct DeviceGrant: Decodable {
    let device_code: String
    let user_code: String
    let verification_uri: String
    let expires_in: Int
    let interval: Int?
}

private struct Tokens: Codable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int
    var storedAt: Date?
}

actor OutlookClient {
    private let session: URLSession
    private let clientID: String
    private var tokens: Tokens?
    private let scope = "https://graph.microsoft.com/User.Read https://graph.microsoft.com/Mail.Read https://graph.microsoft.com/Mail.Send offline_access"
    init(clientID: String, session: URLSession = .shared) { self.clientID = clientID; self.session = session }

    private func form(_ fields: [String: String], endpoint: String) async throws -> (Data, Int) {
        var req = URLRequest(url: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/" + endpoint)!)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var parts = URLComponents()
        parts.queryItems = fields.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await session.data(for: req)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
    private func failure(_ data: Data, fallback: String) -> OutlookFailure {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let code = obj?["error"] as? String {
            // Never include tokens or raw HTTP responses in UI/logs.
            return OutlookFailure(message: "Microsoft 授权错误：\(code)。请检查应用注册、账号类型和公共客户端设置。")
        }
        if let error = obj?["error"] as? [String: Any], let code = error["code"] as? String {
            return OutlookFailure(message: "Microsoft Graph 错误：\(code)")
        }
        return OutlookFailure(message: fallback)
    }
    func beginLogin() async throws -> DeviceGrant {
        guard UUID(uuidString: clientID) != nil else { throw OutlookFailure(message: "请先填写注册应用的 Client ID。") }
        let (data, status) = try await form(["client_id": clientID, "scope": scope], endpoint: "devicecode")
        guard status == 200 else { throw failure(data, fallback: "无法开始 Microsoft 登录（HTTP \(status)）。") }
        return try JSONDecoder().decode(DeviceGrant.self, from: data)
    }
    func finishLogin(_ grant: DeviceGrant) async throws {
        let deadline = Date().addingTimeInterval(Double(grant.expires_in))
        var interval = grant.interval ?? 5
        while Date() < deadline {
            try await Task.sleep(for: .seconds(interval))
            try Task.checkCancellation()
            let (data, status) = try await form(["client_id": clientID, "grant_type": "urn:ietf:params:oauth:grant-type:device_code", "device_code": grant.device_code], endpoint: "token")
            if status == 200 { try Task.checkCancellation(); try save(data); return }
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            switch obj?["error"] as? String {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            default: throw failure(data, fallback: "登录未完成，请重新连接。")
            }
        }
        throw OutlookFailure(message: "验证码已过期，请重新连接 Outlook。")
    }
    private var keyQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.agentemail.outlook",
         kSecAttrAccount as String: clientID]
    }
    private func save(_ data: Data) throws {
        var fresh = try JSONDecoder().decode(Tokens.self, from: data)
        if fresh.refresh_token == nil, let old = tokens {
            fresh = Tokens(access_token: fresh.access_token, refresh_token: old.refresh_token, expires_in: fresh.expires_in, storedAt: nil)
        }
        fresh.storedAt = Date()
        let encoded = try JSONEncoder().encode(fresh)
        let update = SecItemUpdate(keyQuery as CFDictionary, [kSecValueData as String: encoded] as CFDictionary)
        if update == errSecItemNotFound {
            var insert = keyQuery
            insert[kSecValueData as String] = encoded
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw OutlookFailure(message: "无法将授权存入钥匙串。") }
        } else if update != errSecSuccess { throw OutlookFailure(message: "无法更新钥匙串授权。") }
        tokens = fresh
    }
    func restore() throws {
        var query = keyQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { throw OutlookFailure(message: "没有已保存的 Outlook 授权，请先连接。") }
        tokens = try JSONDecoder().decode(Tokens.self, from: data)
    }
    func disconnect() throws {
        let result = SecItemDelete(keyQuery as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw OutlookFailure(message: "无法删除本机授权。") }
        tokens = nil
    }
    private func token(force: Bool = false) async throws -> String {
        guard let current = tokens else { throw OutlookFailure(message: "尚未连接 Outlook。") }
        if !force && Date().timeIntervalSince(current.storedAt ?? .distantPast) < Double(current.expires_in - 120) { return current.access_token }
        guard let refresh = current.refresh_token else { throw OutlookFailure(message: "授权已过期，请重新连接。") }
        let (data, status) = try await form(["client_id": clientID, "grant_type": "refresh_token", "refresh_token": refresh, "scope": scope], endpoint: "token")
        guard status == 200 else { throw failure(data, fallback: "刷新授权失败，请重新登录。") }
        try save(data)
        return tokens!.access_token
    }
    private func request(_ path: String, method: String = "GET", payload: [String: Any]? = nil) async throws -> Data {
        for attempt in 0...1 {
            var req = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0" + path)!)
            req.httpMethod = method
            req.timeoutInterval = 30
            req.setValue("Bearer \(try await token(force: attempt == 1))", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("outlook.body-content-type=\"text\"", forHTTPHeaderField: "Prefer")
            if let payload { req.httpBody = try JSONSerialization.data(withJSONObject: payload) }
            let (data, response) = try await session.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 && attempt == 0 { continue }
            guard (200..<300).contains(status) else { throw failure(data, fallback: "邮箱请求失败（HTTP \(status)）。") }
            return data
        }
        throw OutlookFailure(message: "授权失败，请重新连接。")
    }
    func address() async throws -> String {
        struct Profile: Decodable { let mail: String?; let userPrincipalName: String? }
        let profile = try JSONDecoder().decode(Profile.self, from: await request("/me?$select=mail,userPrincipalName"))
        guard let address = profile.mail ?? profile.userPrincipalName, address.contains("@") else { throw OutlookFailure(message: "无法取得账号邮箱地址。") }
        return address
    }
    func inbox() async throws -> [MailItem] {
        struct Page: Decodable { let value: [MailItem] }
        return try JSONDecoder().decode(Page.self, from: await request("/me/mailFolders/inbox/messages?$top=30&$orderby=receivedDateTime%20desc&$select=id,subject,bodyPreview,from,toRecipients,body")).value
    }
    func reply(to id: String, text: String, subject: String) async throws {
        guard let escaped = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { throw OutlookFailure(message: "无效邮件 ID。") }
        _ = try await request("/me/messages/\(escaped)/reply", method: "POST", payload: ["message": ["subject": "Re: " + subject, "body": ["contentType": "Text", "content": text]]])
    }
}
