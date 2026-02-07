//
//  SettingsView.swift
//  musicplayer
//
//  Settings view for configuring app preferences
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ChatViewModel
    let isScreenShareHidden: Bool
    
    @State private var openAIKey: String = ""
    @State private var claudeKey: String = ""
    @State private var grokKey: String = ""
    @State private var deepseekKey: String = ""
    @State private var geminiKey: String = ""
    @State private var showSaveConfirmation: Bool = false
    @State private var hasUnsavedChanges: Bool = false
    
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
                    // API Keys Section
                    settingsSection(title: "API Keys") {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                            Text("Configure your AI provider API keys. Keys are stored securely in your system.")
                                .font(.system(size: DesignSystem.FontSize.sm))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                                .padding(.bottom, DesignSystem.Spacing.xs)
                            
                            apiKeyField(
                                title: "OpenAI API Key",
                                placeholder: "sk-...",
                                value: $openAIKey,
                                icon: "brain.head.profile"
                            )
                            
                            apiKeyField(
                                title: "Claude API Key (Anthropic)",
                                placeholder: "sk-ant-...",
                                value: $claudeKey,
                                icon: "bubble.left.and.bubble.right.fill"
                            )
                            
                            apiKeyField(
                                title: "Grok API Key (X.AI)",
                                placeholder: "xai-...",
                                value: $grokKey,
                                icon: "sparkles"
                            )
                            
                            apiKeyField(
                                title: "DeepSeek API Key",
                                placeholder: "sk-...",
                                value: $deepseekKey,
                                icon: "cpu"
                            )
                            
                            apiKeyField(
                                title: "Gemini API Key",
                                placeholder: "AI...",
                                value: $geminiKey,
                                icon: "star.circle"
                            )
                            
                            // Save Button
                            HStack {
                                Spacer()
                                
                                Button(action: saveAPIKeys) {
                                    HStack(spacing: DesignSystem.Spacing.sm) {
                                        Image(systemName: showSaveConfirmation ? "checkmark.circle.fill" : "square.and.arrow.down")
                                            .font(.system(size: 16))
                                        
                                        Text(showSaveConfirmation ? "Saved!" : "Save API Keys")
                                            .font(.system(size: DesignSystem.FontSize.md, weight: .semibold))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, DesignSystem.Spacing.lg)
                                    .padding(.vertical, DesignSystem.Spacing.md)
                                    .background(showSaveConfirmation ? Color.green : DesignSystem.Colors.accent)
                                    .cornerRadius(DesignSystem.CornerRadius.md)
                                }
                                .buttonStyle(.plain)
                                .disabled(showSaveConfirmation)
                            }
                            .padding(.top, DesignSystem.Spacing.sm)
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
        .frame(width: 600, height: 600)
        .background(DesignSystem.Colors.background)
        .onAppear {
            loadAPIKeys()
            updateSharingType(isHidden: isScreenShareHidden)
        }
        .onChange(of: isScreenShareHidden) { _, newValue in
            updateSharingType(isHidden: newValue)
        }
    }
    
    private func apiKeyField(title: String, placeholder: String, value: Binding<String>, icon: String) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(DesignSystem.Colors.accent)
                
                Text(title)
                    .font(.system(size: DesignSystem.FontSize.sm, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
            }
            
            SecureField(placeholder, text: value)
                .textFieldStyle(.plain)
                .font(.system(size: DesignSystem.FontSize.md, design: .monospaced))
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.tertiaryBackground)
                .cornerRadius(DesignSystem.CornerRadius.sm)
                .onChange(of: value.wrappedValue) { _, _ in
                    hasUnsavedChanges = true
                    showSaveConfirmation = false
                }
        }
    }
    
    private func loadAPIKeys() {
        openAIKey = AppConfig.openAIAPIKey
        claudeKey = AppConfig.claudeAPIKey
        grokKey = AppConfig.grokAPIKey
        deepseekKey = AppConfig.deepseekAPIKey
        geminiKey = AppConfig.geminiAPIKey
        hasUnsavedChanges = false
        
        // Debug logging
        print("📥 Loaded API Keys from storage:")
        print("  OpenAI: \(openAIKey.isEmpty ? "Not set" : "Set (\(openAIKey.count) chars)")")
        print("  Claude: \(claudeKey.isEmpty ? "Not set" : "Set (\(claudeKey.count) chars)")")
        print("  Grok: \(grokKey.isEmpty ? "Not set" : "Set (\(grokKey.count) chars)")")
        print("  DeepSeek: \(deepseekKey.isEmpty ? "Not set" : "Set (\(deepseekKey.count) chars)")")
        print("  Gemini: \(geminiKey.isEmpty ? "Not set" : "Set (\(geminiKey.count) chars)")")
    }
    
    private func saveAPIKeys() {
        AppConfig.openAIAPIKey = openAIKey
        AppConfig.claudeAPIKey = claudeKey
        AppConfig.grokAPIKey = grokKey
        AppConfig.deepseekAPIKey = deepseekKey
        AppConfig.geminiAPIKey = geminiKey
        
        // Debug logging
        print("💾 Saved API Keys to storage:")
        print("  OpenAI: \(openAIKey.isEmpty ? "Cleared" : "Saved (\(openAIKey.count) chars)")")
        print("  Claude: \(claudeKey.isEmpty ? "Cleared" : "Saved (\(claudeKey.count) chars)")")
        print("  Grok: \(grokKey.isEmpty ? "Cleared" : "Saved (\(grokKey.count) chars)")")
        print("  DeepSeek: \(deepseekKey.isEmpty ? "Cleared" : "Saved (\(deepseekKey.count) chars)")")
        print("  Gemini: \(geminiKey.isEmpty ? "Cleared" : "Saved (\(geminiKey.count) chars)")")
        
        // Refresh services with new API keys
        viewModel.refreshServices()
        
        hasUnsavedChanges = false
        showSaveConfirmation = true
        
        // Reset confirmation after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showSaveConfirmation = false
        }
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

    private func updateSharingType(isHidden: Bool) {
        #if canImport(AppKit)
        let sharingType: NSWindow.SharingType = isHidden ? .none : .readOnly
        if let keyWindow = NSApp.keyWindow {
            keyWindow.sharingType = sharingType
        } else {
            for window in NSApplication.shared.windows {
                window.sharingType = sharingType
            }
        }
        #endif
    }
}

#Preview {
    let viewModel = ChatViewModel()
    
    SettingsView(viewModel: viewModel, isScreenShareHidden: true)
}
