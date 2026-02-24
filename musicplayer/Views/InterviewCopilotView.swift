//
//  InterviewCopilotView.swift
//  musicplayer
//
//  Created by Robin Chauhan on 03/02/26.
//

import SwiftUI
import Combine
import AppKit

struct InterviewCopilotView: View {
    @StateObject private var viewModel = InterviewCopilotViewModel()
    @StateObject private var chatViewModel = ChatViewModel()
    @State private var showScreenShareVisibleConfirm = false
    @State private var commandKeyMonitor: Any?
    @State private var isCommandKeyPressed = false
    @State private var isShiftKeyPressed = false
    @State private var showChatGPTWebView = false
    @State private var isCategoryDropdownOpen = false
    @State private var webViewLoading = false
    @State private var webViewCanGoBack = false
    @State private var webViewCanGoForward = false
    @StateObject private var webViewStore = WebViewStore()

    private static let chatGPTURL = URL(string: "https://chatgpt.com/")!
    
    var body: some View {
        VStack(spacing: 0) {
            HeaderView(
                sessionState: viewModel.sessionState,
                selectedProvider: $chatViewModel.selectedProvider,
                selectedCategory: $chatViewModel.selectedCategory,
                selectedLanguage: $chatViewModel.selectedLanguage,
                continueConversation: $chatViewModel.continueConversation,
                useInterviewCounterQuestionPrompt: $chatViewModel.useInterviewCounterQuestionPrompt,
                onCopy: chatViewModel.copyAllMessages,
                onToggleScreenShareVisibility: {
                    if viewModel.isScreenShareHidden {
                        showScreenShareVisibleConfirm = true
                    } else {
                        viewModel.toggleScreenShareVisibility()
                    }
                },
                onMicrophone: viewModel.toggleMicrophone,
                onChromeSound: viewModel.toggleChromeSound,
                onScreenShare: viewModel.shareScreen,
                onDelete: chatViewModel.clearChat,
                onProviderChange: { _ in },
                isChatGPTWebViewShown: showChatGPTWebView,
                onToggleChatGPTWebView: { showChatGPTWebView.toggle() },
                isMicrophoneActive: viewModel.isMicrophoneActive,
                microphoneCaptionText: viewModel.microphoneCaptionText,
                isChromeSoundActive: viewModel.isChromeSoundActive,
                isScreenShareHidden: viewModel.isScreenShareHidden,
                isCategoryDropdownOpen: $isCategoryDropdownOpen
            )
            
            if showChatGPTWebView {
                VStack(spacing: 0) {
                    WebViewWrapper(
                        url: .constant(Self.chatGPTURL),
                        isLoading: $webViewLoading,
                        canGoBack: $webViewCanGoBack,
                        canGoForward: $webViewCanGoForward,
                        webViewStore: webViewStore,
                        onChatGPTReady: nil
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    WebviewChatInputView(
                        chatViewModel: chatViewModel,
                        webViewStore: webViewStore,
                        onSendToWebView: { },
                        onCaptureScreenshotForWebView: {
                            // When screen capture button is clicked, capture and add image to ChatGPT (same as reference)
                            Task {
                                if let image = await chatViewModel.captureScreenshotForWebView() {
                                    await MainActor.run {
                                        webViewStore.sendImageToChatGPT(image)
                                    }
                                }
                            }
                        }
                    )
                }
                .onChange(of: chatViewModel.isRecording) { _, isRecording in
                    if isRecording { webViewStore.duckAudio() } else { webViewStore.restoreAudio() }
                }
            } else {
                SessionInfoView(
                    chatViewModel: chatViewModel
                )
            }
        }
        .background(
            VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                .opacity(0.3)
        )
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView(
                viewModel: chatViewModel,
                isScreenShareHidden: viewModel.isScreenShareHidden,
                onWindowDidAppear: { viewModel.reapplyWindowSharingType() }
            )
        }
        .confirmationDialog(
            "Make it?",
            isPresented: $showScreenShareVisibleConfirm,
            titleVisibility: .visible
        ) {
            Button("Yes") {
                viewModel.toggleScreenShareVisibility()
            }
            Button("No", role: .cancel) {}
        } message: {
            Text("Do you really want to close.")
        }
        .onAppear {
            viewModel.setScreenShareHidden(true)
            // Set up callback to send recognized speech as message
            viewModel.setSpeechRecognizedCallback { recognizedText in
                chatViewModel.currentInput = recognizedText
                chatViewModel.sendMessage()
            }
            startCommandKeyMonitor()
        }
        .onDisappear {
            stopCommandKeyMonitor()
        }
    }
}

#Preview {
    InterviewCopilotView()
        .frame(width: 1024, height: 768)
}

// MARK: - Visual Effect Blur
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Command Key Handling
private extension InterviewCopilotView {
    func startCommandKeyMonitor() {
        guard commandKeyMonitor == nil else { return }
        commandKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            handleFlagsChanged(event)
            return event
        }
    }
    
    func stopCommandKeyMonitor() {
        if let monitor = commandKeyMonitor {
            NSEvent.removeMonitor(monitor)
            commandKeyMonitor = nil
        }
        isCommandKeyPressed = false
        isShiftKeyPressed = false
    }
    
    func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommandOnly = flags == [.command]
        let isShiftOnly = flags == [.shift]
        
        if isCommandOnly && !isCommandKeyPressed {
            isCommandKeyPressed = true
            if showChatGPTWebView {
                if !chatViewModel.isRecording {
                    chatViewModel.toggleSpeechInput()
                }
            } else {
                viewModel.startMicrophoneFromShortcut()
            }
        } else if !isCommandOnly && isCommandKeyPressed {
            isCommandKeyPressed = false
            if showChatGPTWebView {
                if chatViewModel.isRecording {
                    chatViewModel.toggleSpeechInput()
                    let userInput = chatViewModel.currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !userInput.isEmpty {
                        chatViewModel.clearInput()
                        let prompt = WebViewPromptBuilder.buildPromptForWebView(
                            userInput: userInput,
                            category: chatViewModel.selectedCategory,
                            language: chatViewModel.selectedLanguage,
                            useInterviewCounterQuestion: chatViewModel.useInterviewCounterQuestionPrompt
                        )
                        webViewStore.sendMessageToChatGPT(prompt)
                    }
                }
            } else {
                viewModel.stopMicrophoneFromShortcut()
            }
        }

        if isShiftOnly && !isShiftKeyPressed {
            isShiftKeyPressed = true
            if showChatGPTWebView {
                webViewStore.stopStreamingInWebView()
            } else {
                chatViewModel.abortCurrentRequest()
            }
        } else if !isShiftOnly && isShiftKeyPressed {
            isShiftKeyPressed = false
        }
    }
}
