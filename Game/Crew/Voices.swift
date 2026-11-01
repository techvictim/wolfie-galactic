import AVFoundation
import Foundation

/// The crew's voices, the same clips as Wolfie Military (Resources/Voices/<who>_<kind>_<n>.mp3).
///
/// Kinds used so far: pick, laugh, hurt, down (lots of blocks blasted), blast (a big boom),
/// ride (getting in a vehicle), chute (launched high), hi (a friend), up (nice work).
/// Rules from Wolfie Military: a character never talks over itself, each kind has a cooldown,
/// and some only play part of the time.
@MainActor
final class Voices {
    static let shared = Voices()

    private var player: AVAudioPlayer?
    private var lastPlayed: [String: Date] = [:]
    private var clips: [String: [URL]] = [:]

    private init() {}

    /// Say a line of this kind as your crew member (or someone else's).
    /// - chance: how often it plays at all (1 is always).
    /// - cooldown: seconds before this kind can play again.
    func say(_ kind: String, as who: String? = nil, chance: Double = 1, cooldown: TimeInterval = 4, volume: Float = 1, interrupt: Bool = false) {
        let settings = GameSettings.shared
        guard settings.voices, settings.soundEffects else { return }
        let id = who ?? settings.crew
        let key = "\(id)_\(kind)"
        if let last = lastPlayed[key], Date().timeIntervalSince(last) < cooldown { return }
        if let player, player.isPlaying, !interrupt { return }
        guard Double.random(in: 0..<1) < chance else { return }
        guard let url = urls(key).randomElement(), let next = try? AVAudioPlayer(contentsOf: url) else { return }
        player?.stop()
        lastPlayed[key] = Date()
        next.volume = volume
        next.prepareToPlay()
        next.play()
        player = next
    }

    func has(_ kind: String, as who: String) -> Bool {
        !urls("\(who)_\(kind)").isEmpty
    }

    private func urls(_ key: String) -> [URL] {
        if let found = clips[key] { return found }
        var found: [URL] = []
        for n in 0..<8 {
            let name = "\(key)_\(n)"
            guard let url = Bundle.main.url(forResource: name, withExtension: "mp3")
                    ?? Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "Voices") else { continue }
            found.append(url)
        }
        clips[key] = found
        return found
    }
}
