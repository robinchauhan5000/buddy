//
//  GrokService.swift
//  musicplayer
//
//  Grok AI service for X.AI API integration
//

import Foundation

final class GrokService {
    private let httpClient: HTTPClient
    private let apiKey: String
    
    private static let model = "grok-4"
    
    init(apiKey: String) {
        self.apiKey = apiKey
        
        // Log API key status for debugging
        if apiKey.isEmpty {
            print("⚠️ WARNING: Grok API key is empty!")
            print("   Please add your Grok key in the app settings")
        } else {
            print("✓ Grok API key loaded")
            print("  Length: \(apiKey.count) characters")
            print("  Prefix: \(String(apiKey.prefix(10)))...")
        }
        
        self.httpClient = HTTPClient(
            baseURL: "https://api.x.ai/v1",
            defaultHeaders: [
                "Authorization": "Bearer \(apiKey)",
                "Content-Type": "application/json"
            ]
        )
        
        print("  Base URL: https://api.x.ai/v1")
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
                    [
                        "type": "text",
                        "text": userPrompt
                    ],
                    [
                        "type": "image_url",
                        "image_url": [
                            "url": "data:image/png;base64,\(base64Image)",
                            "detail": "high"
                        ]
                    ]
                ]
            ])
        } else {
            messages.append(["role": "user", "content": userPrompt])
        }
        
        let body: [String: Any] = [
            "model": Self.model,
            "messages": messages
        ]
        
        // Debug logging
        print("🔵 Grok API Request:")
        print("  Endpoint: /chat/completions")
        print("  Model: \(Self.model)")
        print("  Has image: \(imageData != nil)")
        if let jsonData = try? JSONSerialization.data(withJSONObject: body, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("  Body: \(jsonString)")
        }
        
        let (data, httpResponse) = try await httpClient.postRaw("/chat/completions", body: body)
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // Log the error response for debugging
            if let errorString = String(data: data, encoding: .utf8) {
                print("Grok API Error (\(httpResponse.statusCode)): \(errorString)")
            }
            throw HTTPError.statusCode(httpResponse.statusCode)
        }
        
        // Log the response for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            print("Grok API Response: \(responseString)")
        }
        
        let grokResponse = try JSONDecoder().decode(GrokResponse.self, from: data)
        
        guard let content = grokResponse.choices.first?.message.content else {
            throw AIModelError("No content in Grok response", provider: "Grok")
        }
        
        // Parse the JSON response
        guard let jsonData = content.data(using: .utf8),
              let aiResponse = try? JSONDecoder().decode(AIResponse.self, from: jsonData) else {
            throw AIModelError("Failed to parse Grok response JSON", provider: "Grok")
        }
        
        return aiResponse
    }
    
    func streamInterviewResponse(
        prompt: String,
        category: Category,
        language: ProgrammingLanguage,
        includeOptionalCodePhase: Bool = false,
        imageData: Data? = nil,
        conversationContext: [[String: Any]] = []
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
            userPrompt = prompt.isEmpty ? "Analyze this image and provide the answer in the specified JSON format." : prompt
        } else {
            systemPrompt = PromptBuilder.buildSystemPrompt(for: category, language: language)
            userPrompt = prompt
        }
        
        return streamGrokResponse(
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
            let task = Task {
                _ = includeOptionalCodePhase
                var phaseSections: [Int: [MessageSection]] = [:]
                var title = ""
                let baseSystemPrompt = PromptBuilder.buildSystemPrompt(for: .systemDesign, language: language)
                let lastPhase = 15
                
                do {
                    for phase in 1...lastPhase {
                        if Task.isCancelled {
                            throw CancellationError()
                        }
                        
                        print("\n🔵 ========== PHASE \(phase)/\(lastPhase) START ==========")
                        
                        let userPrompt = PromptBuilder.buildSystemDesignPhaseUserPrompt(
                            phase: phase,
                            question: prompt,
                            language: language
                        )
                        
                        print("📝 System Prompt Length: \(baseSystemPrompt.count) characters")
                        print("📝 User Prompt Length: \(userPrompt.count) characters")
                        print("📝 Total Prompt Size: ~\((baseSystemPrompt.count + userPrompt.count) / 1024) KB")
                        
                        let phaseStream = streamGrokResponse(
                            systemPrompt: baseSystemPrompt,
                            prompt: userPrompt,
                            language: language,
                            imageData: nil
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
    
    private func streamGrokResponse(
        systemPrompt: String,
        prompt: String,
        language: ProgrammingLanguage,
        imageData: Data?
    ) -> AsyncThrowingStream<StreamingResponse, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Grok doesn't support streaming, so we get the full response and simulate streaming
                    let response = try await getInterviewResponse(
                        prompt: prompt,
                        category: .normal,
                        language: language,
                        imageData: imageData
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

// MARK: - Grok Response Models

struct GrokResponse: Codable {
    let choices: [GrokChoice]
}

struct GrokChoice: Codable {
    let message: GrokMessage
}

struct GrokMessage: Codable {
    let role: String
    let content: String
}
