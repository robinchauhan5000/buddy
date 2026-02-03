//
//  DesignSystem.swift
//  musicplayer
//
//  Created by Robin Chauhan on 03/02/26.
//

import SwiftUI

enum DesignSystem {
    // MARK: - Colors
    enum Colors {
        static let background = Color(hex: "0A0A0A")
        static let secondaryBackground = Color(hex: "1A1A1A")
        static let tertiaryBackground = Color(hex: "252525")
        static let accent = Color(hex: "6366F1")
        static let accentPurple = Color(hex: "7C3AED")
        static let activeGreen = Color(hex: "10B981")
        static let textPrimary = Color.white
        static let textSecondary = Color(hex: "9CA3AF")
        static let textTertiary = Color(hex: "6B7280")
        static let border = Color(hex: "374151")
        static let cardBackground = Color(hex: "1F1F1F")
    }
    
    // MARK: - Spacing
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }
    
    // MARK: - Corner Radius
    enum CornerRadius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let full: CGFloat = 999
    }
    
    // MARK: - Font Sizes
    enum FontSize {
        static let xs: CGFloat = 11
        static let sm: CGFloat = 13
        static let md: CGFloat = 15
        static let lg: CGFloat = 18
        static let xl: CGFloat = 22
        static let xxl: CGFloat = 28
    }
    
    // MARK: - Icon Sizes
    enum IconSize {
        static let sm: CGFloat = 16
        static let md: CGFloat = 20
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }
}

// MARK: - Color Extension for Hex Support
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
