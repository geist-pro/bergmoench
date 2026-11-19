// Copyright: Kartei contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import AVFoundation
import Foundation

/// Plays a card's [sound:] files and TTS tags in order. Abstract so sessions can be tested without sound.
protocol CardAudioOutput: AnyObject {
    /// Called on the main thread when playback starts or ends.
    var onPlayingChange: ((Bool) -> Void)? { get set }
    func play(_ tags: [Anki_CardRendering_AVTag])
    func stop()
}

/// AVAudioPlayer for files from the collection's media folder, AVSpeechSynthesizer for TTS.
final class CardAudioPlayer: NSObject, CardAudioOutput, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    var onPlayingChange: ((Bool) -> Void)?
    private let mediaFolder: URL?
    private var queue: [Anki_CardRendering_AVTag] = []
    private var player: AVAudioPlayer?
    private let speech = AVSpeechSynthesizer()
    private var playing = false
    private var utterance: AVSpeechUtterance?

    init(mediaFolder: URL?) {
        self.mediaFolder = mediaFolder
        super.init()
        speech.delegate = self
    }

    func play(_ tags: [Anki_CardRendering_AVTag]) {
        stop()
        guard !tags.isEmpty else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        queue = tags
        setPlaying(true)
        next()
    }

    func stop() {
        queue = []
        player?.stop()
        player = nil
        utterance = nil
        if speech.isSpeaking { speech.stopSpeaking(at: .immediate) }
        setPlaying(false)
    }

    private func setPlaying(_ value: Bool) {
        guard playing != value else { return }
        playing = value
        onPlayingChange?(value)
    }

    private func next() {
        guard !queue.isEmpty else { setPlaying(false); return }
        let tag = queue.removeFirst()
        switch tag.value {
        case .soundOrVideo(let name):
            guard let url = mediaFolder?.appendingPathComponent(name), let p = try? AVAudioPlayer(contentsOf: url) else { next(); return }
            p.delegate = self
            player = p
            if !p.play() { next() }
        case .tts(let t):
            let text = t.fieldText.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { next(); return }
            let u = AVSpeechUtterance(string: text)
            u.voice = Self.voice(for: t)
            if t.speed > 0 {
                u.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * t.speed))
            }
            utterance = u
            speech.speak(u)
        case nil:
            next()
        }
    }

    /// Anki's lang is "en_US"; a named voice in the tag wins when this device has it.
    static func voice(for tag: Anki_CardRendering_TTSTag) -> AVSpeechSynthesisVoice? {
        for name in tag.voices {
            if let v = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.name == name || $0.identifier == name }) { return v }
        }
        return AVSpeechSynthesisVoice(language: bcp47(tag.lang))
    }

    static func bcp47(_ lang: String) -> String { lang.replacingOccurrences(of: "_", with: "-") }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { if player === self.player { self.next() } }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async { if player === self.player { self.next() } }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { if utterance === self.utterance { self.utterance = nil; self.next() } }
    }
}
