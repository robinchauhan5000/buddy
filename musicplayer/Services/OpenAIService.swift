import Foundation

final class OpenAIService: AIModel {
    private let httpClient: HTTPClient
    private let apiKey: String
    private static let model = "gpt-4o"
    private static let visionModel = "gpt-4o"
    
    init(apiKey: String) {
        self.apiKey = apiKey
        self.httpClient = HTTPClient(
            baseURL: "https://api.openai.com/v1",
            defaultHeaders: [
                "Content-Type": "application/json",
                "Authorization": "Bearer \(apiKey)"
            ],
            timeout: 120
        )
    }
    
    func getInterviewResponse(
        prompt: String,
        category: Category,
        language: ProgrammingLanguage,
        imageData: Data? = nil
    ) async throws -> AIResponse {
        let systemPrompt: String
        let userPrompt: String
        
        if imageData != nil {
            systemPrompt = PromptBuilder.buildImageAnalysisPrompt(userQuestion: prompt.isEmpty ? nil : prompt)
            userPrompt = "Analyze this image and provide the answer in the specified JSON format."
        } else if category == .systemDesign {
            systemPrompt = PromptBuilder.buildSystemPrompt(for: .systemDesign, language: language)
            userPrompt = PromptBuilder.buildSystemDesignFullUserPrompt(question: prompt)
        } else {
            systemPrompt = PromptBuilder.buildSystemPrompt(for: category, language: language)
            userPrompt = prompt
        }
        
        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]
        
        if let imageData = imageData {
            let base64Image = imageData.base64EncodedString()
            messages.append([
                "role": "user",
                "content": [
                    ["type": "text", "text": userPrompt],
                    [
                        "type": "image_url",
                        "image_url": [
                            "url": "data:image/png;base64,\(base64Image)"
                        ]
                    ]
                ]
            ])
        } else {
            messages.append(["role": "user", "content": userPrompt])
        }
        
        let body: [String: Any] = [
            "model": imageData != nil ? Self.visionModel : Self.model,
            "messages": messages,
            "response_format": ["type": "json_object"]
        ]
        
        let (data, response) = try await httpClient.postRaw("/chat/completions", body: body)
        
        guard response.statusCode == 200 else {
            throw AIModelError(
                "API request failed with status \(response.statusCode)",
                provider: "OpenAI"
            )
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIModelError("Invalid response format", provider: "OpenAI")
        }
        
        guard let contentData = content.data(using: .utf8) else {
            throw AIModelError("Failed to parse content", provider: "OpenAI")
        }
        
