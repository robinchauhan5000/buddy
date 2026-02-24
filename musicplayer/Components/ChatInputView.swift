import SwiftUI

/// Shared abstraction for the chat input UI (mic, clear, screenshot, text field, send).
/// Use `AIBotChatInputView` for AI bot (send → API) or `WebviewChatInputView` for webview (send → inject into page input).
struct ChatInputView: View {
    @Binding var text: String
    let isProcessing: Bool
    let isRecording: Bool
    let onSend: () -> Void
    let onClear: () -> Void
    let onRecord: () -> Void
    let onCaptureScreenshot: () -> Void
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Button(action: onRecord) {
                ZStack {
                    Circle()
                        .fill(isRecording ? DesignSystem.Colors.activeGreen : Color.red.opacity(0.8))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            
            Button(action: onClear) {
                Image(systemName: "trash")
                    .font(.system(size: DesignSystem.IconSize.md))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
            
            Button(action: onCaptureScreenshot) {
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.tertiaryBackground)
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: DesignSystem.IconSize.md))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
            
            HStack(alignment: .bottom, spacing: DesignSystem.Spacing.md) {
                TextField("Ask your interview question...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: DesignSystem.FontSize.md))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1...10)
                    .disabled(isProcessing)
                    .onSubmit {
                        if !text.isEmpty && !isProcessing {
                            onSend()
                        }
                    }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.tertiaryBackground)
            .cornerRadius(DesignSystem.CornerRadius.xl)
            
            Button(action: onSend) {
                ZStack {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                        .fill(text.isEmpty || isProcessing ? DesignSystem.Colors.tertiaryBackground : DesignSystem.Colors.accent)
                        .frame(width: 56, height: 56)
                    
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: DesignSystem.IconSize.md, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(text.isEmpty || isProcessing)
        }
        .padding(.horizontal, DesignSystem.Spacing.xl)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.secondaryBackground)
    }
}
