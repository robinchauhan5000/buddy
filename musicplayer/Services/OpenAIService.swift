import Foundation

final class OpenAIService: AIModel {
    private let httpClient: HTTPClient
    internal let apiKey: String  // Changed to internal for extension access
    internal static let model = "gpt-4o"  // Changed to internal for extension access
    internal static let visionModel = "gpt-4o"  // Changed to internal for extension access
    
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
        imageData: Data? = nil,
        conversationContext: [[String: Any]] = [],
        useInterviewCounterQuestion: Bool = false
    ) -> AsyncThrowingStream<StreamingResponse, Error> {
        if category == .systemDesign && !useInterviewCounterQuestion {
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
            systemPrompt = PromptBuilder.buildImageAnalysisPrompt(userQuestion: prompt.isEmpty ? nil : prompt, category: category, language: language)
            userPrompt = prompt.isEmpty ? "Analyze this image and provide the answer in the specified JSON format." : prompt
        } else {
            systemPrompt = PromptBuilder.buildSystemPrompt(for: category, language: language, useInterviewCounterQuestion: useInterviewCounterQuestion)
            userPrompt = prompt
        }
        
        return streamOpenAIResponse(
            systemPrompt: systemPrompt,
            prompt: userPrompt,
            language: language,
            imageData: imageData,
            conversationContext: conversationContext
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
        imageData: Data?,
        conversationContext: [[String: Any]] = []
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
                
                // Add conversation context if available
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
                
                let body: [String: Any] = [
                    "model": imageData != nil ? Self.visionModel : Self.model,
                    "stream": true,
                    "messages": messages
                    // No response_format - using grammar format instead of JSON
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
                    
                    var parser = StreamingGrammarParser()
                    var currentTitle = ""
                    var currentSections: [MessageSection] = []
                    var chunkCount = 0
                    var receivedLog = ""
                    
                    print("🌊 Starting to receive SSE stream...")
                    
                    var lastLineWasDone = false
                    
                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            throw CancellationError()
                        }
                        
                        if line.isEmpty {
                            continue
                        }
                        
                        if line.hasPrefix("data: ") {
                            let data = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                            
                            if data == "[DONE]" {
                                print("🏁 Received [DONE] signal")
                                print("📊 Total chunks received: \(chunkCount)")
                                print("📄 Full received response (\(receivedLog.count) chars) — first 400: \(receivedLog.prefix(400))")
                                if receivedLog.count > 400 {
                                    print("📄 ... last 200: \(receivedLog.suffix(200))")
                                }
                                lastLineWasDone = true
                                
                                // Finalize parser
                                let finalEvents = parser.finalize()
                                for event in finalEvents {
                                    switch event {
                                    case .completed(let response, _):
                                        continuation.yield(StreamingResponse(
                                            title: response.title,
                                            sections: response.sections,
                                            isComplete: true
                                        ))
                                    default:
                                        break
                                    }
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
                            
                            chunkCount += 1
                            receivedLog.append(content)
                            // Log every 25th chunk + first 3 to avoid flooding (full response logged at end)
                            if chunkCount <= 3 || chunkCount % 25 == 0 {
                                let preview = content.count > 60 ? String(content.prefix(60)) + "…" : content
                                print("📥 Chunk #\(chunkCount): \(content.count) chars — \"\(preview.replacingOccurrences(of: "\n", with: "↵"))\"")
                            }
                            
                            // Parse chunk through grammar parser
                            let events = parser.parse(chunk: content)
                            for event in events {
                                switch event {
                                case .titleParsed(let title):
                                    currentTitle = title
                                    print("📌 Title: \(title)")
                                    
                                case .sectionStarted(let type, let language):
                                    // Create new section with proper type and language
                                    print("🆕 Section started: \(type.displayName) (language: \(language ?? "none"))")
                                    currentSections.append(MessageSection(
                                        type: type,
                                        content: .text(""),
                                        language: language
                                    ))
                                    
                                case .contentChunk(let chunk):
                                    // Update last section with new content. Use plain concat for code (preserve formatting); space-join for text/list.
                                    if !currentSections.isEmpty {
                                        var lastSection = currentSections.removeLast()
                                        let isCode = lastSection.type == .code
                                        
                                        switch lastSection.content {
                                        case .text(let existing):
                                            lastSection = MessageSection(
                                                id: lastSection.id,
                                                type: lastSection.type,
                                                content: .text(isCode ? existing + chunk : existing.appendingStreamingChunk(chunk)),
                                                language: lastSection.language
                                            )
                                        case .list(let items):
                                            var newItems = items
                                            if !newItems.isEmpty {
                                                newItems[newItems.count - 1] = isCode ? newItems[newItems.count - 1] + chunk : newItems[newItems.count - 1].appendingStreamingChunk(chunk)
                                            } else {
                                                newItems.append(chunk)
                                            }
                                            lastSection = MessageSection(
                                                id: lastSection.id,
                                                type: lastSection.type,
                                                content: .list(newItems),
                                                language: lastSection.language
                                            )
                                        }
                                        
                                        currentSections.append(lastSection)
                                    }
                                    
                                    // Yield streaming update
                                    continuation.yield(StreamingResponse(
                                        title: currentTitle,
                                        sections: currentSections,
                                        isComplete: false
                                    ))
                                    
                                case .sectionCompleted(let section):
                                    print("✅ Section completed: \(section.type.displayName)")
                                    
                                    // Replace or add section
                                    if !currentSections.isEmpty && currentSections.last?.type == section.type {
                                        currentSections[currentSections.count - 1] = section
                                    } else {
                                        currentSections.append(section)
                                    }
                                    
                                    continuation.yield(StreamingResponse(
                                        title: currentTitle,
                                        sections: currentSections,
                                        isComplete: false
                                    ))
                                    
                                case .completed(let response, let context):
                                    print("🎉 Response completed with \(response.sections.count) sections")
                                    if let ctx = context {
                                        print("📝 Context: \(ctx.conversationSummary.prefix(50))...")
                                    }
                                    
                                    continuation.yield(StreamingResponse(
                                        title: response.title,
                                        sections: response.sections,
                                        isComplete: true
                                    ))
                                }
                            }
                        }
                    }
                    
                    if !lastLineWasDone {
                        print("⚠️ Stream ended WITHOUT [DONE] signal!")
                        print("📊 Total chunks received: \(chunkCount)")
                        
                        // Finalize anyway
                        let finalEvents = parser.finalize()
                        for event in finalEvents {
                            switch event {
                            case .completed(let response, _):
                                continuation.yield(StreamingResponse(
                                    title: response.title,
                                    sections: response.sections,
                                    isComplete: true
                                ))
                            default:
                                break
                            }
                        }
                    }
                    
                    print("✅ Stream processing complete")
                    
                    continuation.finish()
                } catch {
                    print("❌ ERROR in streamOpenAIResponse: \(error)")
                    continuation.finish(throwing: error)
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