        return try JSONDecoder().decode(AIResponse.self, from: contentData)
    }
    
    func streamInterviewResponse(
        prompt: String,
        category: Category,
        language: ProgrammingLanguage,
        includeOptionalCodePhase: Bool = false,
        imageData: Data? = nil
    ) -> AsyncThrowingStream<StreamingResponse, Error> {
        if category == .systemDesign && imageData == nil {
            return streamPhasedSystemDesign(
                prompt: prompt,
                language: language,
                includeOptionalCodePhase: includeOptionalCodePhase
            )
        }
        
        let systemPrompt: String
        let userPrompt: String
        
        if imageData != nil {
            systemPrompt = PromptBuilder.buildImageAnalysisPrompt(userQuestion: prompt.isEmpty ? nil : prompt)
            userPrompt = "Analyze this image and provide the answer in the specified JSON format."
        } else {
            systemPrompt = PromptBuilder.buildSystemPrompt(for: category, language: language)
            userPrompt = prompt
        }
        
        return streamOpenAIResponse(
            systemPrompt: systemPrompt,
            prompt: userPrompt,
            language: language,
            imageData: imageData
        )
    }
    
    private func streamPhasedSystemDesign(
        prompt: String,
        language: ProgrammingLanguage,
        includeOptionalCodePhase: Bool
    ) -> AsyncThrowingStream<StreamingResponse, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                var phaseSections: [Int: [MessageSection]] = [:]
                var title = ""
                let baseSystemPrompt = PromptBuilder.buildSystemPrompt(for: .systemDesign, language: language)
                let lastPhase = includeOptionalCodePhase ? 7 : 6
                
                do {
                    for phase in 1...lastPhase {
                        let userPrompt = PromptBuilder.buildSystemDesignPhaseUserPrompt(
                            phase: phase,
                            question: prompt
                        )
                        
                        let phaseStream = streamOpenAIResponse(
                            systemPrompt: baseSystemPrompt,
                            prompt: userPrompt,
                            language: language,
                            imageData: nil
                        )
                        
                        for try await phaseResponse in phaseStream {
                            if title.isEmpty && !phaseResponse.title.isEmpty {
                                title = phaseResponse.title
                            }
                            phaseSections[phase] = phaseResponse.sections
                            
                            let mergedSections = mergePhaseSections(phaseSections)
                            continuation.yield(
                                StreamingResponse(
                                    title: title,
                                    sections: mergedSections,
                                    isComplete: false
                                )
                            )
                        }
                    }
                    
                    let finalSections = mergePhaseSections(phaseSections)
                    continuation.yield(
                        StreamingResponse(
                            title: title,
                            sections: finalSections,
                            isComplete: true
                        )
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private func mergePhaseSections(_ phaseSections: [Int: [MessageSection]]) -> [MessageSection] {
        let phases = phaseSections.keys.sorted()
        return phases.flatMap { phaseSections[$0] ?? [] }
    }
    
    private func streamOpenAIResponse(
        systemPrompt: String,
        prompt: String,
        language: ProgrammingLanguage,
        imageData: Data?
    ) -> AsyncThrowingStream<StreamingResponse, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
                    continuation.finish(throwing: AIModelError("Invalid URL", provider: "OpenAI"))
                    return
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                
                var messages: [[String: Any]] = [
                    ["role": "system", "content": systemPrompt]
                ]
                
                if let imageData = imageData {
                    let base64Image = imageData.base64EncodedString()
                    messages.append([
                        "role": "user",
                        "content": [
                            ["type": "text", "text": prompt],
                            [
                                "type": "image_url",
                                "image_url": [
                                    "url": "data:image/png;base64,\(base64Image)"
                                ]
                            ]
                        ]
                    ])
                } else {
                    messages.append(["role": "user", "content": prompt])
                }
                
                let body: [String: Any] = [
                    "model": imageData != nil ? Self.visionModel : Self.model,
                    "stream": true,
                    "messages": messages,
                    "response_format": ["type": "json_object"]
                ]
                
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
                
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: AIModelError("Invalid response", provider: "OpenAI"))
                        return
                    }

                    guard httpResponse.statusCode == 200 else {
                        let errorBody = await readErrorBody(from: bytes)
                        let errorDetail = parseOpenAIErrorMessage(from: errorBody)
                        let message = errorDetail ?? "HTTP \(httpResponse.statusCode)"
                        continuation.finish(
                            throwing: AIModelError(
                                "Streaming failed: \(message)",
                                provider: "OpenAI"
                            )
                        )
                        return
                    }
                    
                    let parser = StreamingResponseParser()
                    
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let data = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                            
                            if data == "[DONE]" {
                                if let response = parser.finalize() {
                                    continuation.yield(response)
                                }
                                break
                            }
                            
                            guard let jsonData = data.data(using: .utf8),
                                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                                  let choices = json["choices"] as? [[String: Any]],
                                  let firstChoice = choices.first,
                                  let delta = firstChoice["delta"] as? [String: Any],
                                  let content = delta["content"] as? String else {
                                continue
                            }
                            
                            if let response = parser.addChunk(content) {
                                continuation.yield(response)
                            }
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func readErrorBody(from bytes: URLSession.AsyncBytes) async -> String {
        var lines: [String] = []
        var count = 0

        do {
            for try await line in bytes.lines {
                lines.append(line)
                count += 1
                if count >= 20 {
                    break
                }
            }
        } catch {
            return ""
        }

        return lines.joined(separator: "\n")
    }

    private func parseOpenAIErrorMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else {
            return nil
        }

        let message = error["message"] as? String
        let type = error["type"] as? String

        switch (type, message) {
        case let (.some(type), .some(message)):
            return "\(type): \(message)"
        case let (_, .some(message)):
            return message
        default:
            return nil
        }
    }
}
