import AVFoundation

/// Says item names aloud, so a new reader can pick blocks by picture and sound.
@MainActor
final class Speaker {
    static let shared = Speaker()
    private let synthesizer = AVSpeechSynthesizer()

    func say(_ text: String) {
        guard GameSettings.shared.speakNames else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.45
        utterance.pitchMultiplier = 1.1
        synthesizer.speak(utterance)
    }
}
