import Foundation

// MARK: - OpenAI Service Grammar Streaming Extension
// This demonstrates how to use StreamingGrammarParser for real-time UI updates

extension OpenAIService {
    
    /// Stream response using grammar parser (NOT JSON)
    /// This provides true real-time streaming without blocking on JSON decoding
    func streamInterviewResponseWithGrammar(
        prompt: String,
        category: Category,
        language: ProgrammingLanguage,
        imageData: Data? = nil,
        conversationContext: [[String: Any]] = []
    ) -> AsyncThrowingStream<StreamingResponse, Error> {
        
        return AsyncThrowingStream { continuation in
            let task = Task<Void, Never> {
                guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
                    continuation.finish(throwing: AIModelError("Invalid URL", provider: "OpenAI"))
                    return
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                
                let systemPrompt = PromptBuilder.buildSystemPrompt(for: category, language: language)
                
                var messages: [[String: Any]] = [
                    ["role": "system", "content": systemPrompt]
                ]
                
                // Add conversation context if available
                if !conversationContext.isEmpty {
                    let contextString = conversationContext.compactMap { context in
                        (try? JSONSerialization.data(withJSONObject: context))
                            .flatMap { String(data: $0, encoding: .utf8) }
                    }.joined(separator: "\n")
                    
                    messages.append([
                        "role": "system",
                        "content": "Previous conversation context:\n\(contextString)"
                    ])
                }
                
                if let imageData = imageData {
                    let base64Image = imageData.base64EncodedString()
                    let userMessage: [String: Any] = [
                        "role": "user",
                        "content": [
                            ["type": "text", "text": prompt],
                            [
                                "type": "image_url",
                                "image_url": [
                                    "url": "data:image/png;base64,\(base64Image)"
                                ]
                            ]
                        ] as [[String: Any]]
                    ]
                    messages.append(userMessage)
                } else {
                    let userMessage: [String: Any] = ["role": "user", "content": prompt]
                    messages.append(userMessage)
                }
                
                let body: [String: Any] = [
                    "model": Self.model,
                    "stream": true,
                    "messages": messages
                    // NOTE: No response_format for grammar-based streaming
                ]
                
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
                
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: AIModelError("Invalid response", provider: "OpenAI"))
                        return
                    }
                    
                    guard httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: AIModelError("HTTP \(httpResponse.statusCode)", provider: "OpenAI"))
                        return
                    }
                    
                    var parser = StreamingGrammarParser()
                    var currentTitle = ""
                    var currentSections: [MessageSection] = []
                    var receivedLog = ""  // Accumulate raw response for logging
                    var chunkIndex = 0
                    
                    print("🌊 Starting grammar-based streaming...")
                    
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
                                print("🏁 Stream complete, finalizing...")
                                print("📄 Full received response (\(receivedLog.count) chars) — first 400: \(receivedLog.prefix(400))")
                                if receivedLog.count > 400 {
                                    print("📄 ... last 200: \(receivedLog.suffix(200))")
                                }
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
                            
                            chunkIndex += 1
                            receivedLog.append(content)
                            if chunkIndex <= 3 || chunkIndex % 25 == 0 {
                                let preview = content.count > 60 ? String(content.prefix(60)) + "…" : content
                                print("📥 Chunk #\(chunkIndex): \(content.count) chars — \"\(preview.replacingOccurrences(of: "\n", with: "↵"))\"")
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
                                    // Stream content immediately to UI
                                    // Update the last section. Use plain concat for code (preserve formatting); space-join for text/list.
                                    if !currentSections.isEmpty {
                                        var lastSection = currentSections.removeLast()
                                        let isCode = lastSection.type == .code
                                        
                                        switch lastSection.content {
                                        case .text(let existing):
                                            lastSection = MessageSection(
                                                id: lastSection.id,
                                                type: lastSection.type,
                                                content: .text(isCode ? existing.appendingCodeChunk(chunk) : existing.appendingStreamingChunk(chunk)),
                                                language: lastSection.language
                                            )
                                        case .list(let items):
                                            var newItems = items
                                            if !newItems.isEmpty {
                                                newItems[newItems.count - 1] = isCode ? newItems[newItems.count - 1].appendingCodeChunk(chunk) : newItems[newItems.count - 1].appendingStreamingChunk(chunk)
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
                                    
                                    // Replace temporary section or add new
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
                    
                    print("✅ Grammar streaming complete")
                    continuation.finish()
                    
                } catch {
                    print("❌ ERROR in grammar streaming: \(error)")
                    continuation.finish(throwing: error)
                }
            }
            
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
