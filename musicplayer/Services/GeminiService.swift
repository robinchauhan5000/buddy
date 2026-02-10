//
//  GeminiService.swift
//  musicplayer
//
//  Google Gemini AI service integration
//

import Foundation

final class GeminiService {
    private let httpClient: HTTPClient
    private let apiKey: String
    
    private static let model = "gemini-2.0-flash-exp"
    
    init(apiKey: String) {
        self.apiKey = apiKey
        
        // Log API key status for debugging
        if apiKey.isEmpty {
            print("⚠️ WARNING: Gemini API key is empty!")
            print("   Please add your Gemini key in the app settings")
        } else {
            print("✓ Gemini API key loaded")
            print("  Length: \(apiKey.count) characters")
            print("  Prefix: \(String(apiKey.prefix(10)))...")
        }
        
        self.httpClient = HTTPClient(
            baseURL: "https://generativelanguage.googleapis.com/v1beta",
            defaultHeaders: [
                "Content-Type": "application/json"
            ]
        )
        
        print("  Base URL: https://generativelanguage.googleapis.com/v1beta")
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
        
        var contents: [[String: Any]] = []
        
        // Add system prompt as first message
        contents.append([
            "role": "user",
            "parts": [["text": systemPrompt]]
        ])
        
        // Add user message with optional image
        if let imageData = imageData {
            let base64Image = imageData.base64EncodedString()
            contents.append([
                "role": "user",
                "parts": [
                    ["text": userPrompt],
                    [
                        "inline_data": [
                            "mime_type": "image/png",
                            "data": base64Image
                        ]
                    ]
                ]
            ])
        } else {
            contents.append([
                "role": "user",
                "parts": [["text": userPrompt]]
            ])
        }
        
        let body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "response_mime_type": "application/json"
            ]
        ]
        
        // Debug logging
        print("🔵 Gemini API Request:")
        print("  Endpoint: /models/\(Self.model):generateContent")
        print("  Has image: \(imageData != nil)")
        if let jsonData = try? JSONSerialization.data(withJSONObject: body, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("  Body preview: \(String(jsonString.prefix(500)))...")
        }
        
        let endpoint = "/models/\(Self.model):generateContent?key=\(apiKey)"
        let (data, httpResponse) = try await httpClient.postRaw(endpoint, body: body)
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // Log the error response for debugging
            if let errorString = String(data: data, encoding: .utf8) {
                print("Gemini API Error (\(httpResponse.statusCode)): \(errorString)")
            }
            throw HTTPError.statusCode(httpResponse.statusCode)
        }
        
        // Log the response for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            print("Gemini API Response preview: \(String(responseString.prefix(500)))...")
        }
        
        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
        
        guard let candidate = geminiResponse.candidates.first,
              let part = candidate.content.parts.first,
              let content = part.text else {
            throw AIModelError("No content in Gemini response", provider: "Gemini")
        }
        
        // Parse the JSON response
        guard let jsonData = content.data(using: .utf8),
              let aiResponse = try? JSONDecoder().decode(AIResponse.self, from: jsonData) else {
            throw AIModelError("Failed to parse Gemini response JSON", provider: "Gemini")
        }
        
        return aiResponse
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
        
        return streamGeminiResponse(
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
                        
                        let phaseStream = streamGeminiResponse(
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
    
    private func streamGeminiResponse(
        systemPrompt: String,
        prompt: String,
        language: ProgrammingLanguage,
        imageData: Data?,
        conversationContext: [[String: Any]] = []
    ) -> AsyncThrowingStream<StreamingResponse, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(Self.model):streamGenerateContent?key=\(apiKey)&alt=sse") else {
                    continuation.finish(throwing: AIModelError("Invalid URL", provider: "Gemini"))
                    return
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                var contents: [[String: Any]] = []
                
                // Add system prompt
                contents.append([
                    "role": "user",
                    "parts": [["text": systemPrompt]]
                ])
                
                // Add conversation context if available
                if !conversationContext.isEmpty {
                    print("📝 Gemini: Injecting \(conversationContext.count) conversation context(s)")
                    for context in conversationContext {
                        if let jsonData = try? JSONSerialization.data(withJSONObject: context),
                           let jsonString = String(data: jsonData, encoding: .utf8) {
                            contents.append([
                                "role": "user",
                                "parts": [["text": "Previous context: \(jsonString)"]]
                            ])
                        }
                    }
                } else {
                    print("📝 Gemini: No conversation context - sending fresh request")
                }
                
                // Add user message with optional image
                if let imageData = imageData {
                    let base64Image = imageData.base64EncodedString()
                    contents.append([
                        "role": "user",
                        "parts": [
                            ["text": prompt],
                            [
                                "inline_data": [
                                    "mime_type": "image/png",
                                    "data": base64Image
                                ]
                            ]
                        ]
                    ])
                } else {
                    contents.append([
                        "role": "user",
                        "parts": [["text": prompt]]
                    ])
                }
                
                let body: [String: Any] = [
                    "contents": contents,
                    "generationConfig": [
                        "response_mime_type": "application/json"
                    ]
                ]
                
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
                
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: AIModelError("Invalid response", provider: "Gemini"))
                        return
                    }

                    guard httpResponse.statusCode == 200 else {
                        let errorBody = await readErrorBody(from: bytes)
                        let errorDetail = parseGeminiErrorMessage(from: errorBody)
                        let message = errorDetail ?? "HTTP \(httpResponse.statusCode)"
                        continuation.finish(
                            throwing: AIModelError(
                                "Streaming failed: \(message)",
                                provider: "Gemini"
                            )
                        )
                        return
                    }
                    
                    var parser = StreamParser()
                    var streamedText = ""
                    var chunkCount = 0
                    var receivedLog = ""
                    
                    print("🌊 Starting to receive Gemini SSE stream...")
                    
                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            throw CancellationError()
                        }
                        
                        if line.isEmpty {
                            continue
                        }
                        
                        if line.hasPrefix("data: ") {
                            let data = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                            
                            guard let jsonData = data.data(using: .utf8),
                                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                                  let candidates = json["candidates"] as? [[String: Any]],
                                  let firstCandidate = candidates.first,
                                  let content = firstCandidate["content"] as? [String: Any],
                                  let parts = content["parts"] as? [[String: Any]],
                                  let firstPart = parts.first,
                                  let text = firstPart["text"] as? String else {
                                continue
                            }
                            
                            chunkCount += 1
                            receivedLog.append(text)
                            if chunkCount <= 3 || chunkCount % 25 == 0 {
                                let preview = text.count > 60 ? String(text.prefix(60)) + "…" : text
                                print("📥 Gemini Chunk #\(chunkCount): \(text.count) chars — \"\(preview.replacingOccurrences(of: "\n", with: "↵"))\"")
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
                                    print("✅ JSON parsed successfully!")
                                    print("   Title: \(aiResponse.title)")
                                    print("   Sections: \(aiResponse.sections.count)")
                                    continuation.yield(StreamingResponse(
                                        title: aiResponse.title,
                                        sections: aiResponse.sections,
                                        isComplete: true
                                    ))
                                }
                            }
                        }
                    }
                    
                    print("🏁 Stream ended")
                    print("📊 Total chunks received: \(chunkCount)")
                    print("📊 Total content length: \(streamedText.count) chars")
                    print("📄 Full received response (\(receivedLog.count) chars) — first 400: \(receivedLog.prefix(400))")
                    if receivedLog.count > 400 {
                        print("📄 ... last 200: \(receivedLog.suffix(200))")
                    }
                    print("✅ Stream processing complete")
                    
                    continuation.finish()
                } catch {
                    print("❌ ERROR in streamGeminiResponse: \(error)")
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

    private func parseGeminiErrorMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else {
            return nil
        }

        let message = error["message"] as? String
        let status = error["status"] as? String

        switch (status, message) {
        case let (.some(status), .some(message)):
            return "\(status): \(message)"
        case let (_, .some(message)):
            return message
        default:
            return nil
        }
    }
}

// MARK: - Gemini Response Models

struct GeminiResponse: Codable {
    let candidates: [GeminiCandidate]
}

struct GeminiCandidate: Codable {
    let content: GeminiContent
}

struct GeminiContent: Codable {
    let parts: [GeminiPart]
    let role: String
}

struct GeminiPart: Codable {
    let text: String?
}
