//
//  ControlBar.swift
//  musicplayer
//
//  Created by Robin Chauhan on 03/02/26.
//

import SwiftUI

struct ControlBar: View {
    @Binding var selectedProvider: AIProvider
    @Binding var selectedCategory: Category
    @Binding var selectedLanguage: ProgrammingLanguage
    
    let onProviderChange: (AIProvider) -> Void
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xl) {
            HStack(spacing: DesignSystem.Spacing.md) {
                Text("AI Provider:")
                    .font(.system(size: DesignSystem.FontSize.sm, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                HStack(spacing: DesignSystem.Spacing.sm) {
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
            }
            
            Spacer()
            
            HStack(spacing: DesignSystem.Spacing.xl) {
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
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.xl)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.background)
    }
}

#Preview {
    @Previewable @State var provider: AIProvider = .openAI
    @Previewable @State var category: Category = .normal
    @Previewable @State var language: ProgrammingLanguage = .golang
    
    ControlBar(
        selectedProvider: $provider,
        selectedCategory: $category,
        selectedLanguage: $language,
        onProviderChange: { _ in }
    )
    .background(DesignSystem.Colors.background)
}
