import Foundation

/// A kind of critter, from Resources/critters.json. Its model is Resources/<id>.vox and its
/// picture for the critter book is Resources/critter-<id>.png (both from Tools/make_critters.py).
struct CritterKind: Codable, Identifiable, Sendable {
    enum Move: String, Codable, Sendable {
        /// Walks with a side-to-side wobble.
        case waddle
        /// Bounces along in hops.
        case hop
        /// Floats above the ground.
        case hover
        /// Walks sideways, like a crab.
        case scuttle
    }

    let id: String
    let name: String
    /// Planet ids where it lives.
    let planets: [String]
    let move: Move
    /// Walking speed in blocks per second.
    let speed: Float
    /// The clip it makes now and then.
    let sound: String
    /// How many wander around you at once.
    let count: Int
    let fact: String
    /// Grumpy critters chase you and only come out when Danger is on.
    let grumpy: Bool?

    var isGrumpy: Bool { grumpy ?? false }
}

@MainActor
final class CritterCatalog {
    static let shared = CritterCatalog()
    let kinds: [CritterKind]

    private struct File: Codable {
        let critters: [CritterKind]
    }

    private init() {
        if let url = Bundle.main.url(forResource: "critters", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let file = try? JSONDecoder().decode(File.self, from: data) {
            kinds = file.critters
        } else {
            kinds = []
        }
    }

    func kind(id: String) -> CritterKind? {
        kinds.first { $0.id == id }
    }

    /// The friendly critters that live on a planet.
    func friendly(on planet: String) -> [CritterKind] {
        kinds.filter { !$0.isGrumpy && $0.planets.contains(planet) }
    }

    func grumpy(on planet: String) -> [CritterKind] {
        kinds.filter { $0.isGrumpy && $0.planets.contains(planet) }
    }
}
