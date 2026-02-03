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
    
    private var streamBuffer: String = ""
    private var currentMessageId: UUID?
    private let openAIService: OpenAIService
    private let speechRecognitionService = SpeechRecognitionService()
    private var recordingBaseText: String = ""
    private var cancellables: Set<AnyCancellable> = []
    private var streamingTask: Task<Void, Never>?
    
    init(apiKey: String? = nil) {
        let key = apiKey ?? AppConfig.openAIAPIKey
        self.openAIService = OpenAIService(apiKey: key)
        bindSpeechRecognition()
    }
    
    func sendMessage() {
        guard !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let userMessage = ChatMessage(
            role: .user,
            content: .text(currentInput),
            timestamp: Date()
        )
        
        messages.append(userMessage)
        let questionText = currentInput
        currentInput = ""
        isProcessing = true
        
        streamingTask?.cancel()
        streamingTask = Task {
            await processAIResponse(for: questionText)
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
    }

    func clearInput() {
        currentInput = ""
        recordingBaseText = ""
        streamingTask?.cancel()
        streamingTask = nil
        stopStreamingState()
        if isRecording {
            speechRecognitionService.cancelRecording()
            isRecording = false
        }
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
    
    private func processAIResponse(for question: String) async {
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
        
        await streamAIResponse(messageId: messageId, question: question)
    }
    
    private func streamAIResponse(messageId: UUID, question: String) async {
        do {
            let stream = openAIService.streamInterviewResponse(
                prompt: question,
                category: selectedCategory,
                language: selectedLanguage,
                includeOptionalCodePhase: false,
                imageData: nil
            )
            
            for try await response in stream {
                updateStreamingMessage(
                    messageId: messageId,
                    response: response
                )
            }
            
            finalizeStreamingMessage(messageId: messageId)
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
    
    private func finalizeStreamingMessage(messageId: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        
        let content = messages[index].content
        messages[index] = ChatMessage(
            id: messageId,
            role: .assistant,
            content: content,
            timestamp: messages[index].timestamp,
            isStreaming: false
        )
        
        isProcessing = false
        streamBuffer = ""
        currentMessageId = nil
    }
    
    private func handleError(messageId: UUID, error: Error) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        
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
        }

        return "\(roleTitle):\n\(contentText)"
    }

    private func messagePlainTextIfUser(_ message: ChatMessage) -> String? {
        guard message.role == .user else { return nil }
        if case .text(let text) = message.content {
            return text
        }
        return nil
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
