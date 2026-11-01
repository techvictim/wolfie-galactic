import Foundation
import RealityKit
import simd

/// Robo-cats: Glitched machines that come out of Glitch Nests, not real cats. They trot toward
/// you, keep their distance, stop to aim (their head laser glows and a faint red line shows
/// first, so there's time to dodge), then fire with a brief robotic meow. They can't shoot
/// through walls. A knocked-out cat meows sadly, powers down, falls asleep and drops a heart.
@MainActor
final class RoboCats {
    let root = Entity()

    enum Event {
        /// Started aiming at you.
        case charge(at: SIMD3<Float>)
        /// Fired. hit: it got you.
        case shot(from: SIMD3<Float>, to: SIMD3<Float>, hit: Bool)
    }

    /// How tough the cats are, from the Danger setting.
    struct Rules {
        var aimTime: Float
        var hitChance: Float
        var hitsToSleep: Int
        var speed: Float
    }

    private enum State { case roam, chase, aim, rest, asleep }

    private struct Cat {
        let id: Int
        let body: Entity
        let model: Entity
        let legs: [Entity]
        let beam: ModelEntity
        let nest: String
        var position: SIMD3<Float>
        var ground: Float
        var yaw: Float = 0
        var heading: Float = 0
        var state: State = .roam
        var stateTime: Float = 0
        var phase: Float = 0
        var hits = 0
        var flash: Float = 0
        var target = SIMD3<Float>(repeating: 0)
    }

    private struct Heart {
        let entity: Entity
        var life: Float
    }

    private var cats: [Int: Cat] = [:]
    private var hearts: [Heart] = []
    private var nextID = 1
    private var prototype: Entity?
    private static let scale: Float = 0.85
    /// The laser on the head, from the cat's feet (facing -z).
    private static let laserTip = SIMD3<Float>(0, 23, -12.5) / 16 * scale

    var count: Int { cats.values.filter { $0.state != .asleep }.count }

    /// Where every cat is (for the map), and whether it's aiming.
    var spots: [(position: SIMD3<Float>, aiming: Bool)] {
        cats.values.filter { $0.state != .asleep }.map { ($0.position, $0.state == .aim) }
    }

    func count(from nest: String) -> Int {
        cats.values.filter { $0.nest == nest && $0.state != .asleep }.count
    }

    // MARK: Coming and going

    /// A new cat trots out of a nest, next to it.
    func spawn(near nest: GlitchNest, world: World) {
        let side = Int.random(in: 0..<4)
        let lo = nest.min, hi = nest.max
        var x: Float, z: Float
        switch side {
        case 0: x = Float(lo.x) - 2; z = Float.random(in: Float(lo.z)...Float(hi.z))
        case 1: x = Float(hi.x) + 2; z = Float.random(in: Float(lo.z)...Float(hi.z))
        case 2: z = Float(lo.z) - 2; x = Float.random(in: Float(lo.x)...Float(hi.x))
        default: z = Float(hi.z) + 2; x = Float.random(in: Float(lo.x)...Float(hi.x))
        }
        guard let ground = RoboCats.ground(world, SIMD3(x, 0, z)) else { return }
        let body = Entity()
        let model = makeModel()
        body.addChild(model)
        var legs: [Entity] = []
        let legMaterial = Shots.material(SIMD3(0.36, 0.4, 0.46))
        for (lx, lz) in [(Float(-2.5), Float(-2.5)), (2.5, -2.5), (-2.5, 7.5), (2.5, 7.5)] {
            let hip = Entity()
            hip.position = SIMD3(lx, 7, lz) / 16 * RoboCats.scale
            let leg = ModelEntity(mesh: .generateBox(width: 3, height: 7, depth: 3), materials: [legMaterial])
            leg.position = SIMD3(0, -3.5, 0)
            leg.scale = SIMD3(repeating: 1 / 16 * RoboCats.scale)
            leg.position *= 1 / 16 * RoboCats.scale
            hip.addChild(leg)
            body.addChild(hip)
            legs.append(hip)
        }
        let beam = ModelEntity(mesh: .generateBox(width: 0.04, height: 0.04, depth: 1), materials: [Shots.material(SIMD3(1, 0.15, 0.2), opacity: 0.45)])
        beam.isEnabled = false
        root.addChild(beam)
        let position = SIMD3<Float>(x, ground, z)
        body.position = position
        root.addChild(body)
        let id = nextID
        nextID += 1
        var cat = Cat(id: id, body: body, model: model, legs: legs, beam: beam, nest: nest.id, position: position, ground: ground)
        cat.heading = Float.random(in: 0...(2 * .pi))
        cat.yaw = cat.heading
        cats[id] = cat
    }

