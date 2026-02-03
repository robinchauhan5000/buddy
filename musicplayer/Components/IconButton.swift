//
//  IconButton.swift
//  musicplayer
//
//  Created by Robin Chauhan on 03/02/26.
//

import SwiftUI

struct IconButton: View {
    let iconName: String
    let action: () -> Void
    var size: CGFloat = DesignSystem.IconSize.md
    var backgroundColor: Color = DesignSystem.Colors.tertiaryBackground
    var foregroundColor: Color = DesignSystem.Colors.textSecondary
    var isActive: Bool = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: iconName)
                .font(.system(size: size - 4))
                .foregroundColor(isActive ? DesignSystem.Colors.activeGreen : foregroundColor)
                .frame(width: size + 20, height: size + 20)
                .background(backgroundColor)
                .cornerRadius(DesignSystem.CornerRadius.md)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

#Preview {
    HStack(spacing: DesignSystem.Spacing.sm) {
        IconButton(iconName: "doc.on.doc", action: {})
        IconButton(iconName: "mic.fill", action: {}, isActive: true)
        IconButton(iconName: "rectangle.on.rectangle", action: {})
        IconButton(iconName: "trash", action: {})
    }
    .padding()
    .background(DesignSystem.Colors.background)
}
