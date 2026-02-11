import Foundation

final class OpenAIService: AIModel {
    private let httpClient: HTTPClient
    private let apiKey: String

    /// Model per category (OpenAI): Normal/System Design/Technical/Coding use full models; Short/Quick/TrueFalse use fast.
    private static func model(for category: Category) -> String {
        switch category {
        case .normal: return "gpt-4o"
        case .shortAnswers: return "gpt-4.1"
        case .quickAnswers: return "gpt-4o"
        case .trueFalse: return "gpt-4o-mini"
        case .systemDesign: return "gpt-5.2"
        case .scenarioBasedSystemDesign: return "gpt-4.2"
        case .technical: return "gpt-5.2"
        case .coding: return "gpt-5.2"
        }
    }

    init(apiKey: String) {
        self.apiKey = apiKey
        self.httpClient = HTTPClient(
            baseURL: "https://api.openai.com/v1",
            defaultHeaders: [
                "Content-Type": "application/json",
                "Authorization": "Bearer \(apiKey)"
            ],
            timeout: 180
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
            systemPrompt = PromptBuilder.buildImageAnalysisPrompt(userQuestion: prompt.isEmpty ? nil : prompt, category: category, language: language)
            userPrompt = prompt.isEmpty ? "Analyze this image and provide the answer in the specified JSON format." : prompt
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
            "model": Self.model(for: category),
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
        imageData: Data? = nil,
        conversationContext: [[String: Any]] = [],
        useInterviewCounterQuestion: Bool = false,
        realTimeStreamingEnabled: Bool = false
    ) -> AsyncThrowingStream<StreamingResponse, Error> {
        if !realTimeStreamingEnabled && category == .systemDesign && !useInterviewCounterQuestion {
            return streamPhasedSystemDesign(
                prompt: prompt,
                language: language,
                includeOptionalCodePhase: includeOptionalCodePhase,
                conversationContext: conversationContext,
                imageData: imageData
            )
        }
        
        let systemPrompt: String
        let userPrompt: String
        
        if imageData != nil {
            systemPrompt = PromptBuilder.buildImageAnalysisPrompt(userQuestion: prompt.isEmpty ? nil : prompt, category: category, language: language, realTimeStreamingEnabled: realTimeStreamingEnabled)
            userPrompt = prompt.isEmpty ? "Analyze this image and provide the answer in the specified JSON format." : prompt
        } else {
            systemPrompt = PromptBuilder.buildSystemPrompt(for: category, language: language, useInterviewCounterQuestion: useInterviewCounterQuestion, realTimeStreamingEnabled: realTimeStreamingEnabled)
            userPrompt = prompt
        }
        
        return streamOpenAIResponse(
            systemPrompt: systemPrompt,
            prompt: userPrompt,
            language: language,
            category: category,
            imageData: imageData,
            conversationContext: conversationContext,
            realTimeStreamingEnabled: realTimeStreamingEnabled
        )
    }
    
    private func streamPhasedSystemDesign(
        prompt: String,
        language: ProgrammingLanguage,
        includeOptionalCodePhase: Bool,
        conversationContext: [[String: Any]],
        imageData: Data? = nil
    ) -> AsyncThrowingStream<StreamingResponse, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                _ = includeOptionalCodePhase
                var phaseSections: [Int: [MessageSection]] = [:]
                var title = ""
                let baseSystemPrompt = PromptBuilder.buildSystemPrompt(for: .systemDesign, language: language)
                let lastPhase = 15
                let questionForPhases = prompt.isEmpty ? "System design question from image" : prompt
                
                do {
                    for phase in 1...lastPhase {
                        if Task.isCancelled {
                            throw CancellationError()
                        }
                        
                        print("\n🔵 ========== PHASE \(phase)/\(lastPhase) START ==========")
                        
                        let userPrompt: String
                        let phaseImageData: Data?
                        if phase == 1, let imageData = imageData {
                            if prompt.isEmpty {
                                userPrompt = PromptBuilder.buildSystemDesignPhase1UserPromptWithImage(language: language)
                            } else {
                                userPrompt = PromptBuilder.buildSystemDesignPhase1UserPromptWithImageAndQuestion(question: prompt, language: language)
                            }
                            phaseImageData = imageData
                        } else {
                            userPrompt = PromptBuilder.buildSystemDesignPhaseUserPrompt(
                                phase: phase,
                                question: questionForPhases,
                                language: language
                            )
                            phaseImageData = nil
                        }
                        
                        print("📝 System Prompt Length: \(baseSystemPrompt.count) characters")
                        print("📝 User Prompt Length: \(userPrompt.count) characters")
                        print("📝 Total Prompt Size: ~\((baseSystemPrompt.count + userPrompt.count) / 1024) KB")
                        print("\n--- SYSTEM PROMPT ---")
                        print(baseSystemPrompt)
                        print("\n--- USER PROMPT ---")
                        print(userPrompt)
                        print("--- END PROMPTS ---\n")
                        
                        let phaseStream = streamOpenAIResponse(
                            systemPrompt: baseSystemPrompt,
                            prompt: userPrompt,
                            language: language,
                            category: .systemDesign,
                            imageData: phaseImageData,
                            conversationContext: conversationContext
                        )
                        
                        for try await phaseResponse in phaseStream {
                            if Task.isCancelled {
                                throw CancellationError()
                            }
                            if title.isEmpty && !phaseResponse.title.isEmpty {
                                title = phaseResponse.title
                                print("📌 Title set: \(title)")
                            }
                            phaseSections[phase] = phaseResponse.sections
                            
                            print("✅ Phase \(phase) received \(phaseResponse.sections.count) section(s)")
                            for section in phaseResponse.sections {
                                print("   - \(section.type)")
                            }
                            
                            print("📊 Current phaseSections state:")
                            for (p, sections) in phaseSections.sorted(by: { $0.key < $1.key }) {
                                print("   Phase \(p): \(sections.count) section(s)")
                            }
                            
                            let mergedSections = mergePhaseSections(phaseSections)
                            print("📊 Merged sections total: \(mergedSections.count)")
                            
                            continuation.yield(
                                StreamingResponse(
                                    title: title,
                                    sections: mergedSections,
                                    isComplete: false
                                )
                            )
                        }
                        
                        print("🔵 ========== PHASE \(phase)/\(lastPhase) COMPLETE ==========\n")
                    }
                    
                    print("\n🎉 ALL PHASES COMPLETE!")
                    print("📊 Total sections collected: \(phaseSections.values.flatMap { $0 }.count)")
                    
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
                    print("❌ ERROR in phased system design: \(error)")
                    continuation.finish(throwing: error)
                }
            }
            
