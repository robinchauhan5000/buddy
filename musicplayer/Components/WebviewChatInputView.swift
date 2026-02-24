//
//  WebviewChatInputView.swift
//  musicplayer
//
//  Uses the shared ChatInputView for webview mode.
//  - Record: press = start recording and write to input field; release = send that text straight to webview.
//  - Send button: sends current input to webview.
//

import SwiftUI

struct WebviewChatInputView: View {
    @ObservedObject var chatViewModel: ChatViewModel
    var webViewStore: WebViewStore?
    /// Called when user presses send. If webViewStore is set, send uses it; otherwise this is used.
    let onSendToWebView: () -> Void
    /// When set, capture button calls this (e.g. capture + sendImageToChatGPT).
    var onCaptureScreenshotForWebView: (() -> Void)? = nil

    var body: some View {
        ChatInputView(
            text: $chatViewModel.currentInput,
            isProcessing: false,
            isRecording: chatViewModel.isRecording,
            onSend: performSend,
            onClear: chatViewModel.clearInput,
            onRecord: performRecord,
            onCaptureScreenshot: onCaptureScreenshotForWebView ?? { }
        )
    }

    /// Press = start recording, text goes to input field. Release = stop and send that text to webview (as built prompt).
    private func performRecord() {
        let wasRecording = chatViewModel.isRecording
        chatViewModel.toggleSpeechInput()
        if wasRecording, let store = webViewStore {
            let userInput = chatViewModel.currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !userInput.isEmpty {
                chatViewModel.clearInput()
                let prompt = WebViewPromptBuilder.buildPromptForWebView(
                    userInput: userInput,
                    category: chatViewModel.selectedCategory,
                    language: chatViewModel.selectedLanguage,
                    useInterviewCounterQuestion: chatViewModel.useInterviewCounterQuestionPrompt
                )
                store.sendMessageToChatGPT(prompt)
            }
        }
    }

    private func performSend() {
        if let store = webViewStore, !chatViewModel.currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let userInput = chatViewModel.currentInput
            chatViewModel.clearInput()
            let prompt = WebViewPromptBuilder.buildPromptForWebView(
                userInput: userInput,
                category: chatViewModel.selectedCategory,
                language: chatViewModel.selectedLanguage,
                useInterviewCounterQuestion: chatViewModel.useInterviewCounterQuestionPrompt
            )
            DispatchQueue.main.async {
                store.sendMessageToChatGPT(prompt)
            }
        } else {
            onSendToWebView()
        }
    }
}
