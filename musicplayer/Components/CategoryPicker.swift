//
//  CategoryPicker.swift
//  musicplayer
//
//  Created by Robin Chauhan on 03/02/26.
//

import SwiftUI

struct CategoryPicker: View {
    @Binding var selectedCategory: Category
    
    var body: some View {
        Menu {
            ForEach(Category.allCases) { category in
                Button(action: {
                    selectedCategory = category
                }) {
                    Text(category.rawValue)
                }
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.md) {
                Text(selectedCategory.rawValue)
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

#Preview {
    @Previewable @State var category: Category = .detailedAnswer
    
    CategoryPicker(selectedCategory: $category)
        .padding()
        .background(DesignSystem.Colors.background)
}
