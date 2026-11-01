import Foundation
import simd

enum VehicleKind: String, Codable, Sendable, CaseIterable {
    case rover, starship, comet, hauler, zoomer, buggy, hoverbike

    /// Flies (and can go to space), rather than drives.
    var isShip: Bool {
        switch self {
        case .rover, .buggy, .hoverbike: return false
        default: return true
        }
    }

    /// Floats over the ground instead of rolling on wheels.
    var hovers: Bool { self == .hoverbike }

    /// The engine sound it makes.
    var engineSound: String { self == .rover || self == .buggy ? "rover-engine" : "ship-engine" }

    var name: String {
        switch self {
        case .rover: return "rover"
        case .starship: return "starship"
        case .comet: return "Comet"
        case .hauler: return "Hauler"
        case .zoomer: return "Zoomer"
        case .buggy: return "moon buggy"
        case .hoverbike: return "hover bike"
        }
    }

    /// Resources/<modelName>.vox
    var modelName: String {
        switch self {
        case .rover, .starship, .buggy, .hoverbike: return rawValue
        default: return "ship-\(rawValue)"
        }
    }

    /// Detail models face +x (rover) or +z (ships); the game's forward is -z.
    var modelTurn: simd_quatf {
        !isShip
            ? simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 1, 0))
            : simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
    }

    /// How close you need to be to get in, in blocks.
    var boardingDistance: Float {
        switch self {
        case .rover, .buggy, .hoverbike: return 4
        case .starship, .hauler: return 7
        case .comet, .zoomer: return 5
        }
    }

    /// Top speed in blocks per second (doubled out in space).
    var topSpeed: Float {
        switch self {
        case .rover: return 13
        case .buggy: return 12
        case .hoverbike: return 20
        case .starship: return 34
        case .comet: return 44
        case .hauler: return 26
        case .zoomer: return 56
        }
    }

    var climbRate: Float {
        switch self {
        case .hauler: return 10
        case .zoomer: return 18
        default: return 14
        }
    }

    /// Where the chase camera sits: distance behind and height above.
    var cameraDistance: Float {
        switch self {
        case .rover, .buggy: return 8.5
        case .hoverbike: return 7
        case .starship: return 15
        case .hauler: return 16
        case .comet: return 11
        case .zoomer: return 8
        }
    }
    var cameraHeight: Float { isShip ? cameraDistance * 0.37 : 3.6 }
    /// Point the camera looks at, above the vehicle's base.
    var lookHeight: Float {
        switch self {
        case .rover, .buggy: return 1.8
        case .hoverbike: return 1.5
        case .starship: return 3.2
        case .hauler: return 2.4
        case .comet: return 1.4
        case .zoomer: return 1.1
        }
    }

    /// Where its blaster fires from, relative to its base, in its own axes (x right, y up, -z forward).
    var muzzle: SIMD3<Float> {
        switch self {
        case .rover: return SIMD3(0.4, 2.6, -1.0)
        case .buggy: return SIMD3(0, 2.2, -1.6)
        case .hoverbike: return SIMD3(0, 1.4, -1.9)
        case .starship: return SIMD3(0, 2.9, -4.8)
        case .comet: return SIMD3(0, 1.2, -2.9)
        case .hauler: return SIMD3(0, 2.0, -4.8)
        case .zoomer: return SIMD3(0, 1.0, -2.2)
        }
    }

    /// Half the distance between its two side blasters.
    var gunSpread: Float {
        switch self {
        case .starship: return 2.2
        case .hauler: return 2.6
        case .comet: return 1.6
        case .zoomer: return 1.1
        case .rover, .buggy, .hoverbike: return 0
        }
    }
}

/// A rover or starship you can get into. Position is the bottom centre of the model.
struct Vehicle {
    let kind: VehicleKind
    /// Which one this is. A planet's own vehicles use their kind ("rover"); ones you place or
    /// swap for get their own ("rover-3fa2").
    let id: String
    var position: SIMD3<Float>
    var yaw: Float
    var pitch: Float = 0
    var roll: Float = 0
    /// Forward speed, blocks per second (negative is reversing).
    var speed: Float = 0
    var climb: Float = 0
    var onGround = true

