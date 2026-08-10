import Foundation

#if os(macOS)
  import Security
#endif

protocol CredentialStoring: Sendable {
  func read(_ provider: ProviderID) -> String
  func save(_ value: String, provider: ProviderID) throws
}

enum KeychainService {
  private static let store: any CredentialStoring = SystemCredentialStore()

  static func read(_ provider: ProviderID) -> String { store.read(provider) }
  static func save(_ value: String, provider: ProviderID) throws {
    try store.save(value, provider: provider)
  }
}

#if os(macOS)
  private struct SystemCredentialStore: CredentialStoring {
    private let service = "app.footageflow.api-keys"
    private let legacyService = "com.footagefinder.api-keys"

    func read(_ provider: ProviderID) -> String {
      if let value = read(provider, service: service) { return value }
      guard let legacy = read(provider, service: legacyService) else { return "" }
      try? save(legacy, provider: provider)
      return legacy
    }

    private func read(_ provider: ProviderID, service: String) -> String? {
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: provider.rawValue,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
      ]
      var result: CFTypeRef?
      guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
        let data = result as? Data,
        let value = String(data: data, encoding: .utf8)
      else { return nil }
      return value
    }

    func save(_ value: String, provider: ProviderID) throws {
      let base: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: provider.rawValue,
      ]
      if value.isEmpty {
        SecItemDelete(base as CFDictionary)
        let legacy: [String: Any] = [
          kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: legacyService,
          kSecAttrAccount as String: provider.rawValue,
        ]
        SecItemDelete(legacy as CFDictionary)
        return
      }
      let data = Data(value.utf8)
      let status = SecItemUpdate(
        base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
      if status == errSecItemNotFound {
        var add = base
        add[kSecValueData as String] = data
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
          throw CredentialStoreError.status(Int32(addStatus))
        }
      } else if status != errSecSuccess {
        throw CredentialStoreError.status(Int32(status))
      }
    }
  }
#else
  private struct SystemCredentialStore: CredentialStoring {
    func read(_ provider: ProviderID) -> String { "" }
    func save(_ value: String, provider: ProviderID) throws {
      guard value.isEmpty else { throw CredentialStoreError.unavailable }
    }
  }
#endif

enum CredentialStoreError: LocalizedError {
  case status(Int32)
  case unavailable

  var errorDescription: String? {
    switch self {
    case .status(let code): tr("error.keychain", code)
    case .unavailable: tr("error.credentialStoreUnavailable")
    }
  }
}
