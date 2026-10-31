import Foundation

/// Playing together on the same Wi-Fi. One device hosts: its world is the real one.
/// Friends join, get a copy of the world, and from then on everyone sends where they are
/// and which blocks they change; the host passes it on to the others.
enum Net {
    /// Bonjour name the host advertises. Also listed in Info.plist (NSBonjourServices).
    static let serviceType = "_wolfiegalactic._tcp"
    /// Bump when messages change, so old and new versions don't try to play together.
    static let version = 2
    /// How often each player sends where they are.
    static let poseInterval: Float = 1.0 / 15
    /// The host's player id. Friends get 1, 2, 3…
    static let hostID = 0
}

/// Who someone is.
struct PlayerCard: Codable, Hashable, Sendable {
    let id: Int
    let name: String
    let color: Int
}

/// Where someone is and what they're doing.
struct Pose: Codable, Sendable, Equatable {
    var x: Float
    var y: Float
    var z: Float
    var yaw: Float
    var pitch: Float
    var flying: Bool
    /// Where their laser beam ends, while they're firing.
    var laser: [Float]?
    /// "rover" or "starship" while driving or flying one.
    var vehicle: String?
    /// True while out in space, where friends on the ground can't see you.
    var space: Bool?
    /// The planet you're on (or orbiting, while in space).
    var planet: String?

    var position: SIMD3<Float> { SIMD3(x, y, z) }
    var laserEnd: SIMD3<Float>? {
        guard let laser, laser.count == 3 else { return nil }
        return SIMD3(laser[0], laser[1], laser[2])
    }
}

/// Where a vehicle is, and who's driving it. Each vehicle exists once per planet.
struct VehicleNote: Codable, Sendable, Equatable {
    let planet: String
    let kind: String
    var x: Float
    var y: Float
    var z: Float
    var yaw: Float
    /// Who's in it right now; nil when parked.
    var driver: Int?
    /// Flown off into space: not on this planet any more.
    var gone: Bool
}

enum NetMessage: Codable, Sendable {
    /// Friend → host, first thing after connecting.
    case hello(version: Int, name: String, color: Int)
    /// Host → friend: your id, the host's planet with every changed chunk and vehicle, and who's here.
    case welcome(you: Int, planet: String, edits: [String: Data], vehicles: [VehicleNote], players: [PlayerCard])
    /// Host → friend: you can't join, and why.
    case refused(reason: String)
    case joined(PlayerCard)
    case left(id: Int)
    case pose(id: Int, pose: Pose)
    /// A block changed on a planet.
    case block(planet: String, x: Int, y: Int, z: Int, id: UInt8)
    /// Friend → host: I'm going to this planet; please send it.
    case askPlanet(planet: String)
    /// Host → friend: a planet's changed chunks and vehicles.
    case planetData(planet: String, edits: [String: Data], vehicles: [VehicleNote])
    /// Someone got into, out of, or flew off in a vehicle.
    case vehicle(VehicleNote)
}
