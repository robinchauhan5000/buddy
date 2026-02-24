//
//  CategoryPicker.swift
//  musicplayer
//
//  Created by Robin Chauhan on 03/02/26.
//

import SwiftUI

struct CategoryPicker: View {
    @Binding var selectedCategory: Category
    @State private var isDropdownPresented = false
    /// When provided, the parent can use this to bring the header above main content (e.g. for zIndex).
    var onDropdownPresentedChange: ((Bool) -> Void)? = nil
    
    var body: some View {
        Button(action: { isDropdownPresented.toggle() }) {
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
        .buttonStyle(.plain)
        .overlay(alignment: .topLeading) {
            if isDropdownPresented {
                categoryDropdown
                    .offset(y: 44)
                    .padding(.top, DesignSystem.Spacing.xs)
            }
        }
        .zIndex(isDropdownPresented ? 1000 : 0)
        .onChange(of: isDropdownPresented) { _, new in
            onDropdownPresentedChange?(new)
        }
    }
    
    /// Solid opaque background for the popup so text stays clearly visible (no transparency).
    private static let popupBackground = Color(red: 0.11, green: 0.11, blue: 0.14)
    private static let popupRowHighlight = Color(red: 0.18, green: 0.18, blue: 0.22)
    private static let popupBorder = Color.white.opacity(0.2)

    private var categoryDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Category.allCases) { category in
                Button(action: {
                    selectedCategory = category
                    isDropdownPresented = false
                }) {
                    Text(category.rawValue)
                        .font(.system(size: DesignSystem.FontSize.md, weight: selectedCategory == category ? .semibold : .regular))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selectedCategory == category ? Self.popupRowHighlight : Color.clear)
                .contentShape(Rectangle())

                if category.id != Category.allCases.last?.id {
                    Divider()
                        .background(Self.popupBorder)
                }
            }
        }
        .background(Self.popupBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .stroke(Self.popupBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 4)
        .frame(width: 280)
    }
}

#Preview {
    @Previewable @State var category: Category = .detailedAnswer
    
    CategoryPicker(selectedCategory: $category)
        .padding()
        .background(DesignSystem.Colors.background)
}