    func clear() {
        for c in cats.values {
            c.body.removeFromParent()
            c.beam.removeFromParent()
        }
        cats.removeAll()
        for h in hearts { h.entity.removeFromParent() }
        hearts.removeAll()
    }

    /// You got knocked out: everyone nearby runs off for a while.
    func scatter(from point: SIMD3<Float>) {
        for id in Array(cats.keys) {
            guard var c = cats[id], c.state != .asleep, simd_distance(c.position, point) < 40 else { continue }
            let away = c.position - point
            c.heading = atan2(-away.x, -away.z)
            c.state = .rest
            c.stateTime = 6
            c.beam.isEnabled = false
            cats[id] = c
        }
    }

    // MARK: Every frame

    func update(dt: Float, player: SIMD3<Float>, world: World, rules: Rules, canSee: (SIMD3<Float>, SIMD3<Float>) -> Bool) -> [Event] {
        var events: [Event] = []
        let chest = player + SIMD3(0, 1.2, 0)
        for id in Array(cats.keys) {
            guard var c = cats[id] else { continue }
            c.stateTime -= dt
            c.flash = max(0, c.flash - dt)
            let toPlayer = player - c.position
            let flat = SIMD2<Float>(toPlayer.x, toPlayer.z)
            let distance = simd_length(flat)
            let toward = atan2(-flat.x, -flat.y)
            let tip = c.body.convert(position: RoboCats.laserTip, to: nil)

            if c.state == .asleep {
                if c.stateTime <= 0 {
                    c.body.removeFromParent()
                    c.beam.removeFromParent()
                    cats[id] = nil
                    dropHeart(at: c.position)
                } else {
                    c.body.scale = SIMD3(repeating: min(1, c.stateTime / 0.6))
                    cats[id] = c
                }
                continue
            }

            // Too far from you: wander home and disappear.
            if distance > 90 {
                c.body.removeFromParent()
                c.beam.removeFromParent()
                cats[id] = nil
                continue
            }

            var speed: Float = 0
            switch c.state {
            case .roam:
                speed = rules.speed * 0.5
                if c.stateTime <= 0 {
                    c.heading += Float.random(in: -1.2...1.2)
                    c.stateTime = Float.random(in: 1.5...3)
                }
                if distance < 30 && canSee(tip, chest) {
                    c.state = .chase
                }
            case .chase:
                c.heading = toward
                speed = distance > 13 ? rules.speed : 0
                if distance > 45 { c.state = .roam }
                if distance < 18 && c.stateTime <= 0 {
                    if canSee(tip, chest) {
                        c.state = .aim
                        c.stateTime = rules.aimTime
                        c.target = chest
                        events.append(.charge(at: tip))
                    } else {
                        // Can't see you: walk round to find a way.
                        c.heading = toward + Float.random(in: -1.3...1.3)
                        c.stateTime = 0.8
                        speed = rules.speed
                    }
                }
            case .aim:
                c.heading = toward
                // Follows you a little while aiming, but not perfectly.
                c.target += (chest - c.target) * min(1, dt * 2.5)
                if c.stateTime <= 0 {
                    if canSee(tip, chest) {
                        let hit = Float.random(in: 0..<1) < rules.hitChance
                        var end = c.target
                        if !hit {
                            let miss = simd_normalize(SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -0.3...1), Float.random(in: -1...1)))
                            end += miss * Float.random(in: 1.2...2.2)
                        }
                        events.append(.shot(from: tip, to: end, hit: hit))
                    }
                    c.state = .rest
                    c.stateTime = Float.random(in: 1.4...2.6)
                    c.heading = toward + (Bool.random() ? 1.4 : -1.4)
                }
            case .rest:
                speed = rules.speed * 0.6
                if c.stateTime <= 0 { c.state = .chase; c.stateTime = 0.3 }
            case .asleep:
                break
            }

