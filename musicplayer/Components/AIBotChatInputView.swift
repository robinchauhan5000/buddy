//
//  AIBotChatInputView.swift
//  musicplayer
//
//  Uses the shared ChatInputView with ChatViewModel. Send button triggers sending the message to the AI (API).
//

import SwiftUI

struct AIBotChatInputView: View {
    @ObservedObject var chatViewModel: ChatViewModel

    var body: some View {
        ChatInputView(
            text: $chatViewModel.currentInput,
            isProcessing: chatViewModel.isProcessing,
            isRecording: chatViewModel.isRecording,
            onSend: chatViewModel.sendMessage,
            onClear: chatViewModel.clearInput,
            onRecord: chatViewModel.toggleSpeechInput,
            onCaptureScreenshot: chatViewModel.captureScreenshot
        )
    }
}
