import Foundation

/// One weapon from Resources/weapons.json. Everything but the name and type has a sensible default,
/// so a new weapon only needs the numbers that make it different.
struct WeaponDef: Decodable, Sendable, Identifiable {
    enum Kind: String, Decodable, Sendable {
        case melee, flame, gun, projectile, sticky, mine, strike, blackhole
    }

    let id: String
    let name: String
    let group: String
    let about: String
    let type: Kind
    let cooldown: Float
    /// Keep firing while the trigger is held.
    let hold: Bool
    let range: Float
    let radius: Float
    let speed: Float
    let gravity: Float
    let pierce: Int
    let spread: Float
    let pellets: Int
    let fuse: Float
    let bounce: Bool
    let drill: Int
    let lob: Float
    let count: Int
    let remote: Bool
    let zoom: Float
    let size: Float
    let recharge: Float
    let duration: Float
    let style: String
    let look: String
    let hand: String
    let sound: String
    /// The colour of its energy bolts.
    let color: SIMD3<Float>

    private enum CodingKeys: String, CodingKey {
        case id, name, group, about, type, cooldown, hold, range, radius, speed, gravity, pierce, spread, pellets
        case fuse, bounce, drill, lob, count, remote, zoom, size, recharge, duration, style, look, hand, sound, color
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(Kind.self, forKey: .type)
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? "Weapons"
        about = try c.decodeIfPresent(String.self, forKey: .about) ?? ""
        cooldown = try c.decodeIfPresent(Float.self, forKey: .cooldown) ?? 0.5
        hold = try c.decodeIfPresent(Bool.self, forKey: .hold) ?? false
        range = try c.decodeIfPresent(Float.self, forKey: .range) ?? 60
        radius = try c.decodeIfPresent(Float.self, forKey: .radius) ?? 2.5
        speed = try c.decodeIfPresent(Float.self, forKey: .speed) ?? 40
        gravity = try c.decodeIfPresent(Float.self, forKey: .gravity) ?? 0
        pierce = try c.decodeIfPresent(Int.self, forKey: .pierce) ?? 0
        spread = try c.decodeIfPresent(Float.self, forKey: .spread) ?? 0
        pellets = try c.decodeIfPresent(Int.self, forKey: .pellets) ?? 1
        fuse = try c.decodeIfPresent(Float.self, forKey: .fuse) ?? 0
        bounce = try c.decodeIfPresent(Bool.self, forKey: .bounce) ?? false
        drill = try c.decodeIfPresent(Int.self, forKey: .drill) ?? 0
        lob = try c.decodeIfPresent(Float.self, forKey: .lob) ?? 0
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 1
        remote = try c.decodeIfPresent(Bool.self, forKey: .remote) ?? false
        zoom = try c.decodeIfPresent(Float.self, forKey: .zoom) ?? 1
        size = try c.decodeIfPresent(Float.self, forKey: .size) ?? 1
        recharge = try c.decodeIfPresent(Float.self, forKey: .recharge) ?? 0
        duration = try c.decodeIfPresent(Float.self, forKey: .duration) ?? 5
        style = try c.decodeIfPresent(String.self, forKey: .style) ?? ""
        look = try c.decodeIfPresent(String.self, forKey: .look) ?? "ball"
        hand = try c.decodeIfPresent(String.self, forKey: .hand) ?? "gun"
        sound = try c.decodeIfPresent(String.self, forKey: .sound) ?? ""
        color = BlockRegistry.parseHex(try c.decodeIfPresent(String.self, forKey: .color) ?? "#5ff0ff")
    }

    /// Your character points it where you look.
    var aimed: Bool { hand == "gun" || hand == "launcher" || hand == "alien" }
}

/// Every weapon, in the order the backpack shows them.
final class Arsenal: Sendable {
    static let shared = Arsenal()

    let weapons: [WeaponDef]
    private let byID: [String: WeaponDef]

    private struct File: Decodable {
        let weapons: [Failable]
    }

    /// One broken entry shouldn't lose the whole arsenal.
    private struct Failable: Decodable {
        let def: WeaponDef?
        init(from decoder: Decoder) throws {
            def = try? WeaponDef(from: decoder)
        }
    }

    private init() {
        var loaded: [WeaponDef] = []
        if let url = Bundle.main.url(forResource: "weapons", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let file = try? JSONDecoder().decode(File.self, from: data) {
            loaded = file.weapons.compactMap(\.def)
        }
        weapons = loaded
        byID = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func weapon(_ id: String) -> WeaponDef? {
        byID[id]
    }
}
