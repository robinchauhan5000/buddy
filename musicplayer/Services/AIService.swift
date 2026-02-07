import Foundation

protocol AIServiceProtocol {
    func streamResponse(
        prompt: String,
        systemPrompt: String,
        provider: AIProvider,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) async
}

final class AIService: AIServiceProtocol {
    private let httpClient: HTTPClient
    
    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }
    
    func streamResponse(
        prompt: String,
        systemPrompt: String,
        provider: AIProvider,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) async {
        let endpoint = getEndpoint(for: provider)
        let body = buildRequestBody(prompt: prompt, systemPrompt: systemPrompt, provider: provider)
        
        do {
            try await httpClient.stream(
                endpoint,
                body: body,
                headers: getHeaders(for: provider)
            ) { jsonPayload in
                // jsonPayload is now a complete JSON string, not raw bytes
                onChunk(jsonPayload)
            }
            onComplete()
        } catch {
            onError(error)
        }
    }
    
    private func getEndpoint(for provider: AIProvider) -> String {
        switch provider {
        case .openAI:
            return "/v1/chat/completions"
        case .claude:
            return "/v1/messages"
        case .gemini:
            return "/v1/models/gemini-pro:streamGenerateContent"
        case .grok:
            return "/v1/responses"
        case .deepseek:
            return "/chat/completions"
        }
    }
    
    private func buildRequestBody(prompt: String, systemPrompt: String, provider: AIProvider) -> [String: Any] {
        switch provider {
        case .openAI:
            return [
                "model": "gpt-4",
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": prompt]
                ],
                "stream": true
            ]
        case .claude:
            return [
                "model": "claude-sonnet-4-20250514",
                "max_tokens": 8192,
                "system": systemPrompt,
                "messages": [["role": "user", "content": [["type": "text", "text": prompt]]]],
                "stream": true
            ]
        case .gemini:
            return [
                "contents": [
                    ["parts": [["text": "\(systemPrompt)\n\n\(prompt)"]]]
                ]
            ]
        case .grok:
            return [
                "model": "grok-4",
                "input": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": prompt]
                ]
            ]
        case .deepseek:
            return [
                "model": "deepseek-chat",
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": prompt]
                ],
                "stream": false
            ]
        }
    }
    
    private func getHeaders(for provider: AIProvider) -> [String: String] {
        switch provider {
        case .openAI:
            return [
                "Content-Type": "application/json",
                "Authorization": "Bearer YOUR_API_KEY"
            ]
        case .claude:
            return [
                "Content-Type": "application/json",
                "anthropic-version": "2023-06-01",
                "x-api-key": "YOUR_API_KEY"
            ]
        case .gemini:
            return [
                "Content-Type": "application/json"
            ]
        case .grok:
            return [
                "Content-Type": "application/json",
                "Authorization": "Bearer YOUR_API_KEY"
            ]
        case .deepseek:
            return [
                "Content-Type": "application/json",
                "Authorization": "Bearer YOUR_API_KEY"
            ]
        }
    }
}

enum AIServiceError: Error {
    case invalidResponse
    case networkError
    case decodingError
}
