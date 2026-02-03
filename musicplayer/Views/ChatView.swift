import SwiftUI
import Combine

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            ChatListView(messages: viewModel.messages)
            
            Divider()
                .background(DesignSystem.Colors.border)
            
            ChatInputView(
                text: $viewModel.currentInput,
                isProcessing: viewModel.isProcessing,
                isRecording: viewModel.isRecording,
                onSend: viewModel.sendMessage,
                onClear: viewModel.clearInput,
                onRecord: viewModel.toggleSpeechInput
            )
        }
        .background(DesignSystem.Colors.background)
    }
}
