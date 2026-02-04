import Foundation

struct AppConfig {
    static let openAIAPIKey: String = {
        if let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !apiKey.isEmpty {
            return apiKey
        }
        return ""
    }()
    
    static let grokAPIKey: String = {
        // Try GROK_API_KEY first, then fall back to XAI_API_KEY
        if let apiKey = ProcessInfo.processInfo.environment["GROK_API_KEY"], !apiKey.isEmpty {
            return apiKey
        }
        if let apiKey = ProcessInfo.processInfo.environment["XAI_API_KEY"], !apiKey.isEmpty {
            return apiKey
        }
        return ""
    }()
    
    static let deepseekAPIKey: String = {
        if let apiKey = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !apiKey.isEmpty {
            return apiKey
        }
        return ""
    }()
    
    static let isConfigured: Bool = {
        !openAIAPIKey.isEmpty || !grokAPIKey.isEmpty || !deepseekAPIKey.isEmpty
    }()
}
