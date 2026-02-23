//
//  InterviewCopilotViewModel.swift
//  musicplayer
//
//  Created by Robin Chauhan on 03/02/26.
//

import Foundation
import Combine
import AppKit
import Speech

@MainActor
class InterviewCopilotViewModel: ObservableObject {
    @Published var selectedProvider: AIProvider = .openAI
    @Published var selectedCategory: Category = .detailedAnswer
    @Published var sessionState: SessionState = .active
    @Published var isMicrophoneActive: Bool = false
    @Published var microphoneCaptionText: String = ""
    @Published var isChromeSoundActive: Bool = false
    @Published var isScreenShareHidden: Bool = true
    @Published var showSettings: Bool = false
    
    private let speechRecognitionService = SpeechRecognitionService()
    private let chromeCaptureManager = ChromeAudioCaptureManager()
    private var onSpeechRecognized: ((String) -> Void)?
    private var cancellables = Set<AnyCancellable>()

    // Chrome audio → speech recognition
    private var chromeRecognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var chromeRecognitionTask: SFSpeechRecognitionTask?
    private let chromeSpeechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    init() {
        speechRecognitionService.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] isRecording in
                self?.isMicrophoneActive = isRecording
            }
            .store(in: &cancellables)

        speechRecognitionService.$recognizedText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                self?.microphoneCaptionText = text
            }
            .store(in: &cancellables)
    }

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
            speechRecognitionService.stopRecording()
            let finalText = speechRecognitionService.recognizedText
            if !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onSpeechRecognized?(finalText)
            }
            microphoneCaptionText = ""
        } else {
            Task {
                await speechRecognitionService.requestAuthorization()
                guard speechRecognitionService.isAuthorized else {
                    print("Speech recognition not authorized")
                    return
                }
                do {
                    try speechRecognitionService.startRecording()
                } catch SpeechRecognitionError.notAuthorized {
                    print("Speech recognition not authorized")
                } catch {
                    print("Failed to start recording: \(error.localizedDescription)")
                }
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

    // MARK: - Chrome sound capture (ScreenCaptureKit → Speech)

    func toggleChromeSound() {
        if isChromeSoundActive {
            stopChromeSound()
        } else {
            startChromeSound()
        }
    }

    private func startChromeSound() {
        guard chromeSpeechRecognizer != nil else {
            print("Speech recognizer not available")
            return
        }

        Task {
            await speechRecognitionService.requestAuthorization()
            guard speechRecognitionService.isAuthorized else {
                print("Speech recognition not authorized. Grant microphone and speech in System Settings.")
                return
            }
            await startChromeSoundAfterAuthorization()
        }
    }

    private func startChromeSoundAfterAuthorization() async {
        guard speechRecognitionService.isAuthorized else { return }

        await MainActor.run { microphoneCaptionText = "" }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        chromeRecognitionRequest = request

        chromeCaptureManager.onAudioBuffer = { [weak self] buffer in
            guard let self else { return }
            let converted = AudioFormatConversion.toSpeechFormat(buffer)
            guard let converted else { return }
            Task { @MainActor in
                self.chromeRecognitionRequest?.append(converted)
            }
        }

        chromeRecognitionTask = chromeSpeechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    self.microphoneCaptionText = text
                    if result.isFinal {
                        self.finishChromeSound(recognizedText: text)
                    }
                }
            }
            if error != nil {
                Task { @MainActor in
                    self.finishChromeSound(recognizedText: "")
                }
            }
        }

        do {
            try await chromeCaptureManager.start()
            await MainActor.run { self.isChromeSoundActive = true }
        } catch {
            await MainActor.run {
                self.chromeRecognitionTask?.cancel()
                self.chromeRecognitionTask = nil
                self.chromeRecognitionRequest = nil
                self.isChromeSoundActive = false
            }
            print("System audio capture failed: \(error.localizedDescription). Ensure Screen Recording permission is granted in System Settings → Privacy & Security.")
        }
    }

    private func stopChromeSound() {
        chromeRecognitionRequest?.endAudio()
        Task {
            await chromeCaptureManager.stop()
            await MainActor.run {
                chromeCaptureManager.onAudioBuffer = nil
                chromeRecognitionTask = nil
                chromeRecognitionRequest = nil
                isChromeSoundActive = false
                microphoneCaptionText = ""
            }
        }
    }

    private func finishChromeSound(recognizedText: String) {
        chromeRecognitionTask = nil
        chromeRecognitionRequest = nil
        isChromeSoundActive = false
        chromeCaptureManager.onAudioBuffer = nil
        microphoneCaptionText = ""
        Task { await chromeCaptureManager.stop() }
        if !recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onSpeechRecognized?(recognizedText)
        }
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
