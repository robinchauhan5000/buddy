//
//  ChromeAudioCaptureManager.swift
//  musicplayer
//
//  Captures system audio (all apps on the display) using ScreenCaptureKit (macOS 13+).
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

    /// Set this to receive system audio buffers (e.g. append to SFSpeechAudioBufferRecognitionRequest).
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)? {
        get { audioOutput.onAudioBuffer }
        set { audioOutput.onAudioBuffer = newValue }
    }

    // MARK: - Public API

    func start() async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            if !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
            }
            throw NSError(
                domain: "SystemAudioCapture",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Screen Recording permission is required. Please enable it in System Settings → Privacy & Security → Screen Recording."]
            )
        }

        guard let display = content.displays.first else {
            if !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
            }
            throw NSError(
                domain: "SystemAudioCapture",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Screen Recording permission is required, or no display is available. Please enable it in System Settings → Privacy & Security → Screen Recording."]
            )
        }

        // Include all applications so we capture system-wide audio (every app on the display), not just one app.
        let filter = SCContentFilter(
            display: display,
            including: content.applications,
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
            sampleHandlerQueue: DispatchQueue(label: "system.audio.queue")
        )
        try await stream.addStreamOutput(
            dummyScreenOutput,
            type: SCStreamOutputType.screen,
            sampleHandlerQueue: DispatchQueue(label: "system.screen.queue")
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
