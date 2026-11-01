import Foundation
import RealityKit
import simd

/// Friends in the world: the crew member they picked, with a laser when they fire.
/// Their movement is smoothed, since updates arrive about 15 times a second.
@MainActor
final class Avatars {
    let root = Entity()

    private struct Avatar {
        var card: PlayerCard
        let rig: CrewRig
        var body: Entity { rig.root }
        let beam: Entity
        var target: Pose?
        var shown: Pose?
        /// Their rover or starship, while they're in one.
        var vehicle: Entity?
        var vehicleKind: String?
    }

    private var avatars: [Int: Avatar] = [:]
    /// Only friends on this planet appear; nil hides everyone (you're in space).
    var visiblePlanet: String?

    var cards: [PlayerCard] {
        avatars.values.map(\.card).sorted { $0.id < $1.id }
    }

    func card(_ id: Int) -> PlayerCard? {
        avatars[id]?.card
    }

    /// Where a friend last said they were.
    func pose(of id: Int) -> Pose? {
        avatars[id]?.target
    }

    func add(_ card: PlayerCard) {
        remove(card.id)
        let rig = CrewRig(card.crew ?? "wolfie")
        let beam = Avatars.makeBeam()
        beam.isEnabled = false
        rig.root.isEnabled = false   // hidden until we know where they are
        root.addChild(rig.root)
        root.addChild(beam)
        avatars[card.id] = Avatar(card: card, rig: rig, beam: beam)
    }

    func remove(_ id: Int) {
        guard let avatar = avatars.removeValue(forKey: id) else { return }
        avatar.body.removeFromParent()
        avatar.beam.removeFromParent()
        avatar.vehicle?.removeFromParent()
    }

    func removeAll() {
        for id in Array(avatars.keys) { remove(id) }
    }

    func setPose(_ id: Int, _ pose: Pose) {
        avatars[id]?.target = pose
    }

    /// After landing on a new planet, snap to the next update rather than gliding across the map.
    func forgetPoses() {
        for id in Array(avatars.keys) {
            avatars[id]?.target = nil
            avatars[id]?.shown = nil
            avatars[id]?.body.isEnabled = false
            avatars[id]?.beam.isEnabled = false
        }
    }

    /// Where each friend's name tag goes: just above their head.
    func tagPoints() -> [(card: PlayerCard, point: SIMD3<Float>)] {
        avatars.values.compactMap { avatar in
            guard let shown = avatar.shown else { return nil }
            guard shown.space != true, visiblePlanet != nil, shown.planet == nil || shown.planet == visiblePlanet else { return nil }
            let kind = shown.vehicle.flatMap(VehicleKind.init(rawValue:))
            let height: Float = kind == nil ? 2.25 : (kind!.isShip ? 7 : 4)
            return (avatar.card, shown.position + SIMD3<Float>(0, height, 0))
        }
    }

    func update(dt: Float, clock: Float) {
        let blend = 1 - exp(-dt * 14)
        for id in Array(avatars.keys) {
            guard var avatar = avatars[id], let target = avatar.target else { continue }
            var shown = avatar.shown ?? target
            let before = shown.position
            // Far apart (just joined, or flew away fast): jump straight there.
            if simd_distance(shown.position, target.position) > 12 {
                shown = target
            } else {
                let p = shown.position + (target.position - shown.position) * blend
                shown.x = p.x
                shown.y = p.y
                shown.z = p.z
                shown.yaw += Avatars.angleDifference(target.yaw, shown.yaw) * blend
                shown.pitch += (target.pitch - shown.pitch) * blend
                shown.flying = target.flying
                shown.laser = target.laser
            }
            shown.vehicle = target.vehicle
            shown.space = target.space
            shown.planet = target.planet
            if shown.vehicle != avatar.vehicleKind {
                avatar.vehicle?.removeFromParent()
                avatar.vehicle = nil
                avatar.vehicleKind = shown.vehicle
                if let name = shown.vehicle.flatMap(VehicleKind.init(rawValue:))?.modelName, let model = DetailModels.entity(named: name) {
                    root.addChild(model)
                    avatar.vehicle = model
                }
            }
            avatar.shown = shown
            avatars[id] = avatar

            if let model = avatar.vehicle, let kind = shown.vehicle.flatMap(VehicleKind.init(rawValue:)) {
                // In a vehicle: show the vehicle instead of the pup.
                avatar.body.isEnabled = false
                model.position = shown.position
                model.orientation = simd_quatf(angle: shown.yaw, axis: SIMD3<Float>(0, 1, 0)) * kind.modelTurn
            } else {
                avatar.body.isEnabled = true
            }
            // Off in space or on another planet: not here.
            let away = shown.space == true || visiblePlanet == nil || (shown.planet != nil && shown.planet != visiblePlanet)
            if away {
                avatar.body.isEnabled = false
                avatar.vehicle?.isEnabled = false
            } else {
                avatar.vehicle?.isEnabled = true
            }
            avatar.body.position = shown.position
            avatar.body.orientation = simd_quatf(angle: shown.yaw, axis: SIMD3<Float>(0, 1, 0))
            let moved = shown.position - before
            let speed = dt > 0 ? simd_length(SIMD2<Float>(moved.x, moved.z)) / dt : 0
            avatar.rig.hold(shown.laserEnd != nil ? "laser" : nil)
            avatar.rig.animate(dt: dt, speed: min(speed, 20), pitch: shown.pitch, flying: shown.flying, aiming: shown.laserEnd != nil)

            if let end = shown.laserEnd, !away {
                let hand = avatar.rig.muzzle
                let span = end - hand
                let length = simd_length(span)
                if length > 0.05 {
                    avatar.beam.isEnabled = true
                    avatar.beam.position = (hand + end) / 2
                    avatar.beam.orientation = simd_quatf(from: SIMD3<Float>(0, 0, -1), to: span / length)
                    let flicker = 1 + 0.25 * sin(clock * 60 + Float(id))
                    avatar.beam.scale = SIMD3<Float>(flicker, flicker, length)
                } else {
                    avatar.beam.isEnabled = false
                }
            } else {
                avatar.beam.isEnabled = false
            }
        }
    }

    // MARK: Building the pup

    static func color(_ index: Int) -> SIMD3<Float> {
        let colors = GameSettings.playerColors
        return colors[((index % colors.count) + colors.count) % colors.count]
    }

    private static func material(_ c: SIMD3<Float>) -> UnlitMaterial {
        UnlitMaterial(color: PlatformColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1))
    }

    private static func makeBeam() -> Entity {
        let beam = Entity()
        var core = UnlitMaterial(color: PlatformColor(red: 1, green: 0.85, blue: 0.97, alpha: 1))
        core.blending = .opaque
        var halo = material(SIMD3(1.0, 0.31, 0.85))
        halo.blending = .transparent(opacity: .init(floatLiteral: 0.45))
        beam.addChild(ModelEntity(mesh: .generateBox(width: 0.05, height: 0.05, depth: 1), materials: [core]))
        beam.addChild(ModelEntity(mesh: .generateBox(width: 0.16, height: 0.16, depth: 1), materials: [halo]))
        return beam
    }

    /// The shortest turn from one angle to another.
    private static func angleDifference(_ to: Float, _ from: Float) -> Float {
        var d = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d -= 2 * .pi }
        if d < -.pi { d += 2 * .pi }
        return d
    }
}
