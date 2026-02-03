//
//  SettingsView.swift
//  musicplayer
//
//  Settings view for configuring app preferences
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedProvider: AIProvider
    @Binding var selectedCategory: Category
    @Binding var selectedLanguage: ProgrammingLanguage
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignSystem.Spacing.xl)
            .padding(.vertical, DesignSystem.Spacing.lg)
            .background(DesignSystem.Colors.secondaryBackground)
            
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                    // AI Provider Section
                    settingsSection(title: "AI Provider") {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                            ForEach(AIProvider.allCases) { provider in
                                providerRow(provider)
                            }
                        }
                    }
                    
                    Divider()
                        .background(DesignSystem.Colors.border)
                    
                    // Default Language Section
                    settingsSection(title: "Default Programming Language") {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                            LanguagePicker(selectedLanguage: $selectedLanguage)
                                .frame(maxWidth: 300)
                        }
                    }
                    
                    Divider()
                        .background(DesignSystem.Colors.border)
                    
                    // Default Category Section
                    settingsSection(title: "Default Category") {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                            CategoryPicker(selectedCategory: $selectedCategory)
                                .frame(maxWidth: 300)
                        }
                    }
                    
                    Divider()
                        .background(DesignSystem.Colors.border)
                    
                    // Permissions Section
                    settingsSection(title: "Permissions") {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                            permissionRow(
                                icon: "mic.fill",
                                title: "Microphone Access",
                                description: "Required for voice input"
                            )
                            
                            permissionRow(
                                icon: "text.bubble.fill",
                                title: "Speech Recognition",
                                description: "Required for converting speech to text"
                            )
                            
                            permissionRow(
                                icon: "camera.viewfinder",
                                title: "Screen Recording",
                                description: "Required for capturing screenshots"
                            )
                        }
                    }
                    
                    Divider()
                        .background(DesignSystem.Colors.border)
                    
                    // About Section
                    settingsSection(title: "About") {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Interview Copilot")
                                .font(.system(size: DesignSystem.FontSize.lg, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            
                            Text("Version 1.0.0")
                                .font(.system(size: DesignSystem.FontSize.md))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            
                            Text("AI-powered interview assistant with screenshot analysis")
                                .font(.system(size: DesignSystem.FontSize.sm))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                                .padding(.top, DesignSystem.Spacing.xs)
                        }
                    }
                }
                .padding(DesignSystem.Spacing.xl)
            }
            .background(DesignSystem.Colors.background)
        }
        .frame(width: 600, height: 700)
        .background(DesignSystem.Colors.background)
    }
    
    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text(title)
                .font(.system(size: DesignSystem.FontSize.lg, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            content()
        }
    }
    
    private func providerRow(_ provider: AIProvider) -> some View {
        Button(action: { selectedProvider = provider }) {
            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: selectedProvider == provider ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(selectedProvider == provider ? DesignSystem.Colors.accent : DesignSystem.Colors.textSecondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.rawValue)
                        .font(.system(size: DesignSystem.FontSize.md, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    Text(provider.description)
                        .font(.system(size: DesignSystem.FontSize.sm))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                Spacer()
            }
            .padding(DesignSystem.Spacing.md)
            .background(
                selectedProvider == provider
                    ? DesignSystem.Colors.accent.opacity(0.1)
                    : DesignSystem.Colors.tertiaryBackground
            )
            .cornerRadius(DesignSystem.CornerRadius.md)
        }
        .buttonStyle(.plain)
    }
    
    private func permissionRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.accent.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(DesignSystem.Colors.accent)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: DesignSystem.FontSize.md, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text(description)
                    .font(.system(size: DesignSystem.FontSize.sm))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            
            Spacer()
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.tertiaryBackground)
        .cornerRadius(DesignSystem.CornerRadius.md)
    }
}

extension AIProvider {
    var description: String {
        switch self {
        case .openAI:
            return "GPT-4 powered responses with vision support"
        case .gemini:
            return "Google's multimodal AI model"
        }
    }
}

#Preview {
    @Previewable @State var provider: AIProvider = .openAI
    @Previewable @State var category: Category = .normal
    @Previewable @State var language: ProgrammingLanguage = .golang
    
    SettingsView(
        selectedProvider: $provider,
        selectedCategory: $category,
        selectedLanguage: $language
    )
}