    static let roverTopSpeed: Float = 13
    static let roverReverse: Float = 6
    /// The starship can't go higher than this.
    static let shipCeiling: Float = 160

    init(kind: VehicleKind, position: SIMD3<Float>, yaw: Float, id: String? = nil) {
        self.kind = kind
        self.id = id ?? kind.rawValue
        self.position = position
        self.yaw = yaw
    }

    /// A new id for another one of a kind.
    static func newID(_ kind: VehicleKind) -> String {
        "\(kind.rawValue)-\(String(UInt16.random(in: 0...UInt16.max), radix: 16))"
    }

    /// The kind of vehicle an id belongs to.
    static func kind(ofID id: String) -> VehicleKind? {
        VehicleKind(rawValue: String(id.split(separator: "-").first ?? ""))
    }

    var forward: SIMD3<Float> { SIMD3<Float>(-sin(yaw), 0, -cos(yaw)) }
    var right: SIMD3<Float> { SIMD3<Float>(cos(yaw), 0, -sin(yaw)) }

    /// Its full turn and tilt, for the model.
    var orientation: simd_quatf {
        let turn = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        let tip = simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
        let lean = simd_quatf(angle: roll, axis: SIMD3<Float>(0, 0, 1))
        return turn * tip * lean * kind.modelTurn
    }

