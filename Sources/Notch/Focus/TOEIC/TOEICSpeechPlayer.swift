import AppKit
import AVFoundation
import Combine

/// Speaks English TOEIC headwords with system TTS (en-US).
@MainActor
final class TOEICSpeechPlayer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = TOEICSpeechPlayer()

    @Published private(set) var isSpeaking = false
    @Published private(set) var lastSpokenWord: String?

    private let synthesizer = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ word: String) {
        let text = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = preferredEnglishVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.88
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0

        lastSpokenWord = text
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    private func preferredEnglishVoice() -> AVSpeechSynthesisVoice? {
        let preferredIDs = [
            "com.apple.voice.compact.en-US.Samantha",
            "com.apple.eloquence.en-US.Reed",
            "com.apple.voice.compact.en-GB.Daniel",
        ]
        for id in preferredIDs {
            if let voice = AVSpeechSynthesisVoice(identifier: id) {
                return voice
            }
        }
        return AVSpeechSynthesisVoice(language: "en-US")
            ?? AVSpeechSynthesisVoice(language: "en-GB")
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
}
