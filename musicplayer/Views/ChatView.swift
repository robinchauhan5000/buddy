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
            
            // Screenshot preview area at bottom of chat
            if !viewModel.capturedScreenshots.isEmpty {
                screenshotPreviewArea
            }
            
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
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                        .fill(DesignSystem.Colors.secondaryBackground)
                        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
                )
                .padding(.horizontal, DesignSystem.Spacing.xl)
            }
            
            AIBotChatInputView(chatViewModel: viewModel)
        }
        .background(DesignSystem.Colors.background)
    }
    
    private var screenshotPreviewArea: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.md) {
                ForEach(viewModel.capturedScreenshots) { screenshot in
                    screenshotThumbnail(screenshot)
                }
                
                // Send button at the end
                sendScreenshotsButton
            }
            .padding(.horizontal, DesignSystem.Spacing.xl)
            .padding(.vertical, DesignSystem.Spacing.md)
        }
        .background(DesignSystem.Colors.secondaryBackground)
    }
    
    private func screenshotThumbnail(_ screenshot: ScreenshotData) -> some View {
        ZStack(alignment: .topTrailing) {
            if let nsImage = NSImage(data: screenshot.imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 90)
                    .cornerRadius(DesignSystem.CornerRadius.md)
                    .clipped()
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .fill(DesignSystem.Colors.tertiaryBackground)
                    .frame(width: 120, height: 90)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    )
            }
            
            Button(action: { viewModel.removeScreenshot(screenshot) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .background(Circle().fill(Color.black.opacity(0.6)).padding(-4))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
        }
    }
    
    private var sendScreenshotsButton: some View {
        Button(action: viewModel.sendMessage) {
            VStack(spacing: DesignSystem.Spacing.xs) {
                ZStack {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                        .fill(DesignSystem.Colors.accent)
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                }
                
                Text("Send")
                    .font(.system(size: DesignSystem.FontSize.xs, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isProcessing)
    }
}
