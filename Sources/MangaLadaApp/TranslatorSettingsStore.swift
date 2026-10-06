import Foundation
import MangaLadaCore
import MangaLadaRendering
import Security

struct TranslatorSettingsStore {
    func load() throws -> (LocalTranslatorConfiguration, MangaTypography) {
        var configuration = try LocalTranslatorConfiguration.load(configURL: AppPaths.configuration)
        if configuration.provider == .googleWeb { configuration.provider = .ollama }
        if configuration.gemini.apiKey.isEmpty { configuration.gemini.apiKey = try readAPIKey() }
        var typography: MangaTypography
        if let data = UserDefaults.standard.data(forKey: "translator.typography") {
            typography = try JSONDecoder().decode(MangaTypography.self, from: data)
        } else { typography = MangaTypography() }
        if typography.effectStyleID == nil { typography.effectStyleID = "automatic" }
        return (configuration, typography)
    }
    func save(configuration: LocalTranslatorConfiguration, typography: MangaTypography) throws {
        try configuration.save(to: AppPaths.configuration)
        try saveAPIKey(configuration.gemini.apiKey)
        UserDefaults.standard.set(try JSONEncoder().encode(typography), forKey: "translator.typography")
    }
    private var keyQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: MangaLadaEdition.geminiKeychainService, kSecAttrAccount as String: "api-key"]
    }
    private func readAPIKey() throws -> String {
        var query = keyQuery; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = item as? Data, let key = String(data: data, encoding: .utf8) else { throw KeychainError(status: status) }
        return key
    }
    private func saveAPIKey(_ key: String) throws {
        let data = Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        if data.isEmpty {
            let status = SecItemDelete(keyQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
            return
        }
        let status = SecItemUpdate(keyQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = keyQuery; query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(query as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess { throw KeychainError(status: status) }
    }
}

private struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "API 키를 키체인에서 처리하지 못했습니다. \(SecCopyErrorMessageString(status, nil) as String? ?? String(status))" }
}