    /// A point on the vehicle, given in its own axes.
    func point(_ local: SIMD3<Float>) -> SIMD3<Float> {
        position + (simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0)) * simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))).act(local)
    }

    private static func ground(_ world: World, _ p: SIMD3<Float>) -> Float {
        Float(world.surfaceY(x: Int(floor(p.x)), z: Int(floor(p.z))))
    }

    // MARK: Rover

    /// Returns true if it bumped into something too tall to climb.
    @discardableResult
    mutating func drive(dt: Float, throttle: Float, steer: Float, hop: Bool, world: World, gravity: Float) -> Bool {
        // Speed up, coast and brake.
        if throttle != 0 {
            let braking = (throttle > 0 && speed < 0) || (throttle < 0 && speed > 0)
            speed += throttle * (braking ? 26 : 11) * dt
        } else {
            speed -= speed * min(1, dt * 1.6)
            if abs(speed) < 0.05 { speed = 0 }
        }
        speed = min(max(speed, -Vehicle.roverReverse), kind.topSpeed)

        // Steer more when moving, and the other way when reversing, like a real car.
        let grip = min(1, abs(speed) / 4) * (speed < 0 ? -1 : 1)
        yaw -= steer * 1.9 * grip * dt

        // Move, unless a wheel would hit a wall more than a block and a bit tall.
        var bumped = false
        let next = position + forward * speed * dt
        let wheels = Vehicle.wheelOffsets.map { next + forward * $0.y + right * $0.x }
        let heights = wheels.map { Vehicle.ground(world, $0) }
        let lift: Float = kind.hovers ? 0.9 : 0
        let highest = (heights.max() ?? position.y) + lift
        if highest - position.y > (kind.hovers ? 2.6 : 1.3) && onGround {
            bumped = abs(speed) > 2
            speed = -speed * 0.25
        } else {
            position.x = next.x
            position.z = next.z
        }

        // Settle on the wheels: tilt to the ground, fall when driving off a ledge, hop with A.
        let here = Vehicle.wheelOffsets.map { Vehicle.ground(world, position + forward * $0.y + right * $0.x) }
        let ground = (here.max() ?? position.y) + lift
        if hop && onGround {
            climb = 7.5
            onGround = false
        }
        if !onGround || position.y > ground + 0.3 {
            climb -= gravity * dt
            position.y += climb * dt
            if position.y <= ground {
                position.y = ground
                climb = 0
                onGround = true
            } else {
                onGround = false
            }
        } else {
            // Step up and down small bumps smoothly.
            position.y += (ground - position.y) * min(1, dt * 14)
            climb = 0
            onGround = true
        }
        if onGround {
            let front = (here[0] + here[1]) / 2
            let back = (here[2] + here[3]) / 2
            let left = (here[0] + here[2]) / 2
            let rightSide = (here[1] + here[3]) / 2
            let calm: Float = kind.hovers ? 0.4 : 1
            let targetPitch = min(max(atan2(front - back, 2.6), -0.45), 0.45) * calm
            let targetRoll = min(max(atan2(rightSide - left, 2.0), -0.35), 0.35) * calm - (kind.hovers ? steer * min(1, abs(speed) / 8) * 0.3 : 0)
            pitch += (targetPitch - pitch) * min(1, dt * 8)
            roll += (targetRoll - roll) * min(1, dt * 8)
        } else {
            pitch += (0 - pitch) * min(1, dt * 2)
        }
        return bumped
    }

    /// Wheels, as (right, forward) offsets from the centre.
    private static let wheelOffsets: [SIMD2<Float>] = [SIMD2(-1.0, 1.3), SIMD2(1.0, 1.3), SIMD2(-1.0, -1.3), SIMD2(1.0, -1.3)]

    // MARK: Starship

    /// Which way the nose points, including up and down.
    var heading: SIMD3<Float> {
        SIMD3<Float>(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
    }

    /// Flies like looking around on foot: turn and tip the nose with the look stick (or mouse),
    /// set the speed with the move stick. A rises and B sinks without tipping.
    mutating func fly(dt: Float, turn: Float, tip: Float, throttle: Float, up: Bool, down: Bool, world: World) {
        yaw += turn
        pitch = min(max(pitch + tip, -1.1), 1.1)

        let targetSpeed = throttle > 0 ? throttle * kind.topSpeed : throttle * kind.topSpeed * 0.3
        speed += (targetSpeed - speed) * min(1, dt * 1.6)
        let targetClimb = ((up ? 1 : 0) - (down ? 1 : 0)) * kind.climbRate
        climb += (targetClimb - climb) * min(1, dt * 3)

        var next = position + heading * speed * dt
        next.y += climb * dt
        // Never fly into a hill: the ship lifts itself over the ground ahead.
        let flatAhead = SIMD3<Float>(-sin(yaw), 0, -cos(yaw)) * min(10, abs(speed) * 0.5 + 4)
        let ahead = Vehicle.ground(world, next + flatAhead)
        let below = Vehicle.ground(world, next)
        let floor = max(below, ahead - 1)
        if next.y < floor {
            next.y += (floor - next.y) * min(1, dt * 6)
            if next.y < below { next.y = below }
            // Skimming the ground nose-down: level out.
            if pitch < 0 { pitch += (0 - pitch) * min(1, dt * 4) }
        }
        next.y = min(next.y, Vehicle.shipCeiling)
        position = next
        onGround = position.y <= below + 0.05

        // Lean into turns.
        let targetRoll = onGround ? 0 : min(max(-turn / max(dt, 0.001) * 0.25, -0.6), 0.6)
        roll += (targetRoll - roll) * min(1, dt * 4)
    }

    /// Flying in space: nothing to bump into, and twice as fast.
    mutating func flySpace(dt: Float, turn: Float, tip: Float, throttle: Float, up: Bool, down: Bool) {
        yaw += turn
        pitch = min(max(pitch + tip, -1.3), 1.3)
        let top = kind.topSpeed * 2
        let targetSpeed = throttle > 0 ? throttle * top : throttle * top * 0.3
        speed += (targetSpeed - speed) * min(1, dt * 1.4)
        let targetClimb = ((up ? 1 : 0) - (down ? 1 : 0)) * kind.climbRate * 1.5
        climb += (targetClimb - climb) * min(1, dt * 3)
        position += heading * speed * dt + SIMD3<Float>(0, climb * dt, 0)
        onGround = false
        let targetRoll = min(max(-turn / max(dt, 0.001) * 0.25, -0.6), 0.6)
        roll += (targetRoll - roll) * min(1, dt * 4)
    }
}
