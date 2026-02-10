//
//  AudioFormatConversion.swift
//  musicplayer
//
//  Converts Chrome capture audio (e.g. 48kHz stereo) to 16kHz mono
//  for SFSpeechAudioBufferRecognitionRequest.
//

import AVFoundation

enum AudioFormatConversion {

    /// Target format for speech recognition (16kHz mono float).
    static let speechFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    /// Converts an arbitrary PCM buffer to 16kHz mono float for speech recognition.
    /// Returns nil if conversion fails.
    static func toSpeechFormat(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let inputFormat = buffer.format as AVAudioFormat?,
              let targetFormat = speechFormat as AVAudioFormat?,
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        else { return nil }

        let inputFrameCapacity = buffer.frameLength
        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(inputFrameCapacity) * ratio) + 1

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCapacity
        ) else { return nil }

        var error: NSError?
        var provided = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if !provided {
                provided = true
                outStatus.pointee = .haveData
                return buffer
            }
            outStatus.pointee = .noDataNow
            return nil
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            return nil
        }
        return outputBuffer
    }
}
