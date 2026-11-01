import Foundation
import simd

/// What the Red Glitch is up to: which nests are cured on each planet, robo-cats each nest still
/// has inside, and the timers for spreading, checking and glowing.
@MainActor
final class GlitchState {
    /// Cured nests, by planet. Saved, so they stay cured.
    private var cured: [String: Set<String>] = [:]
    /// How many Glitch blocks each nest started with, by "planet/id".
    var totals: [String: Int] = [:]
    /// Robo-cats left inside each nest, by "planet/id". A knocked-out cat doesn't come back.
    var catsLeft: [String: Int] = [:]
    /// Nests near you, refreshed every couple of seconds.
    var nearby: [(site: Settlement, nest: GlitchNest)] = []
    var nearbyFrom = SIMD2<Float>(1e9, 1e9)
    var refreshTimer: Float = 0
    var checkTimer: Float = 0
    var lastRevision = -1
    var spawnTimer: Float = 4
    var spreadTimer: Float = 180
    var sparkTimer: Float = 0
    var glowClock: Float = 0
    var glowTimer: Float = 0
    var humming = false
    /// Nests the builder bots are working on right now.
    var rebuilding: Set<String> = []

    func isCured(_ id: String, on planet: String) -> Bool {
        load(planet).contains(id)
    }

    func setCured(_ id: String, on planet: String, _ value: Bool) {
        var set = load(planet)
        if value { set.insert(id) } else { set.remove(id) }
        cured[planet] = set
        UserDefaults.standard.set(Array(set).sorted(), forKey: "curedNests-\(planet)")
    }

    func curedCount(on planet: String) -> Int {
        load(planet).count
    }

    /// Start a planet over: every nest comes back.
    func reset(planet: String) {
        cured[planet] = []
        UserDefaults.standard.removeObject(forKey: "curedNests-\(planet)")
        for key in Array(catsLeft.keys) where key.hasPrefix(planet + "/") { catsLeft[key] = nil }
    }

    func forgetNearby() {
        nearby = []
        nearbyFrom = SIMD2(1e9, 1e9)
        refreshTimer = 0
        rebuilding.removeAll()
    }

    private func load(_ planet: String) -> Set<String> {
        if let set = cured[planet] { return set }
        let set = Set(UserDefaults.standard.stringArray(forKey: "curedNests-\(planet)") ?? [])
        cured[planet] = set
        return set
    }

    /// Total nests cured, everywhere (for the scoreboard).
    var totalCured: Int {
        get { UserDefaults.standard.integer(forKey: "nestsCuredTotal") }
        set { UserDefaults.standard.set(newValue, forKey: "nestsCuredTotal") }
    }

    /// Robo-cats knocked out, ever.
    var catsKnockedOut: Int {
        get { UserDefaults.standard.integer(forKey: "catsKnockedOut") }
        set { UserDefaults.standard.set(newValue, forKey: "catsKnockedOut") }
    }
}
