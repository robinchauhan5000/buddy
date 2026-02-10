//
//  ChromeDummyScreenOutput.swift
//  musicplayer
//
//  No-op SCStreamOutput for screen type. ScreenCaptureKit requires a screen
//  output to be registered or it drops frames and logs "stream output NOT found".
//  We only need audio; this handler discards video frames.
//

import Foundation
import ScreenCaptureKit
import CoreMedia

final class ChromeDummyScreenOutput: NSObject, SCStreamOutput {

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        // Discard screen frames; we only consume audio in ChromeAudioStreamOutput.
        guard type == .screen else { return }
    }
}
