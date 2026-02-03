//
//  ProviderButton.swift
//  musicplayer
//
//  Created by Robin Chauhan on 03/02/26.
//

import SwiftUI

struct ProviderButton: View {
    let provider: AIProvider
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                if provider == .streaming {
                    Image(systemName: "sparkles")
                        .font(.system(size: DesignSystem.FontSize.sm))
                }
                
                Text(provider.rawValue)
                    .font(.system(size: DesignSystem.FontSize.sm, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : DesignSystem.Colors.textSecondary)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(
                isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.tertiaryBackground
            )
            .cornerRadius(DesignSystem.CornerRadius.sm)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HStack(spacing: DesignSystem.Spacing.md) {
        ProviderButton(provider: .openAI, isSelected: true, action: {})
        ProviderButton(provider: .gemini, isSelected: false, action: {})
        ProviderButton(provider: .streaming, isSelected: false, action: {})
    }
    .padding()
    .background(DesignSystem.Colors.background)
}
