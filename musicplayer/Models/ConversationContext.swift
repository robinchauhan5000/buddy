import Foundation

struct ConversationContext: Codable, Identifiable {
    let id: UUID
    let conversationSummary: String
    let previousAnswerSummary: PreviousAnswerSummary
    let currentIntent: String
    let relatedToPrevious: Bool
    let timestamp: Date
    
    init(
        id: UUID = UUID(),
        conversationSummary: String,
        previousAnswerSummary: PreviousAnswerSummary,
        currentIntent: String = "deep_dive",
        relatedToPrevious: Bool = true,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.conversationSummary = conversationSummary
        self.previousAnswerSummary = previousAnswerSummary
        self.currentIntent = currentIntent
        self.relatedToPrevious = relatedToPrevious
        self.timestamp = timestamp
    }
    
    func toJSON() -> [String: Any] {
        return [
            "context": [
                "conversation_summary": conversationSummary,
                "previous_answer_summary": [
                    "ai_technical_summary": previousAnswerSummary.aiTechnicalSummary
                ],
                "current_intent": currentIntent,
                "related_to_previous": relatedToPrevious
            ]
        ]
    }
}

struct PreviousAnswerSummary: Codable {
    let aiTechnicalSummary: String
    
    init(aiTechnicalSummary: String) {
        self.aiTechnicalSummary = aiTechnicalSummary
    }
}

struct ConversationContextHistory {
    private(set) var contexts: [ConversationContext] = []
    private let maxHistoryCount = 10
    
    mutating func addContext(_ context: ConversationContext) {
        contexts.append(context)
        
        // Keep only the last 10 contexts
        if contexts.count > maxHistoryCount {
            contexts.removeFirst(contexts.count - maxHistoryCount)
        }
    }
    
    mutating func clearHistory() {
        contexts.removeAll()
    }
    
    func getContextForPrompt() -> [[String: Any]] {
        return contexts.map { $0.toJSON() }
    }
    
    func getLastContext() -> ConversationContext? {
        return contexts.last
    }
    
    var isEmpty: Bool {
        return contexts.isEmpty
    }
    
    var count: Int {
        return contexts.count
    }
    
    /// Print all stored contexts as they will be sent to the AI as previous chat history.
    func printContextsAsPreviousChatHistory() {
        guard !contexts.isEmpty else { return }
        print("📋 ConversationContext (previous chat history) – \(contexts.count) context(s) used for next prompt:")
        for (index, ctx) in contexts.enumerated() {
            print("   --- Context \(index + 1)/\(contexts.count) ---")
            print("   conversation_summary: \(ctx.conversationSummary.prefix(300))\(ctx.conversationSummary.count > 300 ? "…" : "")")
            print("   ai_technical_summary: \(ctx.previousAnswerSummary.aiTechnicalSummary.prefix(300))\(ctx.previousAnswerSummary.aiTechnicalSummary.count > 300 ? "…" : "")")
            print("   current_intent: \(ctx.currentIntent) | related_to_previous: \(ctx.relatedToPrevious)")
        }
        print("   --- END ConversationContext ---")
    }
}
