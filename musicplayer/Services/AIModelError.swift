import Foundation

struct AIModelError: Error {
    let message: String
    let provider: String?
    
    init(_ message: String, provider: String? = nil) {
        self.message = message
        self.provider = provider
    }
}

extension AIModelError: LocalizedError {
    var errorDescription: String? {
        if let provider = provider {
            return "AIModelError (\(provider)): \(message)"
        }
        return "AIModelError: \(message)"
    }
}
