import Foundation
import simd

/// A planet or moon you can fly to. Defined in Resources/planets.json.
struct Planet: Codable, Identifiable, Sendable {
    struct Terrain: Codable, Sendable {
        /// Lowest typical ground height, in blocks.
        let base: Int
        /// How tall the hills get, in blocks.
        let amplitude: Float
        /// How wide the hills are: smaller numbers make wider hills.
        let frequency: Float
        let surface: UInt8
        let under: UInt8
        let stone: UInt8
        /// Block used for low ground (shores, frozen pools); 0 to skip.
        let low: UInt8
        let lowLevel: Int
        /// Alien tree blocks; 0 for none.
        let trunk: UInt8
        let leaves: UInt8
    }

    struct Features: Codable, Sendable {
        /// Chance per column, 0...1.
        let trees: Float
        let crystals: Float
        let crates: Float
        /// Chance per 24-block area of a crater.
        let craters: Float
        /// "city", "base" or "mine": what people have built here.
        let settlement: String?
        /// Chance per 200-block area of one more settlement.
        let settlementChance: Float?
    }

    /// A vehicle parked on the planet when you first arrive.
    struct VehicleSpot: Codable, Sendable {
        /// A VehicleKind: "rover", "buggy", "hoverbike", "comet", …
        let kind: String
        /// "pad" (the landing pad), "start" or "settlement" (the first city or base).
        let near: String
        let dx: Int
        let dz: Int
        /// Which way it faces, in radians.
        let yaw: Float?
    }

    struct SkyBody: Codable, Sendable {
        let color: String
        let size: Float
        let direction: [Float]
        /// A planet's own voxel model (space-<id>), so it looks like itself instead of a flat circle.
        var model: String?
    }

    let id: String
    let name: String
    let kind: String
    let seed: UInt64
    /// Wolfie World is 26; the moon is much lower, so jumps go high.
    let gravity: Float
    let sky: String
    let stars: Bool
    let mapColors: [String]
    let terrain: Terrain
    let features: Features
    let skyBodies: [SkyBody]
    let vehicles: [VehicleSpot]?
}

struct PlanetFile: Codable {
    let home: String
    let planets: [Planet]
}

final class PlanetCatalog {
    static let shared = PlanetCatalog()

    let planets: [Planet]
    let homeID: String

    private init() {
        if let url = Bundle.main.url(forResource: "planets", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let file = try? JSONDecoder().decode(PlanetFile.self, from: data),
           !file.planets.isEmpty {
            planets = file.planets
            homeID = file.home
        } else {
            let fallback = Planet(
                id: "wolfie-world", name: "Wolfie World", kind: "Home planet", seed: 20_261_028,
                gravity: 26, sky: "#c4b6ff", stars: false, mapColors: ["#4fd1b0", "#8a5cff"],
                terrain: .init(base: 13, amplitude: 20, frequency: 0.035, surface: 13, under: 14, stone: 15,
                               low: 21, lowLevel: 15, trunk: 16, leaves: 17),
                features: .init(trees: 0.014, crystals: 0.004, crates: 0.002, craters: 0, settlement: "city", settlementChance: 0.4),
                skyBodies: [],
                vehicles: nil
            )
            planets = [fallback]
            homeID = fallback.id
        }
    }

    var home: Planet {
        planet(id: homeID) ?? planets[0]
    }

    func planet(id: String) -> Planet? {
        planets.first { $0.id == id }
    }

    func index(of id: String) -> Int {
        planets.firstIndex { $0.id == id } ?? 0
    }
}
