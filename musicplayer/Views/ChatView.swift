import SwiftUI
import Combine

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            ChatListView(
                messages: viewModel.messages,
                onEdit: viewModel.editMessage,
                onResend: viewModel.resendMessage
            )
            
            Divider()
                .background(DesignSystem.Colors.border)
            
            if viewModel.isProcessing {
                HStack {
                    Spacer()
                    Button(action: viewModel.abortCurrentRequest) {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: DesignSystem.FontSize.sm, weight: .semibold))
                            Text("Stop")
                                .font(.system(size: DesignSystem.FontSize.sm, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .background(DesignSystem.Colors.accent)
                        .cornerRadius(DesignSystem.CornerRadius.md)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.vertical, DesignSystem.Spacing.sm)
            }
            
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
