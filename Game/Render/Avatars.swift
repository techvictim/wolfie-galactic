import Foundation
import RealityKit
import simd

/// Friends in the world: a blocky space pup in their colour, with a laser when they fire.
/// Their movement is smoothed, since updates arrive about 15 times a second.
@MainActor
final class Avatars {
    let root = Entity()

    private struct Avatar {
        var card: PlayerCard
        let body: Entity
        let head: Entity
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
        let parts = Avatars.makeBody(color: Avatars.color(card.color))
        let beam = Avatars.makeBeam()
        beam.isEnabled = false
        parts.body.isEnabled = false   // hidden until we know where they are
        root.addChild(parts.body)
        root.addChild(beam)
        avatars[card.id] = Avatar(card: card, body: parts.body, head: parts.head, beam: beam)
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
            avatar.head.orientation = simd_quatf(angle: max(min(shown.pitch, 0.9), -0.9), axis: SIMD3<Float>(1, 0, 0))
            // A little bob while flying.
            if shown.flying {
                avatar.body.position.y += sin(clock * 3 + Float(id)) * 0.06
            }

            if let end = shown.laserEnd, !away {
                let hand = avatar.body.convert(position: SIMD3<Float>(0.32, 1.1, -0.35), to: nil)
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

    private static func box(_ size: SIMD3<Float>, at center: SIMD3<Float>, _ c: SIMD3<Float>) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateBox(width: size.x, height: size.y, depth: size.z), materials: [material(c)])
        entity.position = center
        return entity
    }

    /// About as big as the player: 1.8 m with ears. Faces -z, like the camera.
    private static func makeBody(color c: SIMD3<Float>) -> (body: Entity, head: Entity) {
        let body = Entity()
        let dark = c * 0.62
        let suit = SIMD3<Float>(0.86, 0.88, 0.93)
        let visor = SIMD3<Float>(0.08, 0.06, 0.18)

        // Legs, body and arms: a white space suit with a coloured chest.
        body.addChild(box(SIMD3(0.22, 0.7, 0.26), at: SIMD3(-0.13, 0.35, 0), dark))
        body.addChild(box(SIMD3(0.22, 0.7, 0.26), at: SIMD3(0.13, 0.35, 0), dark))
        body.addChild(box(SIMD3(0.56, 0.62, 0.32), at: SIMD3(0, 1.0, 0), suit))
        body.addChild(box(SIMD3(0.36, 0.3, 0.02), at: SIMD3(0, 1.05, -0.17), c))
        body.addChild(box(SIMD3(0.16, 0.56, 0.2), at: SIMD3(-0.37, 0.98, 0), suit))
        body.addChild(box(SIMD3(0.16, 0.56, 0.2), at: SIMD3(0.37, 0.98, 0), suit))
        // A little blaster in the right hand.
        body.addChild(box(SIMD3(0.1, 0.1, 0.34), at: SIMD3(0.37, 0.72, -0.2), SIMD3(0.3, 0.3, 0.38)))

        // The head tips up and down with where they look. It turns around the neck.
        let head = Entity()
        head.position = SIMD3(0, 1.36, 0)
        head.addChild(box(SIMD3(0.5, 0.46, 0.5), at: SIMD3(0, 0.23, 0), c))
        head.addChild(box(SIMD3(0.4, 0.16, 0.04), at: SIMD3(0, 0.26, -0.26), visor))        // visor band
        head.addChild(box(SIMD3(0.07, 0.07, 0.02), at: SIMD3(-0.1, 0.27, -0.285), SIMD3(1, 0.72, 0.3)))  // eyes
        head.addChild(box(SIMD3(0.07, 0.07, 0.02), at: SIMD3(0.1, 0.27, -0.285), SIMD3(1, 0.72, 0.3)))
        head.addChild(box(SIMD3(0.2, 0.12, 0.14), at: SIMD3(0, 0.1, -0.31), c * 0.85))       // snout
        head.addChild(box(SIMD3(0.07, 0.05, 0.03), at: SIMD3(0, 0.15, -0.385), visor))       // nose
        head.addChild(box(SIMD3(0.13, 0.2, 0.1), at: SIMD3(-0.16, 0.55, 0), dark))           // ears
        head.addChild(box(SIMD3(0.13, 0.2, 0.1), at: SIMD3(0.16, 0.55, 0), dark))
        body.addChild(head)
        return (body, head)
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
