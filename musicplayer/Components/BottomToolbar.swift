//
//  BottomToolbar.swift
//  musicplayer
//
//  Created by Robin Chauhan on 03/02/26.
//

import SwiftUI

struct BottomToolbar: View {
    let isRecording: Bool
    let onRecord: () -> Void
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Button(action: onRecord) {
                ZStack {
                    Circle()
                        .fill(isRecording ? DesignSystem.Colors.activeGreen : Color.red.opacity(0.8))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: "mic.fill")
                        .font(.system(size: DesignSystem.IconSize.lg))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.xl)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.background)
    }
}

#Preview {
    BottomToolbar(
        isRecording: false,
        onRecord: {}
    )
    .background(DesignSystem.Colors.background)
}
