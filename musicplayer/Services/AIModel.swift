import Foundation

protocol AIModel {
    func getInterviewResponse(
        prompt: String,
        category: Category,
        language: ProgrammingLanguage,
        imageData: Data?
    ) async throws -> AIResponse
    
    func streamInterviewResponse(
        prompt: String,
        category: Category,
        language: ProgrammingLanguage,
        includeOptionalCodePhase: Bool,
        imageData: Data?,
        conversationContext: [[String: Any]],
        useInterviewCounterQuestion: Bool,
        realTimeStreamingEnabled: Bool
    ) -> AsyncThrowingStream<StreamingResponse, Error>
}
