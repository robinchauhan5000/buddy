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
    @Published var selectedCategory: Category = .normal
    @Published var selectedProvider: AIProvider = .openAI
    @Published var selectedLanguage: ProgrammingLanguage = .golang
    @Published var capturedScreenshots: [ScreenshotData] = []
    @Published var continueConversation: Bool = true
    
    private var streamBuffer: String = ""
    private var currentMessageId: UUID?
    private var openAIService: OpenAIService
    private var grokService: GrokService
    private var deepseekService: DeepSeekService
    private let speechRecognitionService = SpeechRecognitionService()
    private let screenshotService = ScreenshotService()
    private var recordingBaseText: String = ""
    private var cancellables: Set<AnyCancellable> = []
    private var streamingTask: Task<Void, Never>?
    private var conversationHistory = ConversationContextHistory()
    
    init(apiKey: String? = nil) {
        let openAIKey = apiKey ?? AppConfig.openAIAPIKey
        let grokKey = AppConfig.grokAPIKey
        let deepseekKey = AppConfig.deepseekAPIKey
        self.openAIService = OpenAIService(apiKey: openAIKey)
        self.grokService = GrokService(apiKey: grokKey)
        self.deepseekService = DeepSeekService(apiKey: deepseekKey)
        bindSpeechRecognition()
        bindScreenshotService()
    }
    
    func refreshServices() {
        // Reinitialize services with updated API keys from AppConfig
        openAIService = OpenAIService(apiKey: AppConfig.openAIAPIKey)
        grokService = GrokService(apiKey: AppConfig.grokAPIKey)
        deepseekService = DeepSeekService(apiKey: AppConfig.deepseekAPIKey)
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
            isRecording = false
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
            isRecording = false
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
            let finalText = speechRecognitionService.stopRecording()
            isRecording = false
            if !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                currentInput = appendedSpeechText(
                    base: recordingBaseText,
                    recognized: finalText
                )
            }
            return
        }

        guard speechRecognitionService.isAuthorized else {
            print("Speech recognition not authorized")
            return
        }

        do {
            recordingBaseText = currentInput
            try speechRecognitionService.startRecording()
            isRecording = true
        } catch {
            print("Failed to start recording: \(error.localizedDescription)")
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
            
            // Get conversation context if enabled
            let contextData = continueConversation ? conversationHistory.getContextForPrompt() : []
            
            // Debug logging
            if continueConversation {
                print("✓ Continue Conversation ENABLED - Sending \(contextData.count) context(s) to AI")
            } else {
                print("○ Continue Conversation DISABLED - No context sent to AI")
            }
            
            let stream: AsyncThrowingStream<StreamingResponse, Error>
            
            // Select the appropriate service based on provider
            switch selectedProvider {
            case .openAI:
                stream = openAIService.streamInterviewResponse(
                    prompt: question,
                    category: selectedCategory,
                    language: selectedLanguage,
                    includeOptionalCodePhase: false,
                    imageData: imageData,
                    conversationContext: contextData
                )
            case .grok:
                stream = grokService.streamInterviewResponse(
                    prompt: question,
                    category: selectedCategory,
                    language: selectedLanguage,
                    includeOptionalCodePhase: false,
                    imageData: imageData,
                    conversationContext: contextData
                )
            case .deepseek:
                stream = deepseekService.streamInterviewResponse(
                    prompt: question,
                    category: selectedCategory,
                    language: selectedLanguage,
                    includeOptionalCodePhase: false,
                    imageData: imageData,
                    conversationContext: contextData
                )
            case .gemini:
                // Fallback to OpenAI for now
                stream = openAIService.streamInterviewResponse(
                    prompt: question,
                    category: selectedCategory,
                    language: selectedLanguage,
                    includeOptionalCodePhase: false,
                    imageData: imageData,
                    conversationContext: contextData
                )
            }
            
            for try await response in stream {
                updateStreamingMessage(
                    messageId: messageId,
                    response: response
                )
            }
            
            finalizeStreamingMessage(messageId: messageId, question: question)
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
    
    private func finalizeStreamingMessage(messageId: UUID, question: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        
        let content = messages[index].content
        messages[index] = ChatMessage(
            id: messageId,
            role: .assistant,
            content: content,
            timestamp: messages[index].timestamp,
            isStreaming: false
        )
        
        // Extract and save conversation context if enabled
        if continueConversation, case .structured(let aiResponse) = content {
            let context = extractConversationContext(
                question: question,
                response: aiResponse
            )
            conversationHistory.addContext(context)
            print("💾 Context saved - Total contexts: \(conversationHistory.count)")
        } else if !continueConversation {
            print("○ Context NOT saved - Continue Conversation is disabled")
        }
        
        isProcessing = false
        streamBuffer = ""
        currentMessageId = nil
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
                guard let self = self else { return }
                guard self.isRecording else { return }
                self.currentInput = self.appendedSpeechText(
                    base: self.recordingBaseText,
                    recognized: text
                )
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