            // The aiming line: faint, then brighter just before the shot.
            if c.state == .aim {
                let span = c.target - tip
                let length = simd_length(span)
                c.beam.isEnabled = length > 0.1
                c.beam.position = (tip + c.target) / 2
                c.beam.orientation = simd_quatf(from: SIMD3<Float>(0, 0, -1), to: span / max(length, 0.001))
                let ready = 1 - max(0, c.stateTime) / rules.aimTime
                let width: Float = 0.5 + ready * 1.5
                c.beam.scale = SIMD3(width, width, length)
            } else {
                c.beam.isEnabled = false
            }

            if speed > 0 {
                let step = SIMD2<Float>(-sin(c.heading), -cos(c.heading)) * speed * dt
                let next = SIMD3<Float>(c.position.x + step.x, c.position.y, c.position.z + step.y)
                if let ground = RoboCats.ground(world, next), ground - c.ground < 1.6, ground - c.ground > -5 {
                    c.position.x = next.x
                    c.position.z = next.z
                } else {
                    c.heading += .pi * Float.random(in: 0.5...1.5)
                }
                c.phase += dt * speed * 2.2
            }
            if let ground = RoboCats.ground(world, c.position) {
                c.ground += (ground - c.ground) * min(1, dt * 12)
            }
            c.position.y = c.ground
            c.yaw += RoboCats.angleDifference(c.heading, c.yaw) * min(1, dt * 7)

