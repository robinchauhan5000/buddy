import AVFoundation
import Combine
import Speech

enum SpeechRecognitionError: Error {
    case notAuthorized
}

@MainActor
final class SpeechRecognitionService: ObservableObject {

    @Published private(set) var recognizedText = ""
    @Published private(set) var isRecording = false
    @Published private(set) var isAuthorized = false

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    init() {
        // Authorization is requested on first use (when user taps mic), not at launch,
        // to avoid HAL/Core Audio console noise (task name port, AddInstanceForFactory).
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        let micGranted: Bool
        #if os(iOS)
        micGranted = AVAudioSession.sharedInstance().recordPermission == .granted
        #elseif os(macOS)
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            micGranted = true
        case .notDetermined:
            micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        default:
            micGranted = false
        }
        #else
        micGranted = false
        #endif
        isAuthorized = (speechStatus == .authorized && micGranted)
    }

    // MARK: - Recording

    func startRecording() throws {
        guard isAuthorized else {
            throw SpeechRecognitionError.notAuthorized
        }

        cleanup()

        recognizedText = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                self.recognizedText = result.bestTranscription.formattedString
            }

            if result?.isFinal == true || error != nil {
                self.stopInternal()
            }
        }

        isRecording = true
    }

    func stopRecording() {
        stopInternal()
    }

    func cancelRecording() {
        recognitionTask?.cancel()
        stopInternal(clearText: true)
    }

    // MARK: - Cleanup

    private func stopInternal(clearText: Bool = false) {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false

        if clearText {
            recognizedText = ""
        }
    }

    private func cleanup() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }
}
