//
//  ClaudeAIService.swift
//  musicplayer
//
//  Claude (Anthropic) Messages API:
//  - POST /v1/messages — send messages (streaming and non-streaming).
//  - POST /v1/messages/batches — async batch processing (50% cost reduction) can be added for high-volume use.
//

import Foundation

final class ClaudeAIService: AIModel {
    private let apiKey: String
    private static let model = "claude-sonnet-4-20250514"
    private static let anthropicVersion = "2023-06-01"
    private static let baseURL = "https://api.anthropic.com/v1/messages"

    init(apiKey: String) {
        self.apiKey = apiKey
        if apiKey.isEmpty {
            print("⚠️ ClaudeAIService initialized with empty API key")
        } else {
            print("✓ ClaudeAIService initialized")
            print("  Length: \(apiKey.count) characters")
            print("  Prefix: \(String(apiKey.prefix(10)))...")
        }
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

        let messagesContent: [[String: Any]]
        if let imageData = imageData {
            let base64Image = imageData.base64EncodedString()
            messagesContent = [
                [
                    "type": "text",
                    "text": userPrompt
                ],
                [
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": "image/png",
                        "data": base64Image
                    ] as [String: Any]
                ] as [String: Any]
            ]
        } else {
            messagesContent = [["type": "text", "text": userPrompt]]
        }

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 8192,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": messagesContent]
            ]
        ]

        var request = URLRequest(url: URL(string: Self.baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse

        guard httpResponse.statusCode == 200 else {
            let errorDetail = parseClaudeError(from: data)
            throw AIModelError(
                "API request failed: \(errorDetail)",
                provider: "Claude"
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentBlocks = json["content"] as? [[String: Any]],
              let firstBlock = contentBlocks.first,
              firstBlock["type"] as? String == "text",
              let text = firstBlock["text"] as? String,
              let contentData = text.data(using: .utf8) else {
            throw AIModelError("Invalid response format", provider: "Claude")
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

        return streamClaudeResponse(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            imageData: imageData,
            conversationContext: conversationContext
        )
    }

    // MARK: - Streaming (Messages API with stream: true)

    private func streamClaudeResponse(
        systemPrompt: String,
        userPrompt: String,
        imageData: Data?,
        conversationContext: [[String: Any]]
    ) -> AsyncThrowingStream<StreamingResponse, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var fullSystemPrompt = systemPrompt
                    if !conversationContext.isEmpty {
                        let contextString = conversationContext.compactMap { ctx -> String? in
                            (try? JSONSerialization.data(withJSONObject: ctx)).flatMap { String(data: $0, encoding: .utf8) }
                        }.joined(separator: "\n")
                        fullSystemPrompt = systemPrompt + "\n\nPrevious conversation context:\n\(contextString)"
                    }

                    let messagesContent: [[String: Any]]
                    if let imageData = imageData {
                        let base64Image = imageData.base64EncodedString()
                        messagesContent = [
                            ["type": "text", "text": userPrompt],
                            [
                                "type": "image",
                                "source": [
                                    "type": "base64",
                                    "media_type": "image/png",
                                    "data": base64Image
                                ] as [String: Any]
                            ] as [String: Any]
                        ]
                    } else {
                        messagesContent = [["type": "text", "text": userPrompt]]
                    }

                    let body: [String: Any] = [
                        "model": Self.model,
                        "max_tokens": 8192,
                        "stream": true,
                        "system": fullSystemPrompt,
                        "messages": [["role": "user", "content": messagesContent]]
                    ]

                    var request = URLRequest(url: URL(string: Self.baseURL)!)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    request.timeoutInterval = 120

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: AIModelError("Invalid response", provider: "Claude"))
                        return
                    }
                    guard httpResponse.statusCode == 200 else {
                        let errorBody = await readErrorBody(from: bytes)
                        let detail = parseClaudeError(from: errorBody.data(using: .utf8) ?? Data())
                        continuation.finish(throwing: AIModelError("Streaming failed: \(detail)", provider: "Claude"))
                        return
                    }

                    var parser = StreamParser()
                    var streamedText = ""
                    var receivedLog = ""
                    var chunkIndex = 0

                    print("🌊 Starting Claude SSE stream...")

                    for try await line in bytes.lines {
                        if Task.isCancelled { throw CancellationError() }
                        guard line.hasPrefix("data: ") else { continue }
                        let dataStr = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        guard let data = dataStr.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = json["type"] as? String else { continue }

                        if type == "content_block_delta",
                           let delta = json["delta"] as? [String: Any] {
                            let text = (delta["text"] as? String) ?? (delta["text_delta"] as? String) ?? ""
                            if !text.isEmpty {
                                chunkIndex += 1
                                receivedLog.append(text)
                                if chunkIndex <= 3 || chunkIndex % 25 == 0 {
                                    let preview = text.count > 60 ? String(text.prefix(60)) + "…" : text
                                    print("📥 Claude Chunk #\(chunkIndex): \(text.count) chars — \"\(preview.replacingOccurrences(of: "\n", with: "↵"))\"")
                                }
                                // Parse chunk and emit events
                                let events = parser.parse(chunk: text)
                                for event in events {
                                    switch event {
                                    case .token(let token):
                                        // Stream token immediately to UI
                                        streamedText.append(token)
                                        continuation.yield(StreamingResponse(
                                            title: "",
                                            sections: [MessageSection(
                                                type: .shortAnswer,
                                                content: .text(streamedText)
                                            )],
                                            isComplete: false
                                        ))
                                        
                                    case .completed(let aiResponse):
                                        // Emit final structured response
                                        continuation.yield(StreamingResponse(
                                            title: aiResponse.title,
                                            sections: aiResponse.sections,
                                            isComplete: true
                                        ))
                                    }
                                }
                            }
                        }

                        if type == "message_stop" {
                            break
                        }
                    }
                    print("🏁 Claude stream ended. Full received (\(receivedLog.count) chars) — first 400: \(receivedLog.prefix(400))")
                    if receivedLog.count > 400 {
                        print("📄 ... last 200: \(receivedLog.suffix(200))")
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func readErrorBody(from bytes: URLSession.AsyncBytes) async -> String {
        var lines: [String] = []
        var count = 0
        do {
            for try await line in bytes.lines {
                lines.append(line)
                count += 1
                if count >= 20 { break }
            }
        } catch {}
        return lines.joined(separator: "\n")
    }

    private func parseClaudeError(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return "HTTP error"
        }
        return message
    }

    // MARK: - Phased System Design (same pattern as OpenAI)

    private func streamPhasedSystemDesign(
        prompt: String,
        language: ProgrammingLanguage,
        includeOptionalCodePhase: Bool,
        conversationContext: [[String: Any]],
        imageData: Data? = nil
    ) -> AsyncThrowingStream<StreamingResponse, Error> {
        let baseSystemPrompt = PromptBuilder.buildSystemPrompt(for: .systemDesign, language: language)
        let lastPhase = 15
        let questionForPhases = prompt.isEmpty ? "System design question from image" : prompt
        return AsyncThrowingStream { continuation in
            let task = Task {
                var phaseSections: [Int: [MessageSection]] = [:]
                var title = ""
                do {
                    for phase in 1...lastPhase {
                        if Task.isCancelled { throw CancellationError() }
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
                            userPrompt = PromptBuilder.buildSystemDesignPhaseUserPrompt(phase: phase, question: questionForPhases, language: language)
                            phaseImageData = nil
                        }
                        let phaseStream = streamClaudeResponse(
                            systemPrompt: baseSystemPrompt,
                            userPrompt: userPrompt,
                            imageData: phaseImageData,
                            conversationContext: conversationContext
                        )
                        for try await phaseResponse in phaseStream {
                            if Task.isCancelled { throw CancellationError() }
                            if title.isEmpty && !phaseResponse.title.isEmpty { title = phaseResponse.title }
                            phaseSections[phase] = phaseResponse.sections
                            let merged = mergePhaseSections(phaseSections)
                            continuation.yield(StreamingResponse(title: title, sections: merged, isComplete: false))
                        }
                    }
                    let finalSections = mergePhaseSections(phaseSections)
                    continuation.yield(StreamingResponse(title: title, sections: finalSections, isComplete: true))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func mergePhaseSections(_ phaseSections: [Int: [MessageSection]]) -> [MessageSection] {
        phaseSections.keys.sorted().flatMap { phaseSections[$0] ?? [] }
    }
}