            // Trot.
            let swing = speed > 0 ? sin(c.phase * 2) * 0.6 : 0
            for (i, leg) in c.legs.enumerated() {
                let s: Float = (i == 0 || i == 3) ? 1 : -1
                leg.orientation = simd_quatf(angle: swing * s, axis: SIMD3(1, 0, 0))
            }
            c.body.position = c.position + SIMD3(0, speed > 0 ? abs(sin(c.phase * 2)) * 0.06 : 0, 0)
            c.body.orientation = simd_quatf(angle: c.yaw, axis: SIMD3(0, 1, 0))
            c.model.scale = SIMD3(repeating: (c.flash > 0 ? 1.12 : 1) / 16 * RoboCats.scale)
            cats[id] = c
        }
        updateHearts(dt: dt)
        return events
    }

    // MARK: Getting hit

    /// The nearest cat along a ray.
    func target(origin: SIMD3<Float>, direction: SIMD3<Float>, maxDistance: Float) -> (id: Int, distance: Float, point: SIMD3<Float>)? {
        var best: (id: Int, distance: Float, point: SIMD3<Float>)?
        for c in cats.values where c.state != .asleep {
            let center = c.position + SIMD3(0, 0.8, 0)
            let along = simd_dot(center - origin, direction)
            guard along > 0, along < maxDistance + 1 else { continue }
            guard simd_distance(origin + direction * along, center) < 0.95 else { continue }
            if best == nil || along < best!.distance { best = (c.id, along, center) }
        }
        return best
    }

    func nearestDistance(to point: SIMD3<Float>) -> Float {
        cats.values.filter { $0.state != .asleep }.map { simd_distance($0.position + SIMD3(0, 0.7, 0), point) }.min() ?? .infinity
    }

    /// One hit. True if it's knocked out (asleep).
    @discardableResult
    func hit(_ id: Int, from origin: SIMD3<Float>, hitsToSleep: Int, direct: Bool = false) -> Bool {
        guard var c = cats[id], c.state != .asleep else { return false }
        c.hits += 1
        c.flash = 0.15
        if direct || c.hits >= hitsToSleep {
            c.state = .asleep
            c.stateTime = 3
            c.beam.isEnabled = false
            // Tips over onto its side.
            c.model.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
            c.model.position = SIMD3(0.5, 0.4, 0) * RoboCats.scale
            cats[id] = c
            return true
        }
        // Startled: hops back.
        let away = c.position - origin
        c.heading = atan2(-away.x, -away.z)
        c.state = .rest
        c.stateTime = 0.8
        c.beam.isEnabled = false
        cats[id] = c
        return false
    }

    /// Everything inside a blast. Returns how many got knocked out and how many just got hit.
    func blast(at point: SIMD3<Float>, radius: Float, hitsToSleep: Int) -> (asleep: [SIMD3<Float>], hurt: Int) {
        var asleep: [SIMD3<Float>] = []
        var hurt = 0
        for (id, c) in cats where c.state != .asleep {
            let d = simd_distance(c.position + SIMD3(0, 0.7, 0), point)
            guard d < radius else { continue }
            if hit(id, from: point, hitsToSleep: hitsToSleep, direct: d < radius * 0.5) {
                asleep.append(c.position)
            } else {
                hurt += 1
            }
        }
        return (asleep, hurt)
    }

    func ids(near point: SIMD3<Float>, within radius: Float) -> [Int] {
        cats.values.filter { $0.state != .asleep && simd_distance($0.position, point) < radius }.map(\.id)
    }

    func position(of id: Int) -> SIMD3<Float>? {
        cats[id]?.position
    }

    // MARK: Hearts

    private func dropHeart(at point: SIMD3<Float>) {
        let heart = Entity()
        let red = Shots.material(SIMD3(1, 0.25, 0.4))
        for (x, y) in [(Float(-0.09), Float(0.08)), (0.09, 0.08), (0, -0.04)] {
            let part = ModelEntity(mesh: .generateBox(size: y > 0 ? 0.16 : 0.2), materials: [red])
            part.position = SIMD3(x, y, 0)
            if y < 0 { part.orientation = simd_quatf(angle: .pi / 4, axis: SIMD3(0, 0, 1)) }
            heart.addChild(part)
        }
        heart.position = point + SIMD3(0, 0.8, 0)
        root.addChild(heart)
        hearts.append(Heart(entity: heart, life: 40))
    }

    private func updateHearts(dt: Float) {
        for i in hearts.indices.reversed() {
            hearts[i].life -= dt
            let h = hearts[i]
            h.entity.orientation = simd_quatf(angle: h.life * 2, axis: SIMD3(0, 1, 0))
            if h.life <= 0 {
                h.entity.removeFromParent()
                hearts.remove(at: i)
            }
        }
    }

    /// Walk over a heart to pick it up.
    func collectHeart(near point: SIMD3<Float>) -> Bool {
        guard let i = hearts.firstIndex(where: { simd_distance($0.entity.position, point + SIMD3(0, 0.8, 0)) < 1.6 }) else { return false }
        hearts[i].entity.removeFromParent()
        hearts.remove(at: i)
        return true
    }

    // MARK: Helpers

    private func makeModel() -> Entity {
        if prototype == nil {
            prototype = DetailModels.entity(named: "robocat")
        }
        guard let prototype else { return Entity() }
        let model = prototype.clone(recursive: true)
        // The .vox grid's corner is at (-12, 0, -18) toy pixels; DetailModels centres it.
        model.scale = SIMD3(repeating: 1 / 16 * RoboCats.scale)
        model.position = SIMD3(0, 0, -1) / 16 * RoboCats.scale
        return model
    }

    private static func ground(_ world: World, _ p: SIMD3<Float>) -> Float? {
        let x = Int(floor(p.x)), z = Int(floor(p.z))
        guard world.cachedChunk(World.key(x: x, z: z)) != nil else { return nil }
        return Float(world.surfaceY(x: x, z: z))
    }

    private static func angleDifference(_ to: Float, _ from: Float) -> Float {
        var d = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d -= 2 * .pi }
        if d < -.pi { d += 2 * .pi }
        return d
    }
}
