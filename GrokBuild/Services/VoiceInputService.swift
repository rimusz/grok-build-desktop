import Foundation
import Speech
import AVFoundation
import Observation

@Observable
@MainActor
final class VoiceInputService {
    enum State: Equatable {
        case idle
        case listening
        case transcribing
        case unavailable(String)
    }

    private(set) var state: State = .idle
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    func start(onPartial: @escaping (String) -> Void, onFinal: @escaping (String) -> Void) {
        guard state == .idle else { return }
        guard let recognizer, recognizer.isAvailable else {
            state = .unavailable("Speech recognition unavailable")
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard status == .authorized else {
                    self?.state = .unavailable("Speech permission denied")
                    return
                }
                self?.beginRecognition(onPartial: onPartial, onFinal: onFinal)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        if state == .listening || state == .transcribing {
            state = .idle
        }
    }

    private func beginRecognition(onPartial: @escaping (String) -> Void, onFinal: @escaping (String) -> Void) {
        stop()
        state = .listening

        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            state = .unavailable(error.localizedDescription)
            return
        }

        task = recognizer?.recognitionTask(with: request!) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.state = .transcribing
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        onFinal(text)
                        self.stop()
                    } else {
                        onPartial(text)
                    }
                } else if error != nil {
                    self.stop()
                }
            }
        }
    }
}
