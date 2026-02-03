//
//  SpeechRecognitionService.swift
//  musicplayer
//
//  Created by Robin Chauhan on 03/02/26.
//

import Foundation
import Combine
import Speech
import AVFoundation

@MainActor
final class SpeechRecognitionService: NSObject, ObservableObject {
    @Published var recognizedText: String = ""
    @Published var isRecording: Bool = false
    @Published var isAuthorized: Bool = false
    
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    
    override init() {
        super.init()
        requestAuthorization()
    }
    
    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    self?.isAuthorized = true
                case .denied, .restricted, .notDetermined:
                    self?.isAuthorized = false
                    print("Speech recognition not authorized: \(authStatus.rawValue)")
                @unknown default:
                    self?.isAuthorized = false
                }
            }
        }
    }
    
    func startRecording() throws {
        // Cancel any ongoing recognition task
        if let recognitionTask = recognitionTask {
            recognitionTask.cancel()
            self.recognitionTask = nil
        }
        
        // Reset recognized text
        recognizedText = ""
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            throw SpeechRecognitionError.recognitionRequestFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Create audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw SpeechRecognitionError.audioEngineFailed
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        // Start recognition
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            var isFinal = false
            
            if let result = result {
                Task { @MainActor in
                    self.recognizedText = result.bestTranscription.formattedString
                    isFinal = result.isFinal
                }
            }
            
            if error != nil || isFinal {
                Task { @MainActor in
                    audioEngine.stop()
                    inputNode.removeTap(onBus: 0)
                    
                    self.recognitionRequest = nil
                    self.recognitionTask = nil
                }
            }
        }
        
        isRecording = true
    }
    
    func stopRecording() -> String {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        
        isRecording = false
        
        let finalText = recognizedText
        recognizedText = ""
        
        return finalText
    }
    
    func cancelRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        isRecording = false
        recognizedText = ""
    }
}

enum SpeechRecognitionError: Error {
    case recognitionRequestFailed
    case audioEngineFailed
    case notAuthorized
    
    var localizedDescription: String {
        switch self {
        case .recognitionRequestFailed:
            return "Unable to create speech recognition request"
        case .audioEngineFailed:
            return "Unable to create audio engine"
        case .notAuthorized:
            return "Speech recognition not authorized"
        }
    }
}
