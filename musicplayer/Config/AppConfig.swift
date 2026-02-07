import Foundation

struct AppConfig {
    private static let defaults = UserDefaults.standard
    
    // Keys for UserDefaults
    private static let openAIKeyName = "openai_api_key"
    private static let claudeKeyName = "claude_api_key"
    private static let grokKeyName = "grok_api_key"
    private static let deepseekKeyName = "deepseek_api_key"
    private static let geminiKeyName = "gemini_api_key"
    
    // Get API keys from UserDefaults (UI saved)
    static var openAIAPIKey: String {
        get {
            if let savedKey = defaults.string(forKey: openAIKeyName), !savedKey.isEmpty {
                return normalizeKey(savedKey)
            }
            return ""
        }
        set {
            storeKey(newValue, forKey: openAIKeyName)
        }
    }
    
    static var claudeAPIKey: String {
        get {
            if let savedKey = defaults.string(forKey: claudeKeyName), !savedKey.isEmpty {
                return normalizeKey(savedKey)
            }
            return ""
        }
        set {
            storeKey(newValue, forKey: claudeKeyName)
        }
    }
    
    static var grokAPIKey: String {
        get {
            if let savedKey = defaults.string(forKey: grokKeyName), !savedKey.isEmpty {
                return normalizeKey(savedKey)
            }
            return ""
        }
        set {
            storeKey(newValue, forKey: grokKeyName)
        }
    }
    
    static var deepseekAPIKey: String {
        get {
            if let savedKey = defaults.string(forKey: deepseekKeyName), !savedKey.isEmpty {
                return normalizeKey(savedKey)
            }
            return ""
        }
        set {
            storeKey(newValue, forKey: deepseekKeyName)
        }
    }
    
    static var geminiAPIKey: String {
        get {
            if let savedKey = defaults.string(forKey: geminiKeyName), !savedKey.isEmpty {
                return normalizeKey(savedKey)
            }
            return ""
        }
        set {
            storeKey(newValue, forKey: geminiKeyName)
        }
    }
    
    static var isConfigured: Bool {
        !openAIAPIKey.isEmpty || !claudeAPIKey.isEmpty || !grokAPIKey.isEmpty || !deepseekAPIKey.isEmpty || !geminiAPIKey.isEmpty
    }
    
    static func clearAllKeys() {
        defaults.removeObject(forKey: openAIKeyName)
        defaults.removeObject(forKey: claudeKeyName)
        defaults.removeObject(forKey: grokKeyName)
        defaults.removeObject(forKey: deepseekKeyName)
        defaults.removeObject(forKey: geminiKeyName)
        defaults.synchronize() // Force immediate save to disk
    }

    private static func normalizeKey(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("bearer ") {
            return String(trimmed.dropFirst("bearer ".count))
        }
        return trimmed
    }

    private static func storeKey(_ value: String, forKey key: String) {
        let normalized = normalizeKey(value)
        if normalized.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(normalized, forKey: key)
        }
        defaults.synchronize() // Force immediate save to disk
    }
}