            continuation.onTermination = { _ in
                task.cancel()
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
        category: Category,
        imageData: Data?,
        conversationContext: [[String: Any]] = [],
        realTimeStreamingEnabled: Bool = false
    ) -> AsyncThrowingStream<StreamingResponse, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
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
                
                if !conversationContext.isEmpty {
                    print("📝 OpenAI: Injecting \(conversationContext.count) conversation context(s)")
                    let contextString = conversationContext.map { context in
                        if let jsonData = try? JSONSerialization.data(withJSONObject: context),
                           let jsonString = String(data: jsonData, encoding: .utf8) {
                            return jsonString
                        }
                        return ""
                    }.joined(separator: "\n")
                    
                    messages.append([
                        "role": "system",
                        "content": "Previous conversation context:\n\(contextString)"
                    ])
                } else {
                    print("📝 OpenAI: No conversation context - sending fresh request")
                }
                
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
                
                var body: [String: Any] = [
                    "model": Self.model(for: category),
                    "stream": true,
                    "messages": messages
                ]
                if !realTimeStreamingEnabled {
                    body["response_format"] = ["type": "json_object"]
                }
                
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
                    
                    var chunkCount = 0
                    var totalContent = ""
                    var lastLineWasDone = false
                    print("🌊 Starting to receive SSE stream...")
                    if realTimeStreamingEnabled {
                        let parser = BlockGrammarStreamParser()
                        let throttleInterval = 0.1
                        var pendingContent = ""
                        var lastFlushAt: TimeInterval = 0
                        for try await line in bytes.lines {
                            if Task.isCancelled { throw CancellationError() }
                            if line.isEmpty { continue }
                            if line.hasPrefix("data: ") {
                                let data = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                                if data == "[DONE]" { lastLineWasDone = true; break }
                                guard let jsonData = data.data(using: .utf8),
                                      let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                                      let choices = json["choices"] as? [[String: Any]],
                                      let firstChoice = choices.first,
                                      let delta = firstChoice["delta"] as? [String: Any],
                                      let content = delta["content"] as? String else { continue }
                                if !content.isEmpty {
                                    pendingContent += content
                                    let now = Date().timeIntervalSince1970
                                    if now - lastFlushAt >= throttleInterval {
                                        lastFlushAt = now
                                        if !pendingContent.isEmpty {
                                            if let response = parser.addChunk(pendingContent) {
                                                continuation.yield(response)
                                            }
                                            pendingContent = ""
                                        }
                                    }
                                }
                            }
                        }
                        if !pendingContent.isEmpty { _ = parser.addChunk(pendingContent) }
                        if let response = parser.finalize() {
                            continuation.yield(response)
                        }
                    } else {
                        let parser = StreamingResponseParser()
                        for try await line in bytes.lines {
                            if Task.isCancelled { throw CancellationError() }
                            if line.isEmpty { continue }
                            if line.hasPrefix("data: ") {
                                let data = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                                if data == "[DONE]" {
                                    lastLineWasDone = true
                                    if let response = parser.finalize() { continuation.yield(response) }
                                    break
                                }
                                guard let jsonData = data.data(using: .utf8),
                                      let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                                      let choices = json["choices"] as? [[String: Any]],
                                      let firstChoice = choices.first,
                                      let delta = firstChoice["delta"] as? [String: Any],
                                      let content = delta["content"] as? String else { continue }
                                chunkCount += 1
                                totalContent.append(content)
                                if let response = parser.addChunk(content) { continuation.yield(response) }
                            }
                        }
                        if !lastLineWasDone, let response = parser.finalize() {
                            continuation.yield(response)
                        }
                    }
                    print("✅ Stream processing complete")
                    
                    continuation.finish()
                } catch {
                    let nsError = error as NSError
                    if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                        continuation.finish(throwing: CancellationError())
                    } else {
                        print("❌ ERROR in streamOpenAIResponse: \(error)")
                        continuation.finish(throwing: error)
                    }
                }
            }
            
            continuation.onTermination = { _ in
                task.cancel()
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
