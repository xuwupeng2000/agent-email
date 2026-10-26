import Foundation
import Security

struct QQMessage: Decodable, Identifiable {
    let id: String
    let uid: Int
    let subject: String
    let sender: String
    let recipients: [String]
    let body: String
    let automated: Bool
}
struct QQResult: Decodable {
    let ok: Bool
    let error: String?
    let validity: String?
    let cursor: Int?
    let messages: [QQMessage]?
    let text: String?
    let sent: Bool?
}

enum QQService {
    static func credentials(_ address: String, save secret: String? = nil, delete: Bool = false) throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.agentemail.qq", kSecAttrAccount as String: address.lowercased()]
        if delete {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw OutlookFailure(message: "无法删除钥匙串授权。") }
            return ""
        }
        if let secret {
            let data = Data(secret.utf8)
            let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var insert = query
                insert[kSecValueData as String] = data
                insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw OutlookFailure(message: "无法保存 QQ 授权码。") }
            } else if status != errSecSuccess { throw OutlookFailure(message: "无法更新 QQ 授权码。") }
            return secret
        }
        var read = query
        read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(read as CFDictionary, &result) == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw OutlookFailure(message: "没有保存的 QQ 授权，请输入授权码连接。") }
        return value
    }

    static func call(_ fields: [String: Any]) async throws -> QQResult {
        let input = try JSONSerialization.data(withJSONObject: fields)
        let script = Bundle.main.url(forResource: "qq_bridge", withExtension: "py")
            ?? Bundle.module.url(forResource: "qq_bridge", withExtension: "py", subdirectory: "Resources")
        guard let script else { throw OutlookFailure(message: "应用缺少 QQ 邮箱组件，请重新构建。") }
        return try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [script.path]
            let source = Pipe(), output = Pipe()
            process.standardInput = source
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            // Only a bounded JSON request is written. Credentials are never command arguments.
            try source.fileHandleForWriting.write(contentsOf: input)
            try source.fileHandleForWriting.close()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0, !data.isEmpty else { throw OutlookFailure(message: "QQ 组件未运行成功。需要可用的 Python 3（本机 /usr/bin/python3）。") }
            let result = try JSONDecoder().decode(QQResult.self, from: data)
            guard result.ok else { throw OutlookFailure(message: result.error ?? "QQ 操作失败。") }
            return result
        }.value
    }
}
