import SwiftUI

struct LanguagePicker: View {
    @Binding var selectedLanguage: ProgrammingLanguage
    
    var body: some View {
        Menu {
            ForEach(ProgrammingLanguage.allCases) { language in
                Button(action: {
                    selectedLanguage = language
                }) {
                    Text(language.rawValue)
                }
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.md) {
                Text(selectedLanguage.rawValue)
                    .font(.system(size: DesignSystem.FontSize.md, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Image(systemName: "chevron.down")
                    .font(.system(size: DesignSystem.FontSize.xs))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.tertiaryBackground)
            .cornerRadius(DesignSystem.CornerRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
    }
}
