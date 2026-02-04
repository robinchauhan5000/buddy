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
    
    var body: some View {
        VStack(spacing: 0) {
            HeaderView(
                sessionState: viewModel.sessionState,
                selectedProvider: $chatViewModel.selectedProvider,
                selectedCategory: $chatViewModel.selectedCategory,
                selectedLanguage: $chatViewModel.selectedLanguage,
                onCopy: chatViewModel.copyAllMessages,
                onToggleScreenShareVisibility: {
                    if viewModel.isScreenShareHidden {
                        showScreenShareVisibleConfirm = true
                    } else {
                        viewModel.toggleScreenShareVisibility()
                    }
                },
                onMicrophone: viewModel.toggleMicrophone,
                onScreenShare: viewModel.shareScreen,
                onDelete: chatViewModel.clearChat,
                onProviderChange: { _ in },
                isMicrophoneActive: viewModel.isMicrophoneActive,
                isScreenShareHidden: viewModel.isScreenShareHidden
            )
            
            SessionInfoView(
                chatViewModel: chatViewModel
            )
        }
        .background(
            VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                .opacity(0.3)
        )
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView(
                viewModel: chatViewModel,
                isScreenShareHidden: viewModel.isScreenShareHidden
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
            viewModel.startMicrophoneFromShortcut()
        } else if !isCommandOnly && isCommandKeyPressed {
            isCommandKeyPressed = false
            viewModel.stopMicrophoneFromShortcut()
        }

        if isShiftOnly && !isShiftKeyPressed {
            isShiftKeyPressed = true
            chatViewModel.abortCurrentRequest()
        } else if !isShiftOnly && isShiftKeyPressed {
            isShiftKeyPressed = false
        }
    }
}
