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
    let onCopy: () -> Void
    let onToggleScreenShareVisibility: () -> Void
    let onMicrophone: () -> Void
    let onScreenShare: () -> Void
    let onDelete: () -> Void
    let onProviderChange: (AIProvider) -> Void
    var isMicrophoneActive: Bool = false
    var isScreenShareHidden: Bool = true
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            HStack(spacing: DesignSystem.Spacing.lg) {
                HStack(spacing: DesignSystem.Spacing.md) {
                    ForEach(AIProvider.allCases) { provider in
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
                    
                    CategoryPicker(selectedCategory: $selectedCategory)
                }
                
                Spacer()
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.xl)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.secondaryBackground)
    }
}

#Preview {
    @Previewable @State var provider: AIProvider = .openAI
    @Previewable @State var category: Category = .normal
    @Previewable @State var language: ProgrammingLanguage = .golang
    
    HeaderView(
        sessionState: .active,
        selectedProvider: $provider,
        selectedCategory: $category,
        selectedLanguage: $language,
        onCopy: {},
        onToggleScreenShareVisibility: {},
        onMicrophone: {},
        onScreenShare: {},
        onDelete: {},
        onProviderChange: { _ in },
        isMicrophoneActive: true,
        isScreenShareHidden: true
    )
    .background(DesignSystem.Colors.background)
}
