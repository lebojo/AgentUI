import Foundation
import Security

protocol PairingCodeStore: Sendable {
    func load() throws -> String?
    func save(_ code: String) throws
}

enum PairingCodeStores {
    static func make(account: String) -> any PairingCodeStore {
        #if DEBUG
        if let code = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[account] as? String {
            return FixedPairingCodeStore(code: code)
        }
        if ProcessInfo.processInfo.environment["AGENTUI_STATE_DIRECTORY"] != nil { return FixedPairingCodeStore(code: nil) }
        #endif
        return KeychainPairingCodeStore(account: account)
    }
}

struct FixedPairingCodeStore: PairingCodeStore {
    let code: String?

    func load() -> String? { code }
    func save(_ code: String) {}
}

struct KeychainPairingCodeStore: PairingCodeStore {
    let account: String

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "ch.jordanchap.agentui.pairing",
         kSecAttrAccount as String: account]
    }

    func load() throws -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError.unreadable(status) }
        return String(decoding: data, as: UTF8.self)
    }

    func save(_ code: String) throws {
        let value = [kSecValueData as String: Data(code.utf8)]
        var status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(value) { $1 }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }
}

enum KeychainError: Error, Equatable, LocalizedError, Sendable {
    case unexpectedStatus(OSStatus)
    case unreadable(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status): "Impossible d’enregistrer le code d’appairage dans le trousseau (erreur \(status))."
        case .unreadable(let status): "Impossible de lire le code d’appairage dans le trousseau (erreur \(status)). Déverrouille le trousseau puis réactive l’accès local."
        }
    }
}
