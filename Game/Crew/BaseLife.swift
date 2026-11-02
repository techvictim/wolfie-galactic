import Foundation
import RealityKit
import simd

/// Life at Wolfie Military's base: troops doing jumping jacks and squats in the yard, a squad
/// marching round it, guards at the gate, and drones hovering on patrol overhead.
@MainActor
final class BaseLife {
    let root = Entity()

    private struct Troop {
        let rig: CrewRig
        /// "jacks", "squat", "salute", "march" or "guard".
        let job: String
        let spot: SIMD3<Float>
        let yaw: Float
        let offset: Float
    }

    private struct Drone {
        let entity: Entity
        let light: ModelEntity
        let center: SIMD3<Float>
        let radius: Float
        let speed: Float
        let phase: Float
    }

    private var troops: [Troop] = []
    private var drones: [Drone] = []
    private var clock: Float = 0
    private var center = SIMD3<Float>(repeating: 0)
    private(set) var active = false

    func clear() {
        for child in Array(root.children) { child.removeFromParent() }
        troops.removeAll()
        drones.removeAll()
        active = false
    }

    /// Set up the base for this planet (only Wolfie World has one).
    func setup(world: World, planet: Planet) {
        clear()
        guard planet.id == TerrainGenerator.homePlanet else { return }
        let gen = world.generator
        let b = TerrainGenerator.militaryBase
        guard let site = gen.settlement(near: b.x, b.y), site.kind == .military else { return }
        active = true
        let g = Float(site.ground)
        let o = MilitaryLayout.origin
        func at(_ lx: Float, _ lz: Float, _ y: Float = 0) -> SIMD3<Float> {
            SIMD3(Float(o.x) + lx, g + y, Float(o.y) + lz)
        }
        center = at(Float(MilitaryLayout.size) / 2, Float(MilitaryLayout.size) / 2)
        let ids = Crew.all.map(\.id)
        var n = 0
        func troop(_ job: String, _ p: SIMD3<Float>, yaw: Float, holding: String? = nil) {
            let rig = CrewRig(ids[n % ids.count])
            n += 1
            rig.hold(holding)
            rig.root.position = p
            rig.root.orientation = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
            root.addChild(rig.root)
            troops.append(Troop(rig: rig, job: job, spot: p, yaw: yaw, offset: Float(n) * 0.37))
        }
        let yard = MilitaryLayout.yard
        // Two squads in rows, facing their sergeant at the front of the yard.
        for row in 0..<2 {
            for col in 0..<4 {
                let job = row == 0 ? "jacks" : "squat"
                troop(job, at(Float(yard.x0 + 6 + col * 4), Float(yard.z0 + 9 + row * 4)), yaw: 0)
            }
        }
        troop("salute", at(Float(yard.x0 + 12), Float(yard.z0 + 4)), yaw: .pi)
        // A squad marching round the yard, single file.
        for _ in 0..<5 { troop("march", at(0, 0), yaw: 0, holding: "gun") }
        // Guards at the gate and by the armory.
        let gateX = Float(MilitaryLayout.size / 2)
        troop("guard", at(gateX - 6, 3), yaw: 0, holding: "gun")
        troop("guard", at(gateX + 6, 3), yaw: 0, holding: "gun")
        let a = MilitaryLayout.armory
        troop("guard", at(Float(a.x0 + a.x1) / 2 + 3, Float(a.z1) + 1.5), yaw: 0, holding: "launcher")

        // Drones: patrolling in loops over the base.
        for i in 0..<8 {
            let (drone, _) = Shots.model("drone", size: 3.5)
            let light = Shots.box(SIMD3(0.12, 0.06, 0.12), SIMD3(0, -0.1, 0), i % 2 == 0 ? SIMD3(0.4, 1, 1) : SIMD3(1, 0.3, 0.4))
            drone.addChild(light)
            root.addChild(drone)
            let cx = Float(10 + (i % 4) * 24), cz = Float(12 + (i / 4) * 44)
            drones.append(Drone(entity: drone, light: light, center: at(cx, cz, 9 + Float(i % 3) * 3),
                                radius: 6 + Float(i % 3) * 3, speed: (i % 2 == 0 ? 1 : -1) * (0.25 + Float(i) * 0.03), phase: Float(i) * 0.9))
        }
    }

    /// Animate everyone. Far away, nothing moves (and nothing's drawn).
    func update(dt: Float, viewer: SIMD3<Float>) {
        guard active else { return }
        let near = simd_distance(SIMD2(viewer.x, viewer.z), SIMD2(center.x, center.z)) < 170
        root.isEnabled = near
        guard near else { return }
        clock += dt
        let yard = MilitaryLayout.yard
        let o = MilitaryLayout.origin
        // The marching loop: a rectangle just inside the yard.
        let loop: [SIMD2<Float>] = [
            SIMD2(Float(yard.x0) + 1.5, Float(yard.z0) + 1.5), SIMD2(Float(yard.x1) - 1.5, Float(yard.z0) + 1.5),
            SIMD2(Float(yard.x1) - 1.5, Float(yard.z1) - 1.5), SIMD2(Float(yard.x0) + 1.5, Float(yard.z1) - 1.5),
        ].map { $0 + SIMD2(Float(o.x), Float(o.y)) }
        var lengths: [Float] = []
        for i in 0..<4 { lengths.append(simd_distance(loop[i], loop[(i + 1) % 4])) }
        let perimeter = lengths.reduce(0, +)
        var marcher = 0
        for t in troops {
            switch t.job {
            case "march":
                var d = (clock * 2.6 - Float(marcher) * 2.2).truncatingRemainder(dividingBy: perimeter)
                if d < 0 { d += perimeter }
                marcher += 1
                var side = 0
                while d > lengths[side] { d -= lengths[side]; side += 1 }
                let a = loop[side], b = loop[(side + 1) % 4]
                let p = a + (b - a) * (d / lengths[side])
                let dir = simd_normalize(b - a)
                t.rig.root.position = SIMD3(p.x, t.spot.y, p.y)
                t.rig.root.orientation = simd_quatf(angle: atan2(-dir.x, -dir.y), axis: SIMD3(0, 1, 0))
                t.rig.animate(dt: dt, speed: 2.6, pitch: 0, flying: false, aiming: false)
            case "guard":
                // Look around now and then.
                let look = sin(clock * 0.4 + t.offset * 3) * 0.6
                t.rig.root.orientation = simd_quatf(angle: t.yaw + look, axis: SIMD3(0, 1, 0))
                t.rig.animate(dt: dt, speed: 0, pitch: 0, flying: false, aiming: false)
            default:
                let lift = t.rig.exercise(t.job, clock: clock + t.offset * 0.15)
                t.rig.root.position = t.spot + SIMD3(0, lift, 0)
            }
        }
        for d in drones {
            let a = clock * d.speed + d.phase
            let bob = sin(clock * 1.7 + d.phase) * 0.6
            d.entity.position = d.center + SIMD3(cos(a) * d.radius, bob, sin(a) * d.radius)
            // Face the way it's flying, tipped a little into the turn.
            let heading = atan2(-(-sin(a)) * d.speed, -(cos(a)) * d.speed)
            d.entity.orientation = simd_quatf(angle: heading, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: -0.12, axis: SIMD3(1, 0, 0))
            d.light.isEnabled = Int(clock * 2 + d.phase) % 2 == 0
        }
    }
}
