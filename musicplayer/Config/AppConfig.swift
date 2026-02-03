import Foundation

struct AppConfig {
    static let openAIAPIKey: String = {
        if let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !apiKey.isEmpty {
            return apiKey
        }
        return ""
    }()
    
    static let isConfigured: Bool = {
        !openAIAPIKey.isEmpty
    }()
}
