import AVFoundation
import Foundation
import simd

/// Every sound in the game. Effects are short clips from Resources/Sounds played on a small
/// pool of voices, each with its own pitch and pan; music is one loop per planet that fades
/// from one to the next. All of it was made by Tools/make_sounds.py.
@MainActor
final class Sound {
    static let shared = Sound()

    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var voices: [(player: AVAudioPlayerNode, speed: AVAudioUnitVarispeed)] = []
    private var nextVoice = 0
    /// Repeating sounds, one per channel: "fx" for the laser hum, "engine" for vehicles.
    private var loops: [String: (player: AVAudioPlayerNode, speed: AVAudioUnitVarispeed, name: String?)] = [:]
    private var started = false

    private var music: AVAudioPlayer?
    private var musicName: String?
    private var fadingOut: [AVAudioPlayer] = []

    private static let voiceCount = 22
    /// Music volume for Off, Low, Medium, High.
    static let musicLevels: [Float] = [0, 0.18, 0.32, 0.5]

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    }

    /// Load the clips and start the engine. Safe to call more than once.
    func start() {
        guard !started else { return }
        started = true
        #if !os(macOS)
        // Mix politely with other audio (like a FaceTime call) and respect the silent switch.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        for name in Sound.effectNames {
            guard let url = Sound.url(name, "wav"),
                  let file = try? AVAudioFile(forReading: url),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buffer)) != nil else { continue }
            buffers[name] = buffer
        }

        for _ in 0..<Sound.voiceCount {
            let player = AVAudioPlayerNode()
            let speed = AVAudioUnitVarispeed()
            engine.attach(player)
            engine.attach(speed)
            engine.connect(player, to: speed, format: format)
            engine.connect(speed, to: engine.mainMixerNode, format: format)
            voices.append((player, speed))
        }
        for channel in ["fx", "engine", "glitch"] {
            let player = AVAudioPlayerNode()
            let speed = AVAudioUnitVarispeed()
            engine.attach(player)
            engine.attach(speed)
            engine.connect(player, to: speed, format: format)
            engine.connect(speed, to: engine.mainMixerNode, format: format)
            loops[channel] = (player, speed, nil)
        }

        engine.prepare()
        try? engine.start()
        applyVolumes()
    }

    /// Settings changed.
    func applyVolumes() {
        let settings = GameSettings.shared
        engine.mainMixerNode.outputVolume = settings.soundEffects ? 1 : 0
        music?.setVolume(musicVolume, fadeDuration: 0.3)
    }

    private var musicVolume: Float {
        Sound.musicLevels[min(max(GameSettings.shared.musicLevel, 0), Sound.musicLevels.count - 1)]
    }

    // MARK: Effects

    /// Play a clip. pitch 1 is normal; pan -1 is left, 1 is right.
    func play(_ name: String, volume: Float = 1, pitch: Float = 1, pan: Float = 0) {
        guard started, GameSettings.shared.soundEffects, volume > 0.01, let buffer = buffers[name] else { return }
        if !engine.isRunning { try? engine.start() }
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.player.stop()
        voice.player.volume = min(volume, 1)
        voice.player.pan = max(-1, min(1, pan))
        voice.speed.rate = max(0.25, min(4, pitch))
        voice.player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        voice.player.play()
    }

    /// A little different each time, so repeated sounds don't feel robotic.
    func playVaried(_ name: String, volume: Float = 1, spread: Float = 0.08) {
        play(name, volume: volume, pitch: 1 + Float.random(in: -spread...spread))
    }

    /// A sound from something in the world: quieter further away, panned to its side.
    func play(_ name: String, at point: SIMD3<Float>, listener: SIMD3<Float>, facing yaw: Float, volume: Float = 1, pitch: Float = 1) {
        let offset = point - listener
        let distance = simd_length(offset)
        let loudness = volume * max(0, 1 - distance / 40) * min(1, 6 / max(distance, 1))
        guard loudness > 0.02 else { return }
        // How far to the right it is, from -1 to 1.
        let right = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
        let pan = distance > 0.1 ? simd_dot(offset / distance, right) * 0.8 : 0
        play(name, volume: loudness, pitch: pitch, pan: pan)
    }

    /// A clip that repeats until stopped, like the laser's hum or an engine. One per channel.
    func startLoop(_ name: String, channel: String = "fx", volume: Float = 0.5, pitch: Float = 1) {
        guard started, let loop = loops[channel], loop.name != name, let buffer = buffers[name] else { return }
        loops[channel]?.name = name
        loop.player.stop()
        loop.player.volume = volume
        loop.speed.rate = pitch
        loop.player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        loop.player.play()
    }

    /// Change a playing loop, like an engine revving up.
    func setLoop(channel: String, volume: Float, pitch: Float) {
        guard let loop = loops[channel], loop.name != nil else { return }
        loop.player.volume = volume
        loop.speed.rate = max(0.25, min(4, pitch))
    }

    func stopLoop(channel: String = "fx") {
        guard let loop = loops[channel], loop.name != nil else { return }
        loops[channel]?.name = nil
        loop.player.stop()
    }

    // MARK: Music

    /// Fade to a planet's music, or the title music. Same name: keep playing.
    func playMusic(_ name: String) {
        guard started, name != musicName else { return }
        musicName = name
        if let old = music {
            old.setVolume(0, fadeDuration: 5)
            fadingOut.append(old)
            let finished = old
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 5_300_000_000)
                finished.stop()
                self?.fadingOut.removeAll { $0 === finished }
            }
        }
        guard let url = Sound.url(name, "m4a") ?? Sound.url("music-title", "m4a"),
              let player = try? AVAudioPlayer(contentsOf: url) else {
            music = nil
            return
        }
        player.numberOfLoops = -1
        player.volume = 0
        player.prepareToPlay()
        player.play()
        player.setVolume(musicVolume, fadeDuration: 5)
        music = player
    }

    // MARK: Files

    private static func url(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Sounds")
    }

    static let effectNames = [
        "laser-start", "laser-loop", "blast", "break", "place", "step-1", "step-2", "step-3",
        "jump", "land", "fly-on", "fly-off", "launch", "menu-move", "menu-select", "hotbar",
        "critter-chirp", "critter-boop", "critter-squeak", "critter-click", "befriend",
        "grumble", "poof", "zap-critter", "startle", "hurt", "heart", "knocked-out", "friend-joined",
        "rover-engine", "ship-engine", "horn", "vehicle-in", "vehicle-out", "bump", "bolt", "explode", "hyperspace", "entry",
        "pickup", "craft", "boing", "zoom", "teleport",
        "hammer", "sledge", "flame-loop", "gun-mini", "gun-heavy", "gun-sniper", "gun-rifle", "shotgun",
        "cannon", "rocket", "throw", "gl", "mortar", "bounce", "stick", "beep", "boom-big", "boom-huge", "nuke",
        "whistle", "jet", "bomber", "gunship", "drone", "radio", "blackhole-open", "blackhole-loop", "blackhole-close",
        "robocat-meow", "robocat-hurt", "robocat-down", "robocat-charge", "robocat-laser", "glitch-hum", "cure", "build-tick", "glitch-alarm", "creak", "rubble"
    ]
}
