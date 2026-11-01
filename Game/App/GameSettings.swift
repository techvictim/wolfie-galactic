import Foundation
import Observation
import simd

/// Player preferences, remembered between launches.
@MainActor
@Observable
final class GameSettings {
    static let shared = GameSettings()

    static let lookSpeedNames = ["Slow", "Normal", "Fast"]
    static let lookSpeedValues: [Float] = [0.6, 1.0, 1.5]

    /// 0 slow, 1 normal, 2 fast.
    var lookSpeed: Int {
        didSet { UserDefaults.standard.set(lookSpeed, forKey: "lookSpeed") }
    }
    /// Push the stick up to look down, like a plane.
    var invertLook: Bool {
        didSet { UserDefaults.standard.set(invertLook, forKey: "invertLook") }
    }
    /// Say block and planet names aloud.
    var speakNames: Bool {
        didSet { UserDefaults.standard.set(speakNames, forKey: "speakNames") }
    }

    static let viewDistanceNames = ["Near", "Medium", "Far", "Very far"]
    /// Detailed chunks around you, as a radius in chunks of 16 blocks.
    static let detailRadii = [4, 6, 8, 10]
    /// How far the simple far-away land reaches, in blocks.
    static let farDistances = [256, 448, 704, 960]

    /// 0 near … 3 very far. Further looks better but needs a faster device.
    var viewDistance: Int {
        didSet { UserDefaults.standard.set(viewDistance, forKey: "viewDistance") }
    }

    static let musicLevelNames = ["Off", "Low", "Medium", "High"]
    static let dangerNames = ["Off", "Gentle", "Tough"]

    /// Backpack: false collects blocks and uses them up when building; true gives you everything.
    var freeBuild: Bool {
        didSet { UserDefaults.standard.set(freeBuild, forKey: "freeBuild") }
    }

    /// 0: nothing can hurt you. 1: hearts and a few Grumblers. 2: more Grumblers and falls hurt.
    var danger: Int {
        didSet { UserDefaults.standard.set(danger, forKey: "danger") }
    }

    /// Which crew member you play as: an id from Crew.all.
    var crew: String {
        didSet { UserDefaults.standard.set(crew, forKey: "crew") }
    }
    /// See your character from behind (true) or look through their eyes (false).
    var viewBehind: Bool {
        didSet { UserDefaults.standard.set(viewBehind, forKey: "viewBehind") }
    }
    /// Characters talk and laugh.
    var voices: Bool {
        didSet { UserDefaults.standard.set(voices, forKey: "voices") }
    }

    /// 0 off … 3 high.
    var musicLevel: Int {
        didSet { UserDefaults.standard.set(musicLevel, forKey: "musicLevel") }
    }
    var soundEffects: Bool {
        didSet { UserDefaults.standard.set(soundEffects, forKey: "soundEffects") }
    }

    /// Names to pick from for playing together, so nobody has to type.
    static let playerNames = ["Nova", "Comet", "Rocket", "Pixel", "Blaze", "Orbit", "Zippy", "Luna", "Astro", "Bolt", "Echo", "Sparky", "Wolfie", "Cosmo", "Ziggy", "Pluto"]
    static let playerColorNames = ["Teal", "Pink", "Gold", "Violet", "Lime", "Sky", "Orange", "Red"]
    static let playerColors: [SIMD3<Float>] = [
        SIMD3(0.31, 0.82, 0.69), SIMD3(1.0, 0.45, 0.78), SIMD3(1.0, 0.76, 0.25), SIMD3(0.6, 0.42, 1.0),
        SIMD3(0.6, 0.9, 0.3), SIMD3(0.37, 0.75, 1.0), SIMD3(1.0, 0.55, 0.2), SIMD3(0.95, 0.3, 0.3)
    ]

    /// Your name when playing with friends: an index into playerNames.
    var playerName: Int {
        didSet { UserDefaults.standard.set(playerName, forKey: "playerName") }
    }
    /// Your colour when playing with friends: an index into playerColors.
    var playerColor: Int {
        didSet { UserDefaults.standard.set(playerColor, forKey: "playerColor") }
    }
    var playerNameText: String { GameSettings.playerNames[min(max(playerName, 0), GameSettings.playerNames.count - 1)] }

    var detailRadius: Int { GameSettings.detailRadii[min(max(viewDistance, 0), 3)] }
    var farDistance: Int { GameSettings.farDistances[min(max(viewDistance, 0), 3)] }

    var lookMultiplier: Float {
        GameSettings.lookSpeedValues[min(max(lookSpeed, 0), 2)]
    }

    private init() {
        let defaults = UserDefaults.standard
        lookSpeed = defaults.object(forKey: "lookSpeed") as? Int ?? 1
        invertLook = defaults.bool(forKey: "invertLook")
        speakNames = defaults.object(forKey: "speakNames") as? Bool ?? true
        #if os(macOS)
        let defaultView = 2
        #else
        let defaultView = 1
        #endif
        viewDistance = defaults.object(forKey: "viewDistance") as? Int ?? defaultView
        // First launch picks a random name and colour, so friends' devices start out different.
        musicLevel = defaults.object(forKey: "musicLevel") as? Int ?? 2
        danger = defaults.object(forKey: "danger") as? Int ?? 1
        freeBuild = defaults.bool(forKey: "freeBuild")
        soundEffects = defaults.object(forKey: "soundEffects") as? Bool ?? true
        crew = defaults.string(forKey: "crew") ?? "wolfie"
        viewBehind = defaults.object(forKey: "viewBehind") as? Bool ?? true
        voices = defaults.object(forKey: "voices") as? Bool ?? true
        let name = defaults.object(forKey: "playerName") as? Int ?? Int.random(in: 0..<GameSettings.playerNames.count)
        let color = defaults.object(forKey: "playerColor") as? Int ?? Int.random(in: 0..<GameSettings.playerColors.count)
        defaults.set(name, forKey: "playerName")
        defaults.set(color, forKey: "playerColor")
        playerName = name
        playerColor = color
    }
}
