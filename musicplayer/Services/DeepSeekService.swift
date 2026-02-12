//
//  DeepSeekService.swift
//  musicplayer
//
//  DeepSeek AI service integration
//

import Foundation

final class DeepSeekService {
    private let httpClient: HTTPClient
    private let apiKey: String
    
    private static let model = "deepseek-chat"
    
    init(apiKey: String) {
        self.apiKey = apiKey
        
        // Log API key status for debugging
        if apiKey.isEmpty {
            print("⚠️ WARNING: DeepSeek API key is empty!")
            print("   Please add your DeepSeek key in the app settings")
        } else {
            print("✓ DeepSeek API key loaded")
            print("  Length: \(apiKey.count) characters")
            print("  Prefix: \(String(apiKey.prefix(10)))...")
        }
        
        self.httpClient = HTTPClient(
            baseURL: "https://api.deepseek.com",
            defaultHeaders: [
                "Authorization": "Bearer \(apiKey)",
                "Content-Type": "application/json"
            ]
        )
        
        print("  Base URL: https://api.deepseek.com")
    }
    
    func getInterviewResponse(
        prompt: String,
        category: Category,
        language: ProgrammingLanguage,
        imageData: Data? = nil,
        conversationContext: [[String: Any]] = []
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
        
        if !conversationContext.isEmpty {
            let contextString = conversationContext.compactMap { ctx -> String? in
                (try? JSONSerialization.data(withJSONObject: ctx)).flatMap { String(data: $0, encoding: .utf8) }
            }.joined(separator: "\n")
            messages.append([
                "role": "system",
                "content": "Previous conversation context (chat history):\n\(contextString)"
            ])
        }
        
        if let imageData = imageData {
            let base64Image = imageData.base64EncodedString()
            messages.append([
                "role": "user",
                "content": [
                    [
                        "type": "text",
                        "text": userPrompt
                    ],
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
            "model": Self.model,
            "messages": messages,
            "stream": false
        ]
        
        // Debug logging
        print("🔵 DeepSeek API Request:")
        print("  Endpoint: /chat/completions")
        print("  Model: \(Self.model)")
        print("  Has image: \(imageData != nil)")
        PromptBuilder.printFinalPromptSent(provider: "DeepSeek", systemPrompt: systemPrompt, userPrompt: userPrompt, conversationContextCount: conversationContext.count, hasImage: imageData != nil)
        if let jsonData = try? JSONSerialization.data(withJSONObject: body, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("  Body: \(jsonString)")
        }
        
        let (data, httpResponse) = try await httpClient.postRaw("/chat/completions", body: body)
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // Log the error response for debugging
            if let errorString = String(data: data, encoding: .utf8) {
                print("DeepSeek API Error (\(httpResponse.statusCode)): \(errorString)")
            }
            throw HTTPError.statusCode(httpResponse.statusCode)
        }
        
        // Log the response for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            print("DeepSeek API Response: \(responseString)")
        }
        
        let deepseekResponse = try JSONDecoder().decode(DeepSeekResponse.self, from: data)
        
        guard let content = deepseekResponse.choices.first?.message.content else {
            throw AIModelError("No content in DeepSeek response", provider: "DeepSeek")
        }
        
        // Parse the JSON response
        guard let jsonData = content.data(using: .utf8),
              let aiResponse = try? JSONDecoder().decode(AIResponse.self, from: jsonData) else {
            throw AIModelError("Failed to parse DeepSeek response JSON", provider: "DeepSeek")
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
        useInterviewCounterQuestion: Bool = false,
        realTimeStreamingEnabled: Bool = false
    ) -> AsyncThrowingStream<StreamingResponse, Error> {
        if category == .systemDesign && !useInterviewCounterQuestion {
            return streamPhasedSystemDesign(
                prompt: prompt,
                language: language,
                includeOptionalCodePhase: includeOptionalCodePhase,
                imageData: imageData
            )
        }
        let systemPrompt: String
        let userPrompt: String
        if imageData != nil {
            systemPrompt = PromptBuilder.buildImageAnalysisPrompt(userQuestion: prompt.isEmpty ? nil : prompt, category: category, language: language, useInterviewCounterQuestion: useInterviewCounterQuestion, realTimeStreamingEnabled: false)
            userPrompt = prompt.isEmpty ? "Analyze this image and provide the answer in the specified JSON format." : prompt
        } else {
            systemPrompt = PromptBuilder.buildSystemPrompt(for: category, language: language, useInterviewCounterQuestion: useInterviewCounterQuestion, realTimeStreamingEnabled: false)
            userPrompt = prompt
        }
        return streamDeepSeekResponse(
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
        imageData: Data? = nil
    ) -> AsyncThrowingStream<StreamingResponse, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                _ = includeOptionalCodePhase
                var phaseSections: [Int: [MessageSection]] = [:]
                var title = ""
                let baseSystemPrompt = PromptBuilder.buildSystemPrompt(for: .systemDesign, language: language)
                let lastPhase = 8
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
                        
                        let phaseStream = streamDeepSeekResponse(
                            systemPrompt: baseSystemPrompt,
                            prompt: userPrompt,
                            language: language,
                            imageData: phaseImageData
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
    
    private func streamDeepSeekResponse(
        systemPrompt: String,
        prompt: String,
        language: ProgrammingLanguage,
        imageData: Data?,
        conversationContext: [[String: Any]] = []
    ) -> AsyncThrowingStream<StreamingResponse, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // DeepSeek doesn't support streaming in this implementation, so we get the full response
                    let response = try await getInterviewResponse(
                        prompt: prompt,
                        category: .normal,
                        language: language,
                        imageData: imageData,
                        conversationContext: conversationContext
                    )
                    
                    // Convert to streaming format
                    let streamingResponse = StreamingResponse(
                        title: response.title,
                        sections: response.sections,
                        isComplete: true
                    )
                    
                    continuation.yield(streamingResponse)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - DeepSeek Response Models

struct DeepSeekResponse: Codable {
    let choices: [DeepSeekChoice]
}

struct DeepSeekChoice: Codable {
    let message: DeepSeekMessage
}

struct DeepSeekMessage: Codable {
    let role: String
    let content: String
}
