import Foundation
import Combine
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var currentInput: String = ""
    @Published var isProcessing: Bool = false
    @Published var isRecording: Bool = false
    @Published var selectedCategory: Category = .detailedAnswer
    @Published var selectedProvider: AIProvider = .openAI
    @Published var selectedLanguage: ProgrammingLanguage = .golang
    @Published var capturedScreenshots: [ScreenshotData] = []
    @Published var continueConversation: Bool = true
    /// When true, uses Interview Counter Question prompt instead of category prompt. When false, category can be selected. Default false.
    @Published var useInterviewCounterQuestionPrompt: Bool = false
    
    private var streamBuffer: String = ""
    private var currentMessageId: UUID?
    private var openAIService: OpenAIService
    private var claudeService: ClaudeAIService
    private var grokService: GrokService
    private var deepseekService: DeepSeekService
    private var geminiService: GeminiService
    private let speechRecognitionService = SpeechRecognitionService()
    private let screenshotService = ScreenshotService()
    private var recordingBaseText: String = ""
    private var cancellables: Set<AnyCancellable> = []
    private var streamingTask: Task<Void, Never>?
    private var conversationHistory = ConversationContextHistory()
    
    init(apiKey: String? = nil) {
        let openAIKey = apiKey ?? AppConfig.openAIAPIKey
        let claudeKey = AppConfig.claudeAPIKey
        let grokKey = AppConfig.grokAPIKey
        let deepseekKey = AppConfig.deepseekAPIKey
        let geminiKey = AppConfig.geminiAPIKey
        self.openAIService = OpenAIService(apiKey: openAIKey)
        self.claudeService = ClaudeAIService(apiKey: claudeKey)
        self.grokService = GrokService(apiKey: grokKey)
        self.deepseekService = DeepSeekService(apiKey: deepseekKey)
        self.geminiService = GeminiService(apiKey: geminiKey)
        bindSpeechRecognition()
        bindScreenshotService()
    }
    
    func refreshServices() {
        // Reinitialize services with updated API keys from AppConfig
        openAIService = OpenAIService(apiKey: AppConfig.openAIAPIKey)
        claudeService = ClaudeAIService(apiKey: AppConfig.claudeAPIKey)
        grokService = GrokService(apiKey: AppConfig.grokAPIKey)
        deepseekService = DeepSeekService(apiKey: AppConfig.deepseekAPIKey)
        geminiService = GeminiService(apiKey: AppConfig.geminiAPIKey)
        print("✓ Services refreshed with updated API keys")
    }
    
    func sendMessage() {
        guard !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !capturedScreenshots.isEmpty else { return }
        
        let userMessage: ChatMessage
        if !capturedScreenshots.isEmpty {
            let imageDataArray = capturedScreenshots.map { $0.imageData }
            userMessage = ChatMessage(
                role: .user,
                content: .textWithImages(currentInput, imageDataArray),
                timestamp: Date()
            )
        } else {
            userMessage = ChatMessage(
                role: .user,
                content: .text(currentInput),
                timestamp: Date()
            )
        }
        
        messages.append(userMessage)
        let questionText = currentInput
        let screenshots = capturedScreenshots
        currentInput = ""
        screenshotService.clearAllScreenshots()
        isProcessing = true
        
        streamingTask?.cancel()
        streamingTask = Task {
            await processAIResponse(for: questionText, screenshots: screenshots)
        }
    }

    func resendMessage(_ message: ChatMessage) {
        guard let text = messagePlainTextIfUser(message) else { return }
        currentInput = text
        sendMessage()
    }

    func editMessage(_ message: ChatMessage) {
        guard let text = messagePlainTextIfUser(message) else { return }
        currentInput = text
        recordingBaseText = text
    }
    
    func clearChat() {
        messages.removeAll()
        currentInput = ""
        isProcessing = false
        streamBuffer = ""
        currentMessageId = nil
        streamingTask?.cancel()
        streamingTask = nil
        if isRecording {
            speechRecognitionService.cancelRecording()
        }
        recordingBaseText = ""
        conversationHistory.clearHistory()
    }

    func clearInput() {
        currentInput = ""
        recordingBaseText = ""
        screenshotService.clearAllScreenshots()
        streamingTask?.cancel()
        streamingTask = nil
        stopStreamingState()
        if isRecording {
            speechRecognitionService.cancelRecording()
        }
    }
    
    func captureScreenshot() {
        Task {
            do {
                try await screenshotService.captureScreenshot()
            } catch ScreenshotError.permissionDenied {
                print("Screen recording permission required. Please grant permission in System Settings > Privacy & Security > Screen Recording")
            } catch {
                print("Failed to capture screenshot: \(error.localizedDescription)")
            }
        }
    }
    
    func removeScreenshot(_ screenshot: ScreenshotData) {
        screenshotService.removeScreenshot(screenshot)
    }

    func abortCurrentRequest() {
        streamingTask?.cancel()
        streamingTask = nil
        stopStreamingState()
    }

    func toggleSpeechInput() {
        if isRecording {
            speechRecognitionService.stopRecording()
            let finalText = speechRecognitionService.recognizedText
            if !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                currentInput = appendedSpeechText(
                    base: recordingBaseText,
                    recognized: finalText
                )
            }
            return
        }
        
        Task {
            await speechRecognitionService.requestAuthorization()
            guard speechRecognitionService.isAuthorized else {
                print("Speech recognition not authorized")
                return
            }
            
            do {
                recordingBaseText = currentInput
                try speechRecognitionService.startRecording()
                isRecording = true
            } catch SpeechRecognitionError.notAuthorized {
                print("Speech recognition not authorized")
            } catch {
                print("Failed to start recording: \(error.localizedDescription)")
            }
        }
    }

    func copyAllMessages() {
        let text = messages
            .map { messagePlainText($0) }
            .joined(separator: "\n\n")

        guard !text.isEmpty else { return }

        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
    
    private func processAIResponse(for question: String, screenshots: [ScreenshotData] = []) async {
        let messageId = UUID()
        currentMessageId = messageId
        
        let placeholderMessage = ChatMessage(
            id: messageId,
            role: .assistant,
            content: .text(""),
            timestamp: Date(),
            isStreaming: true
        )
        messages.append(placeholderMessage)
        
        await streamAIResponse(messageId: messageId, question: question, screenshots: screenshots)
    }
    
    private func streamAIResponse(messageId: UUID, question: String, screenshots: [ScreenshotData] = []) async {
        do {
            let imageData = screenshots.first?.imageData
            
            // Get conversation context if enabled (previous chat history for next prompt)
            let contextData = continueConversation ? conversationHistory.getContextForPrompt() : []
            
            if continueConversation {
                print("✓ Continue Conversation ENABLED - Sending \(contextData.count) context(s) to AI as previous chat history")
                conversationHistory.printContextsAsPreviousChatHistory()
            } else {
                print("○ Continue Conversation DISABLED - No context sent to AI")
            }
            
            let realTimeStreamingEnabled = AppConfig.realTimeStreamingEnabled
            let stream: AsyncThrowingStream<StreamingResponse, Error>
            switch selectedProvider {
            case .openAI:
                stream = openAIService.streamInterviewResponse(
                    prompt: question,
                    category: selectedCategory,
                    language: selectedLanguage,
                    includeOptionalCodePhase: false,
                    imageData: imageData,
                    conversationContext: contextData,
                    useInterviewCounterQuestion: useInterviewCounterQuestionPrompt,
                    realTimeStreamingEnabled: realTimeStreamingEnabled
                )
            case .claude:
                stream = claudeService.streamInterviewResponse(
                    prompt: question,
                    category: selectedCategory,
                    language: selectedLanguage,
                    includeOptionalCodePhase: false,
                    imageData: imageData,
                    conversationContext: contextData,
                    useInterviewCounterQuestion: useInterviewCounterQuestionPrompt,
                    realTimeStreamingEnabled: realTimeStreamingEnabled
                )
            case .grok:
                stream = grokService.streamInterviewResponse(
                    prompt: question,
                    category: selectedCategory,
                    language: selectedLanguage,
                    includeOptionalCodePhase: false,
                    imageData: imageData,
                    conversationContext: contextData,
                    useInterviewCounterQuestion: useInterviewCounterQuestionPrompt,
                    realTimeStreamingEnabled: realTimeStreamingEnabled
                )
            case .deepseek:
                stream = deepseekService.streamInterviewResponse(
                    prompt: question,
                    category: selectedCategory,
                    language: selectedLanguage,
                    includeOptionalCodePhase: false,
                    imageData: imageData,
                    conversationContext: contextData,
                    useInterviewCounterQuestion: useInterviewCounterQuestionPrompt,
                    realTimeStreamingEnabled: realTimeStreamingEnabled
                )
            case .gemini:
                stream = geminiService.streamInterviewResponse(
                    prompt: question,
                    category: selectedCategory,
                    language: selectedLanguage,
                    includeOptionalCodePhase: false,
                    imageData: imageData,
                    conversationContext: contextData,
                    useInterviewCounterQuestion: useInterviewCounterQuestionPrompt,
                    realTimeStreamingEnabled: realTimeStreamingEnabled
                )
            }
            
            var lastResponse: StreamingResponse?
            for try await response in stream {
                lastResponse = response
                print("🧩 Streaming update: title=\(response.title.count) chars, sections=\(response.sections.count), complete=\(response.isComplete)")
                updateStreamingMessage(
                    messageId: messageId,
                    response: response
                )
            }
            if lastResponse == nil {
                print("❌ No StreamingResponse chunks received from provider.")
                if let index = messages.firstIndex(where: { $0.id == messageId }) {
                    messages[index] = ChatMessage(
                        id: messageId,
                        role: .assistant,
                        content: .error("No response content received from AI provider."),
                        timestamp: messages[index].timestamp,
                        isStreaming: false
                    )
                }
            }
            finalizeStreamingMessage(messageId: messageId, question: question, streamingContextPayload: lastResponse?.contextPayload)
        } catch is CancellationError {
            stopStreamingState()
        } catch {
            handleError(messageId: messageId, error: error)
        }
    }
    
    private func updateStreamingMessage(messageId: UUID, response: StreamingResponse) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        
        let aiResponse = AIResponse(
            title: response.title,
            sections: response.sections
        )
        
        messages[index] = ChatMessage(
            id: messageId,
            role: .assistant,
            content: .structured(aiResponse),
            timestamp: messages[index].timestamp,
            isStreaming: !response.isComplete
        )
    }
    
    private func finalizeStreamingMessage(messageId: UUID, question: String, streamingContextPayload: String? = nil) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        
        let content = messages[index].content
        messages[index] = ChatMessage(
            id: messageId,
            role: .assistant,
            content: content,
            timestamp: messages[index].timestamp,
            isStreaming: false
        )
        if continueConversation {
            if let payload = streamingContextPayload, let context = parseStreamingContextPayload(question: question, payload: payload) {
                conversationHistory.addContext(context)
                print("💾 Context saved (streaming) - Total contexts: \(conversationHistory.count)")
                conversationHistory.logAllContextsFull()
            } else if case .structured(let aiResponse) = content {
                let context = extractConversationContext(question: question, response: aiResponse)
                conversationHistory.addContext(context)
                print("💾 Context saved - Total contexts: \(conversationHistory.count)")
                conversationHistory.logAllContextsFull()
            }
        } else {
            print("○ Context NOT saved - Continue Conversation is disabled")
        }
        isProcessing = false
        streamBuffer = ""
        currentMessageId = nil
    }
    private func parseStreamingContextPayload(question: String, payload: String) -> ConversationContext? {
        var convPart = ""
        var techPart = ""
        if let r = payload.range(of: "conversation_summary:", options: .caseInsensitive) {
            let after = payload[r.upperBound...]
            if let tr = after.range(of: "ai_technical_context:", options: .caseInsensitive) {
                convPart = String(after[..<tr.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                techPart = String(after[tr.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                convPart = String(after).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if let r = payload.range(of: "ai_technical_context:", options: .caseInsensitive) {
            techPart = String(payload[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let conversationSummary = convPart.isEmpty ? "Question: \(question.prefix(150))" : "Question: \(question.prefix(100))\nSummary: \(convPart.prefix(300))"
        return ConversationContext(
            conversationSummary: conversationSummary,
            previousAnswerSummary: PreviousAnswerSummary(aiTechnicalSummary: String(techPart.prefix(500))),
            currentIntent: "deep_dive",
            relatedToPrevious: true
        )
    }
    
    private func extractConversationContext(
        question: String,
        response: AIResponse
    ) -> ConversationContext {
        // Extract technical summary from response sections
        let technicalSummary = response.sections
            .compactMap { section -> String? in
                switch section.content {
                case .text(let text):
                    return text
                case .list(let items):
                    return items.joined(separator: " ")
                }
            }
            .prefix(3)
            .joined(separator: " ")
            .prefix(200)
        
        let conversationSummary = "Question: \(question.prefix(150))"
        
        return ConversationContext(
            conversationSummary: conversationSummary,
            previousAnswerSummary: PreviousAnswerSummary(
                aiTechnicalSummary: String(technicalSummary)
            ),
            currentIntent: "deep_dive",
            relatedToPrevious: true
        )
    }
    
    private func handleError(messageId: UUID, error: Error) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        
        // Log the error for debugging
        print("AI Service Error: \(error)")
        if let httpError = error as? HTTPError {
            print("HTTP Error details: \(httpError.localizedDescription)")
        }
        
        messages[index] = ChatMessage(
            id: messageId,
            role: .assistant,
            content: .error(error.localizedDescription),
            timestamp: messages[index].timestamp,
            isStreaming: false
        )
        
        isProcessing = false
        currentMessageId = nil
    }

    private func stopStreamingState() {
        if let messageId = currentMessageId,
           let index = messages.firstIndex(where: { $0.id == messageId }) {
            let content = messages[index].content
            messages[index] = ChatMessage(
                id: messageId,
                role: .assistant,
                content: content,
                timestamp: messages[index].timestamp,
                isStreaming: false
            )
        }
        isProcessing = false
        streamBuffer = ""
        currentMessageId = nil
    }

    private func bindSpeechRecognition() {
        speechRecognitionService.$recognizedText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                guard let self else { return }
                guard self.isRecording else { return }
                self.currentInput = self.appendedSpeechText(
                    base: self.recordingBaseText,
                    recognized: text
                )
            }
            .store(in: &cancellables)

        speechRecognitionService.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] serviceRecording in
                self?.isRecording = serviceRecording
            }
            .store(in: &cancellables)
    }
    
    private func bindScreenshotService() {
        screenshotService.$capturedScreenshots
            .receive(on: RunLoop.main)
            .sink { [weak self] screenshots in
                self?.capturedScreenshots = screenshots
            }
            .store(in: &cancellables)
    }

    private func appendedSpeechText(base: String, recognized: String) -> String {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRecognized = recognized.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedBase.isEmpty {
            return trimmedRecognized
        }
        if trimmedRecognized.isEmpty {
            return trimmedBase
        }
        return "\(trimmedBase) \(trimmedRecognized)"
    }

    private func messagePlainText(_ message: ChatMessage) -> String {
        let roleTitle: String
        switch message.role {
        case .user:
            roleTitle = "You"
        case .assistant:
            roleTitle = "Assistant"
        case .system:
            roleTitle = "System"
        }

        let contentText: String
        switch message.content {
        case .text(let text):
            contentText = text
        case .error(let error):
            contentText = "Error: \(error)"
        case .structured(let response):
            contentText = structuredResponseText(response)
        case .textWithImages(let text, _):
            contentText = text.isEmpty ? "[Image]" : text
        }

        return "\(roleTitle):\n\(contentText)"
    }

    private func messagePlainTextIfUser(_ message: ChatMessage) -> String? {
        guard message.role == .user else { return nil }
        switch message.content {
        case .text(let text):
            return text
        case .textWithImages(let text, _):
            return text
        default:
            return nil
        }
    }

    private func structuredResponseText(_ response: AIResponse) -> String {
        var lines: [String] = []
        lines.append(response.title)

        for section in response.sections {
            lines.append("")
            lines.append(section.type.displayName)

            switch section.content {
            case .text(let text):
                lines.append(text)
            case .list(let items):
                lines.append(contentsOf: items.map { "- \($0)" })
            }
        }

        return lines.joined(separator: "\n")
    }
}
