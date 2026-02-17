import Foundation
import Security

/// Simple Keychain wrapper for storing API keys securely.
enum KeychainService {
    private static let serviceName = "com.sbbender.apikeys"

    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete existing first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Don't store empty values
        guard !value.isEmpty else { return }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Convenience Keys

    static let anthropicAPIKey = "anthropic_api_key"
    static let openaiAPIKey = "openai_api_key"
    static let ollamaBaseURL = "ollama_base_url"
    static let groqAPIKey = "groq_api_key"
    static let deepinfraAPIKey = "deepinfra_api_key"

    /// Get Anthropic key: Keychain first, then env var fallback
    static var anthropicKey: String {
        get { load(key: anthropicAPIKey) ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? "" }
        set { save(key: anthropicAPIKey, value: newValue) }
    }

    /// Get OpenAI key: Keychain first, then env var fallback
    static var openaiKey: String {
        get { load(key: openaiAPIKey) ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "" }
        set { save(key: openaiAPIKey, value: newValue) }
    }

    /// Get Ollama base URL
    static var ollamaURL: String {
        get { load(key: ollamaBaseURL) ?? "http://localhost:11434" }
        set { save(key: ollamaBaseURL, value: newValue) }
    }

    /// Get Groq key: Keychain first, then env var fallback
    static var groqKey: String {
        get { load(key: groqAPIKey) ?? ProcessInfo.processInfo.environment["GROQ_API_KEY"] ?? "" }
        set { save(key: groqAPIKey, value: newValue) }
    }

    /// Get DeepInfra key: Keychain first, then env var fallback
    static var deepinfraKey: String {
        get { load(key: deepinfraAPIKey) ?? ProcessInfo.processInfo.environment["DEEPINFRA_API_KEY"] ?? "" }
        set { save(key: deepinfraAPIKey, value: newValue) }
    }
}
