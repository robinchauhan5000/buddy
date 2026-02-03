import SwiftUI

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    let isRecording: Bool
    let onRecord: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            ChatListView(messages: viewModel.messages)
            
            Divider()
                .background(DesignSystem.Colors.border)
            
            ChatInputView(
                text: $viewModel.currentInput,
                isProcessing: viewModel.isProcessing,
                isRecording: isRecording,
                onSend: viewModel.sendMessage,
                onClear: viewModel.clearChat,
                onRecord: onRecord
            )
        }
        .background(DesignSystem.Colors.background)
    }
}
