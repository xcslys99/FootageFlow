import Foundation
import Security

enum KeychainService {
    private static let service = "app.footageflow.api-keys"
    private static let legacyService = "com.footagefinder.api-keys"

    static func read(_ provider: ProviderID) -> String {
        if let value = read(provider, service: service) { return value }
        guard let legacy = read(provider, service: legacyService) else { return "" }
        try? save(legacy, provider: provider)
        return legacy
    }

    private static func read(_ provider: ProviderID, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    static func save(_ value: String, provider: ProviderID) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
        if value.isEmpty {
            SecItemDelete(base as CFDictionary)
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }
    }
}

enum KeychainError: LocalizedError {
    case status(OSStatus)
    var errorDescription: String? { "无法安全保存 API Key（Keychain 状态 \(code)）" }
    private var code: OSStatus { if case .status(let code) = self { code } else { -1 } }
}
