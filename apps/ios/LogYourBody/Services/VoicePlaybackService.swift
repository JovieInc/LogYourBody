import AVFoundation
import Foundation

@MainActor
final class VoicePlaybackService {
    private let makeSynthesizer: () -> AVSpeechSynthesizer
    private lazy var synthesizer = makeSynthesizer()
    private var player: AVAudioPlayer?

    init(makeSynthesizer: @escaping () -> AVSpeechSynthesizer = { AVSpeechSynthesizer() }) {
        self.makeSynthesizer = makeSynthesizer
    }

    func play(_ audio: Data) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        player = try AVAudioPlayer(data: audio)
        player?.play()
    }

    func speakOffline(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
}
