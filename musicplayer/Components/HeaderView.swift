//
//  HeaderView.swift
//  musicplayer
//
//  Created by Robin Chauhan on 03/02/26.
//

import SwiftUI

struct HeaderView: View {
    let sessionState: SessionState
    @Binding var selectedProvider: AIProvider
    @Binding var selectedCategory: Category
    @Binding var selectedLanguage: ProgrammingLanguage
    @Binding var continueConversation: Bool
    @Binding var useInterviewCounterQuestionPrompt: Bool
    let onCopy: () -> Void
    let onToggleScreenShareVisibility: () -> Void
    let onMicrophone: () -> Void
    let onChromeSound: () -> Void
    let onScreenShare: () -> Void
    let onDelete: () -> Void
    let onProviderChange: (AIProvider) -> Void
    var isChatGPTWebViewShown: Bool = false
    let onToggleChatGPTWebView: () -> Void
    var isMicrophoneActive: Bool = false
    var microphoneCaptionText: String = ""
    var isChromeSoundActive: Bool = false
    var isScreenShareHidden: Bool = true
    /// When set, header zIndex is raised while the category dropdown is open so it appears above main content.
    var isCategoryDropdownOpen: Binding<Bool>? = nil
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            HStack(spacing: DesignSystem.Spacing.lg) {
                HStack(spacing: DesignSystem.Spacing.md) {
                    ForEach([AIProvider.openAI, AIProvider.gemini]) { provider in
                        ProviderButton(
                            provider: provider,
                            isSelected: selectedProvider == provider,
                            action: {
                                selectedProvider = provider
                                onProviderChange(provider)
                            }
                        )
                    }
                }
                
                Spacer()
                
                IconButton(
                    iconName: isScreenShareHidden ? "eye.slash" : "eye",
                    action: onToggleScreenShareVisibility,
                    size: DesignSystem.IconSize.lg,
                    backgroundColor: DesignSystem.Colors.tertiaryBackground,
                    foregroundColor: DesignSystem.Colors.textSecondary,
                    isActive: !isScreenShareHidden
                )
                
                Spacer()
                
                HStack(spacing: DesignSystem.Spacing.lg) {
                    IconButton(
                        iconName: isChatGPTWebViewShown ? "bubble.left.and.bubble.right" : "globe",
                        action: onToggleChatGPTWebView,
                        size: DesignSystem.IconSize.lg,
                        backgroundColor: DesignSystem.Colors.tertiaryBackground,
                        foregroundColor: DesignSystem.Colors.textSecondary,
                        isActive: isChatGPTWebViewShown
                    )
                    IconButton(
                        iconName: "doc.on.doc",
                        action: onCopy,
                        size: DesignSystem.IconSize.lg,
                        backgroundColor: DesignSystem.Colors.tertiaryBackground,
                        foregroundColor: DesignSystem.Colors.textSecondary
                    )
                    IconButton(
                        iconName: "mic.fill",
                        action: onMicrophone,
                        size: DesignSystem.IconSize.lg,
                        backgroundColor: DesignSystem.Colors.tertiaryBackground,
                        foregroundColor: DesignSystem.Colors.textSecondary,
                        isActive: isMicrophoneActive
                    )
                    IconButton(
                        iconName: "speaker.wave.2.fill",
                        action: onChromeSound,
                        size: DesignSystem.IconSize.lg,
                        backgroundColor: DesignSystem.Colors.tertiaryBackground,
                        foregroundColor: DesignSystem.Colors.textSecondary,
                        isActive: isChromeSoundActive
                    )
                    IconButton(
                        iconName: "trash",
                        action: onDelete,
                        size: DesignSystem.IconSize.lg,
                        backgroundColor: DesignSystem.Colors.tertiaryBackground,
                        foregroundColor: DesignSystem.Colors.textSecondary
                    )
                    IconButton(
                        iconName: "gearshape.fill",
                        action: onScreenShare,
                        size: DesignSystem.IconSize.lg,
                        backgroundColor: DesignSystem.Colors.tertiaryBackground,
                        foregroundColor: DesignSystem.Colors.textSecondary
                    )
                }
            }
            
