import SwiftUI
import AppKit

// MARK: - Auto-scrolling text view (macOS)

private struct AutoScrollTextView: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var textColor: NSColor
    var isEnabled: Bool
    var minHeight: CGFloat
    var maxHeight: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.font = font
        textView.textColor = textColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let contentWidth = scrollView.contentSize.width
        if contentWidth > 0, let container = textView.textContainer {
            container.containerSize = NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
        }
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = isEnabled
        textView.isSelectable = isEnabled
        context.coordinator.scrollToSelection()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AutoScrollTextView
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?

        init(_ parent: AutoScrollTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            scrollToSelection()
        }

        func scrollToSelection() {
            guard let textView = textView else { return }
            DispatchQueue.main.async {
                let range = textView.selectedRange()
                if range.location != NSNotFound {
                    textView.scrollRangeToVisible(range)
                }
            }
        }
    }
}

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
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Ask your interview question...")
                            .font(.system(size: DesignSystem.FontSize.md))
                            .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.7))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                    }
                    AutoScrollTextView(
                        text: $text,
                        font: .systemFont(ofSize: DesignSystem.FontSize.md),
                        textColor: NSColor.white,
                        isEnabled: !isProcessing,
                        minHeight: 22,
                        maxHeight: 70
                    )
                    .frame(minHeight: 22, maxHeight: 70)
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
