//
//  ChromeAudioCaptureManager.swift
//  musicplayer
//
//  Captures audio from Google Chrome only using ScreenCaptureKit (macOS 13+).
//  Outputs raw audio buffers for STT, saving to file, or streaming.
//

import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia

@MainActor
final class ChromeAudioCaptureManager {

    private var stream: SCStream?
    private let audioOutput = ChromeAudioStreamOutput()
    private let dummyScreenOutput = ChromeDummyScreenOutput()

    /// Set this to receive Chrome audio buffers (e.g. append to SFSpeechAudioBufferRecognitionRequest).
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)? {
        get { audioOutput.onAudioBuffer }
        set { audioOutput.onAudioBuffer = newValue }
    }

    // MARK: - Public API

    func start() async throws {
        let content = try await SCShareableContent.current

        guard let chromeApp = content.applications.first(where: {
            $0.applicationName == "Google Chrome"
        }) else {
            throw NSError(
                domain: "ChromeNotFound",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Google Chrome is not running"]
            )
        }

        guard let display = content.displays.first else {
            throw NSError(
                domain: "ChromeCapture",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "No display available"]
            )
        }

        let filter = SCContentFilter(
            display: display,
            including: [chromeApp],
            exceptingWindows: []
        )

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        config.excludesCurrentProcessAudio = true
        // Minimal dimensions so ScreenCaptureKit has a screen output; avoids "stream output NOT found. Dropping frame".
        config.width = 64
        config.height = 64

        let stream = SCStream(
            filter: filter,
            configuration: config,
            delegate: nil
        )

        try await stream.addStreamOutput(
            audioOutput,
            type: SCStreamOutputType.audio,
            sampleHandlerQueue: DispatchQueue(label: "chrome.audio.queue")
        )
        try await stream.addStreamOutput(
            dummyScreenOutput,
            type: SCStreamOutputType.screen,
            sampleHandlerQueue: DispatchQueue(label: "chrome.screen.queue")
        )

        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        if let stream = stream {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                stream.stopCapture { _ in
                    continuation.resume()
                }
            }
        }
        stream = nil
    }
}
