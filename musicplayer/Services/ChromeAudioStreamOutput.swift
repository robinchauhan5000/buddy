//
//  ChromeAudioStreamOutput.swift
//  musicplayer
//
//  Captures Chrome audio sample buffers from ScreenCaptureKit and forwards
//  them as AVAudioPCMBuffer for STT or other processing.
//

import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia

final class ChromeAudioStreamOutput: NSObject, SCStreamOutput {

    /// Called on the sample handler queue with each PCM buffer (e.g. to append to speech recognition).
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio else { return }

        guard let pcmBuffer = pcmBuffer(from: sampleBuffer) else {
            return
        }

        onAudioBuffer?(pcmBuffer)
    }

    // MARK: - CMSampleBuffer → AVAudioPCMBuffer

    private func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard
            let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
        else { return nil }

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: asbd.pointee.mSampleRate,
            channels: AVAudioChannelCount(asbd.pointee.mChannelsPerFrame),
            interleaved: false
        )

        guard
            let audioFormat = format,
            let buffer = AVAudioPCMBuffer(
                pcmFormat: audioFormat,
                frameCapacity: AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
            )
        else { return nil }

        buffer.frameLength = buffer.frameCapacity

        CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(buffer.frameLength),
            into: buffer.mutableAudioBufferList
        )

        return buffer
    }
}
