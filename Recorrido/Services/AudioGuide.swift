import AVFoundation
import NaturalLanguage
import Observation

/// Reads stop stories aloud with the system voices — an audio guide that
/// works offline in any language the phone has a voice for.
@MainActor
@Observable
final class AudioGuide: NSObject, AVSpeechSynthesizerDelegate {
    /// The id of what is being read, if anything.
    private(set) var speakingID: String?
    private(set) var isPaused = false

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func isSpeaking(_ id: String) -> Bool { speakingID == id && !isPaused }

    /// Starts reading, or pauses/resumes when the same item is already playing.
    func toggle(id: String, text: String, language: String?) {
        if speakingID == id {
            isPaused ? resume() : pause()
        } else {
            speak(id: id, text: text, language: language)
        }
    }

    func speak(id: String, text: String, language: String?) {
        stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(for: language ?? Self.detectLanguage(of: text))
        let rate = AppGroup.defaults.double(forKey: SettingsKey.speechRate)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(rate > 0 ? rate : 1)
        utterance.postUtteranceDelay = 0.2
        speakingID = id
        isPaused = false
        synthesizer.speak(utterance)
    }

    func pause() {
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
    }

    func resume() {
        synthesizer.continueSpeaking()
        isPaused = false
    }

    func stop() {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        finish()
    }

    /// The text read for a stop: its name, story and tip.
    static func script(for stop: Stop) -> String {
        var parts = [stop.title]
        if !stop.details.isEmpty { parts.append(stop.details) }
        if let tip = stop.tip, !tip.isEmpty {
            parts.append(String(localized: "Tip: \(tip)"))
        }
        return parts.joined(separator: ". ")
    }

    static func voice(for language: String) -> AVSpeechSynthesisVoice? {
        let code = String(language.prefix(2))
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(code) }
        return candidates.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: language)
    }

    static func detectLanguage(of text: String) -> String {
        NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue ?? ContentLanguage.current
    }

    private func finish() {
        speakingID = nil
        isPaused = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if !self.synthesizer.isSpeaking { self.finish() }
        }
    }
}
