import Foundation

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: MessageRole
    let content: MessageContent
    let timestamp: Date
    let isStreaming: Bool
    
    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: MessageContent,
        timestamp: Date = Date(),
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }
}

enum MessageContent: Equatable {
    case text(String)
    case structured(AIResponse)
    case error(String)
}
