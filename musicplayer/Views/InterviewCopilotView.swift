//
//  InterviewCopilotView.swift
//  musicplayer
//
//  Created by Robin Chauhan on 03/02/26.
//

import SwiftUI
import Combine

struct InterviewCopilotView: View {
    @StateObject private var viewModel = InterviewCopilotViewModel()
    @StateObject private var chatViewModel = ChatViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            HeaderView(
                sessionState: viewModel.sessionState,
                selectedProvider: $chatViewModel.selectedProvider,
                selectedCategory: $chatViewModel.selectedCategory,
                selectedLanguage: $chatViewModel.selectedLanguage,
                onCopy: chatViewModel.copyAllMessages,
                onMicrophone: viewModel.toggleMicrophone,
                onScreenShare: viewModel.shareScreen,
                onDelete: chatViewModel.clearChat,
                onProviderChange: { _ in },
                isMicrophoneActive: viewModel.isMicrophoneActive
            )
            
            SessionInfoView(
                chatViewModel: chatViewModel
            )
        }
        .background(DesignSystem.Colors.background)
        .onAppear {
            // Set up callback to send recognized speech as message
            viewModel.setSpeechRecognizedCallback { recognizedText in
                chatViewModel.currentInput = recognizedText
                chatViewModel.sendMessage()
            }
        }
    }
}

#Preview {
    InterviewCopilotView()
        .frame(width: 1024, height: 768)
}
