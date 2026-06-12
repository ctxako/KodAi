//
//  SpeechService.swift
//  kodAI_chatbot_dev
//
//  Created by Charles Thomas Xavier Austin III on 6/8/26.
//
import Foundation
import AVFoundation

@MainActor
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechService()

    private let synthesizer = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isSpeaking: Bool {
        synthesizer.isSpeaking
    }

    func speak(_ text: String) {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else {
            print("[SpeechService] No text to speak")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()

            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers]
            )

            try session.setActive(true)
        } catch {
            print("[SpeechService] Audio session error:", error)
        }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.enhanced.en-US.Ava")
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.42
        utterance.volume = 1.0
        utterance.pitchMultiplier = 0.95

        print("[SpeechService] Speaking:", cleaned.prefix(80))

        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)

        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("[SpeechService] Failed to deactivate audio session:", error)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            do {
                try AVAudioSession.sharedInstance().setActive(false)
            } catch {
                print("[SpeechService] Failed to deactivate after finish:", error)
            }
        }
    }
}
