//
//  InterviewCopilotViewModel.swift
//  musicplayer
//
//  Created by Robin Chauhan on 03/02/26.
//

import Foundation
import Combine
import AppKit

@MainActor
class InterviewCopilotViewModel: ObservableObject {
    @Published var selectedProvider: AIProvider = .openAI
    @Published var selectedCategory: Category = .normal
    @Published var sessionState: SessionState = .active
    @Published var isMicrophoneActive: Bool = false
    @Published var isScreenShareHidden: Bool = true
    @Published var showSettings: Bool = false
    
    private let speechRecognitionService = SpeechRecognitionService()
    private var onSpeechRecognized: ((String) -> Void)?
    
    // MARK: - Computed Properties
    
    // MARK: - Actions
    
    func setSpeechRecognizedCallback(_ callback: @escaping (String) -> Void) {
        onSpeechRecognized = callback
    }
    
    func selectProvider(_ provider: AIProvider) {
        selectedProvider = provider
    }
    
    func selectCategory(_ category: Category) {
        selectedCategory = category
    }
    
    func toggleMicrophone() {
        if isMicrophoneActive {
            // Stop recording and send the message
            let recognizedText = speechRecognitionService.stopRecording()
            isMicrophoneActive = false
            
            if !recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onSpeechRecognized?(recognizedText)
            }
        } else {
            // Start recording
            guard speechRecognitionService.isAuthorized else {
                print("Speech recognition not authorized")
                return
            }
            
            do {
                try speechRecognitionService.startRecording()
                isMicrophoneActive = true
            } catch {
                print("Failed to start recording: \(error.localizedDescription)")
            }
        }
    }

    func startMicrophoneFromShortcut() {
        guard !isMicrophoneActive else { return }
        toggleMicrophone()
    }
    
    func stopMicrophoneFromShortcut() {
        guard isMicrophoneActive else { return }
        toggleMicrophone()
    }
    
    func toggleScreenShareVisibility() {
        setScreenShareHidden(!isScreenShareHidden)
    }
    
    func setScreenShareHidden(_ hidden: Bool) {
        isScreenShareHidden = hidden
        updateWindowSharingType(hidden: hidden)
    }
    
    func shareScreen() {
        showSettings = true
    }
    
    func deleteSession() {
        print("Delete session")
    }
    
    private func updateWindowSharingType(hidden: Bool) {
        let sharingType: NSWindow.SharingType = hidden ? .none : .readOnly
        for window in NSApplication.shared.windows {
            window.sharingType = sharingType
        }
    }
}
