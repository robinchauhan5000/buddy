import SwiftUI

struct ChatListView: View {
    let messages: [ChatMessage]
    let onEdit: (ChatMessage) -> Void
    let onResend: (ChatMessage) -> Void
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if messages.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(messages) { message in
                            MessageBubbleView(
                                message: message,
                                onEdit: onEdit,
                                onResend: onResend
                            )
                                .id(message.id)
                        }
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity)
                .onChange(of: messages.count) { _, _ in
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            .background(DesignSystem.Colors.secondaryBackground)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.accentPurple.opacity(0.2))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 40))
                    .foregroundColor(DesignSystem.Colors.accentPurple)
            }
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Start Your Interview Practice")
                    .font(.system(size: DesignSystem.FontSize.xl, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("Ask any interview question and get detailed answers")
                    .font(.system(size: DesignSystem.FontSize.md))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.xxl)
    }
}
