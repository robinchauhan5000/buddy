import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    let onEdit: (ChatMessage) -> Void
    let onResend: (ChatMessage) -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            if message.role == .assistant {
                avatarView
            }
            
            Spacer().frame(width: 0)
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: DesignSystem.Spacing.xs) {
                contentView
                
                if message.role == .user, isUserTextMessage {
                    userActionButtons
                }
                
                if message.isStreaming {
                    streamingIndicator
                }
            }
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .user {
                Spacer().frame(width: 0)
                avatarView
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.xl)
        .padding(.vertical, DesignSystem.Spacing.lg)
    }

    private var isUserTextMessage: Bool {
        if message.role != .user { return false }
        switch message.content {
        case .text, .textWithImages:
            return true
        default:
            return false
        }
    }
    
    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(message.role == .assistant ? DesignSystem.Colors.accentPurple : DesignSystem.Colors.tertiaryBackground)
                .frame(width: 32, height: 32)
            
            Image(systemName: message.role == .assistant ? "sparkles" : "person.fill")
                .font(.system(size: 14))
                .foregroundColor(.white)
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch message.content {
        case .text(let text):
            textBubble(text)
        case .structured(let response):
            structuredResponseView(response)
        case .error(let error):
            errorBubble(error)
        case .textWithImages(let text, let images):
            textWithImagesBubble(text, images: images)
        }
    }
    
    private func textBubble(_ text: String) -> some View {
        Text(text)
            .font(.system(size: DesignSystem.FontSize.md))
            .foregroundColor(DesignSystem.Colors.textPrimary)
            .textSelection(.enabled)
            .padding(DesignSystem.Spacing.md)
            .background(
                message.role == .user
                    ? DesignSystem.Colors.accent
                    : DesignSystem.Colors.secondaryBackground
            )
            .cornerRadius(DesignSystem.CornerRadius.lg)
            .frame(maxWidth: 600, alignment: message.role == .user ? .trailing : .leading)
    }
    
    private func textWithImagesBubble(_ text: String, images: [Data]) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            // Display images
            ForEach(Array(images.enumerated()), id: \.offset) { index, imageData in
                if let nsImage = NSImage(data: imageData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 400)
                        .cornerRadius(DesignSystem.CornerRadius.md)
                }
            }
            
            // Display text if not empty
            if !text.isEmpty {
                Text(text)
                    .font(.system(size: DesignSystem.FontSize.md))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .textSelection(.enabled)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.accent)
        .cornerRadius(DesignSystem.CornerRadius.lg)
        .frame(maxWidth: 600, alignment: .trailing)
    }

    private var userActionButtons: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Button(action: { onEdit(message) }) {
                Image(systemName: "pencil")
                    .font(.system(size: DesignSystem.FontSize.sm, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            
            Button(action: { onResend(message) }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: DesignSystem.FontSize.sm, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func structuredResponseView(_ response: AIResponse) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            Text(response.title)
                .font(.system(size: DesignSystem.FontSize.lg, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .textSelection(.enabled)
            
            ForEach(Array(response.sections.enumerated()), id: \.element.id) { index, section in
                // Phase 4 mermaid_diagram: render diagram only once phase 5 has started (we have all phase 4 data).
                let phase4Complete = index < response.sections.count - 1
                sectionView(section, phase4MermaidComplete: phase4Complete)
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.secondaryBackground)
        .cornerRadius(DesignSystem.CornerRadius.lg)
    }
    
    @ViewBuilder
    private func sectionView(_ section: MessageSection, phase4MermaidComplete: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            sectionHeaderView(for: section.type)
            
            switch section.content {
            case .text(let text):
                if section.type == .mermaidDiagram {
                    // Render phase 4 Mermaid only when phase 5 has started (we have full diagram data).
                    if phase4MermaidComplete {
                        mermaidBlockView(mermaidCode: text)
                    } else {
                        codeBlockView(text, language: "mermaid")
                    }
                } else if section.type == .code {
                    if MessageBubbleView.isMermaidContent(text, language: section.language) {
                        mermaidOrStreamingView(text: text, language: section.language)
                    } else {
                        codeBlockView(text, language: section.language)
                    }
                } else if MessageBubbleView.isMermaidContent(text, language: nil) {
                    mermaidOrStreamingView(text: text, language: nil)
                } else {
                    textContentView(text)
                }
            case .list(let items):
                let combined = items.joined(separator: "\n")
                if section.type == .mermaidDiagram {
                    if phase4MermaidComplete {
                        mermaidBlockView(mermaidCode: combined)
                    } else {
                        codeBlockView(combined, language: "mermaid")
                    }
                } else if MessageBubbleView.isMermaidContent(combined, language: nil) {
                    mermaidOrStreamingView(text: combined, language: nil)
                } else {
                    listContentView(items)
                }
            }
        }
    }
    
    /// Show raw code while streaming (incomplete Mermaid would cause syntax error); render diagram when complete.
    @ViewBuilder
    private func mermaidOrStreamingView(text: String, language: String?) -> some View {
        if message.isStreaming {
            codeBlockView(text, language: language ?? "mermaid")
        } else {
            mermaidBlockView(mermaidCode: text)
        }
    }
    
    private func mermaidBlockView(mermaidCode: String) -> some View {
        MermaidDiagramBlockView(mermaidCode: mermaidCode)
            .cornerRadius(DesignSystem.CornerRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
            )
    }
    
    /// Only treat as Mermaid when explicitly tagged or content starts with a Mermaid diagram declaration.
    /// Do not use loose patterns like "->" or "---" — those appear in normal flow text (e.g. "ServiceA -> ServiceB").
    private static func isMermaidContent(_ text: String, language: String?) -> Bool {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return false }
        if language?.lowercased() == "mermaid" { return true }
        let lower = raw.lowercased()
        if lower.hasPrefix("graph ") || lower.hasPrefix("flowchart ") { return true }
        if lower.hasPrefix("sequencediagram") { return true }
        if lower.hasPrefix("classdiagram") { return true }
        if lower.hasPrefix("statediagram") { return true }
        if lower.hasPrefix("erDiagram") || lower.hasPrefix("erdiagram") { return true }
        return false
    }
    
    private func sectionHeaderView(for type: SectionType) -> some View {
        Text(type.displayName)
            .font(.system(size: DesignSystem.FontSize.md, weight: .semibold))
            .foregroundColor(DesignSystem.Colors.accent)
            .textCase(.uppercase)
            .tracking(0.5)
            .textSelection(.enabled)
    }
    
    private func textContentView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: DesignSystem.FontSize.md))
            .foregroundColor(DesignSystem.Colors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
    
    private func listContentView(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                    Text("•")
                        .foregroundColor(DesignSystem.Colors.accent)
                    Text(item)
                        .font(.system(size: DesignSystem.FontSize.md))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }
    
    private func codeBlockView(_ code: String, language: String?) -> some View {
        let displayLanguage = language ?? CodeHighlighter.parseLanguage(from: code)
        let highlighted = CodeHighlighter.highlight(content: code, explicitLanguage: language)

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let lang = displayLanguage, !lang.isEmpty {
                    Text(lang)
                        .font(.system(size: DesignSystem.FontSize.xs, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .padding(.horizontal, DesignSystem.Spacing.sm)
                        .padding(.vertical, DesignSystem.Spacing.xs)
                        .background(DesignSystem.Colors.tertiaryBackground)
                        .cornerRadius(DesignSystem.CornerRadius.sm)
                        .textSelection(.enabled)
                }

                Spacer()

                Button(action: { MessageBubbleView.copyToPasteboard(code) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: DesignSystem.FontSize.xs, weight: .medium))
                        Text("Copy")
                            .font(.system(size: DesignSystem.FontSize.xs, weight: .medium))
                    }
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .background(DesignSystem.Colors.tertiaryBackground)
                    .cornerRadius(DesignSystem.CornerRadius.sm)
                }
                .buttonStyle(.plain)
            }
            .padding(DesignSystem.Spacing.sm)
            .background(DesignSystem.Colors.background)

            ScrollView(.horizontal, showsIndicators: true) {
                Group {
                    if let ns = highlighted {
                        Text(AttributedString(ns))
                    } else {
                        Text(code)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                    }
                }
                .font(.system(size: DesignSystem.FontSize.sm, design: .monospaced))
                .padding(DesignSystem.Spacing.md)
                .textSelection(.enabled)
            }
            .background(DesignSystem.Colors.background)
        }
        .cornerRadius(DesignSystem.CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
    }

    private func copyToPasteboard(_ text: String) {
        guard !text.isEmpty else { return }
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }

    private static func copyToPasteboard(_ text: String) {
        guard !text.isEmpty else { return }
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
    
    private func errorBubble(_ error: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(error)
                .font(.system(size: DesignSystem.FontSize.sm))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .textSelection(.enabled)
        }
        .padding(DesignSystem.Spacing.md)
        .background(Color.red.opacity(0.1))
        .cornerRadius(DesignSystem.CornerRadius.md)
    }
    
    private var streamingIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(DesignSystem.Colors.accent)
                    .frame(width: 6, height: 6)
                    .opacity(0.5)
            }
        }
    }
}