            HStack(spacing: DesignSystem.Spacing.lg) {
                HStack(spacing: DesignSystem.Spacing.md) {
                    Text("Language:")
                        .font(.system(size: DesignSystem.FontSize.sm, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    LanguagePicker(selectedLanguage: $selectedLanguage)
                }
                
                HStack(spacing: DesignSystem.Spacing.md) {
                    Text("Category:")
                        .font(.system(size: DesignSystem.FontSize.sm, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    CategoryPicker(
                        selectedCategory: $selectedCategory,
                        onDropdownPresentedChange: isCategoryDropdownOpen.map { binding in { binding.wrappedValue = $0 } }
                    )
                        .disabled(useInterviewCounterQuestionPrompt)
                        .opacity(useInterviewCounterQuestionPrompt ? 0.6 : 1)
                }
                
                if !isChatGPTWebViewShown {
                    HStack(spacing: DesignSystem.Spacing.md) {
                        Toggle(isOn: $useInterviewCounterQuestionPrompt) {
                            HStack(spacing: DesignSystem.Spacing.xs) {
                                Image(systemName: useInterviewCounterQuestionPrompt ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                                    .font(.system(size: DesignSystem.FontSize.md))
                                Text("Counter Questions")
                                    .font(.system(size: DesignSystem.FontSize.sm, weight: .medium))
                            }
                            .foregroundColor(useInterviewCounterQuestionPrompt ? DesignSystem.Colors.accentPurple : DesignSystem.Colors.textSecondary)
                        }
                        .toggleStyle(.button)
                        .buttonStyle(.plain)
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                .fill(useInterviewCounterQuestionPrompt ? DesignSystem.Colors.accentPurple.opacity(0.1) : DesignSystem.Colors.tertiaryBackground)
                        )
                    }
                    
                    HStack(spacing: DesignSystem.Spacing.md) {
                        Toggle(isOn: $continueConversation) {
                            HStack(spacing: DesignSystem.Spacing.xs) {
                                Image(systemName: continueConversation ? "arrow.triangle.turn.up.right.circle.fill" : "arrow.triangle.turn.up.right.circle")
                                    .font(.system(size: DesignSystem.FontSize.md))
                                Text("Continue Conversation")
                                    .font(.system(size: DesignSystem.FontSize.sm, weight: .medium))
                            }
                            .foregroundColor(continueConversation ? DesignSystem.Colors.accent : DesignSystem.Colors.textSecondary)
                        }
                        .toggleStyle(.button)
                        .buttonStyle(.plain)
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                .fill(continueConversation ? DesignSystem.Colors.accent.opacity(0.1) : DesignSystem.Colors.tertiaryBackground)
                        )
                    }
                }
                
                Spacer()
            }

            if isMicrophoneActive || isChromeSoundActive {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: isChromeSoundActive ? "speaker.wave.2.fill" : "mic.fill")
                        .font(.system(size: DesignSystem.FontSize.sm))
                        .foregroundColor(DesignSystem.Colors.accent)
                    Text(microphoneCaptionText.isEmpty ? "Listening…" : microphoneCaptionText)
                        .font(.system(size: DesignSystem.FontSize.sm))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(DesignSystem.Colors.tertiaryBackground)
                .cornerRadius(DesignSystem.CornerRadius.sm)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.xl)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.secondaryBackground)
        .zIndex((isCategoryDropdownOpen?.wrappedValue ?? false) ? 1000 : 0)
    }
}

#Preview {
    @Previewable @State var provider: AIProvider = .openAI
    @Previewable @State var category: Category = .detailedAnswer
    @Previewable @State var language: ProgrammingLanguage = .golang
    @Previewable @State var continueConversation: Bool = true
    @Previewable @State var useInterviewCounterQuestionPrompt: Bool = false
    
    HeaderView(
        sessionState: .active,
        selectedProvider: $provider,
        selectedCategory: $category,
        selectedLanguage: $language,
        continueConversation: $continueConversation,
        useInterviewCounterQuestionPrompt: $useInterviewCounterQuestionPrompt,
        onCopy: {},
        onToggleScreenShareVisibility: {},
        onMicrophone: {},
        onChromeSound: {},
        onScreenShare: {},
        onDelete: {},
        onProviderChange: { _ in },
        isChatGPTWebViewShown: false,
        onToggleChatGPTWebView: {},
        isMicrophoneActive: true,
        microphoneCaptionText: "This is the live caption when the mic is on.",
        isChromeSoundActive: false,
        isScreenShareHidden: true
    )
    .background(DesignSystem.Colors.background)
}
