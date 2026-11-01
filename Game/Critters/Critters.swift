import Foundation
import RealityKit
import simd

/// Something that happened to a critter that the game should react to.
enum CritterEvent {
    /// A grumpy critter bumped into you.
    case bump(from: SIMD3<Float>)
    /// A critter made a noise.
    case sound(String, at: SIMD3<Float>, pitch: Float)
}

/// What happened when the laser hit a critter.
enum ZapResult {
    /// A friendly critter got a fright and ran off. Nobody is hurt.
    case startled(CritterKind)
    /// A grumpy critter got zapped but is still grumbling.
    case zapped(CritterKind)
    /// A grumpy critter had enough and poofed home.
    case poofed(CritterKind, at: SIMD3<Float>)
}

/// The critters around you: spawns them nearby as you explore, moves and animates them,
/// and forgets them when you go far away. Befriended critters follow you around.
@MainActor
final class Critters {
    let root = Entity()

    private enum State {
        case idle, wander, flee, follow, chase, backOff
    }

    private struct Critter {
        let id: Int
        let kind: CritterKind
        let body: Entity
        let model: Entity
        var position: SIMD3<Float>
        /// Ground height under the critter, smoothed.
        var ground: Float
        var yaw: Float
        var heading: Float
        var state: State = .wander
        var stateTime: Float = 0
        var phase: Float = 0
        var friend = false
        var hits = 0
        var soundTimer: Float
        var hearts: Float = 0
        var hurtFlash: Float = 0
    }

    private var critters: [Int: Critter] = [:]
    private var nextID = 1
    private var spawnTimer: Float = 0
    private var prototypes: [String: Entity] = [:]
    private var hearts: [(entity: Entity, life: Float)] = []
    private var sparkles: [(entity: Entity, velocity: SIMD3<Float>, life: Float)] = []
    private var planetID = ""

    /// Befriended critters that follow you, at most this many at once.
    static let maxFollowers = 4
    private static let despawnDistance: Float = 80

    var followerCount: Int { critters.values.filter(\.friend).count }

    /// New planet: everyone stays behind.
    func reset(planet: String) {
        for critter in critters.values { critter.body.removeFromParent() }
        critters.removeAll()
        for heart in hearts { heart.entity.removeFromParent() }
        hearts.removeAll()
        for sparkle in sparkles { sparkle.entity.removeFromParent() }
        sparkles.removeAll()
        planetID = planet
        spawnTimer = 0
    }

    /// Danger turned off: grumpy critters go home.
    func removeGrumpy() {
        for (id, critter) in critters where critter.kind.isGrumpy {
            critter.body.removeFromParent()
            critters[id] = nil
        }
    }

    /// After being knocked out, grumpy critters near where you wake up wander off.
    func clearGrumpy(near point: SIMD3<Float>, radius: Float) {
        for (id, critter) in critters where critter.kind.isGrumpy && simd_distance(critter.position, point) < radius {
            critter.body.removeFromParent()
            critters[id] = nil
        }
    }

    // MARK: Every frame

    /// grumpyLimit is 0 when Danger is off.
    func update(dt: Float, player: Player, world: World, gravity: Float, grumpyLimit: Int, clock: Float) -> [CritterEvent] {
        var events: [CritterEvent] = []
        spawnTimer -= dt
        if spawnTimer <= 0 {
            spawnTimer = 1.2
            despawnFar(from: player.position)
            spawn(around: player.position, world: world, grumpyLimit: grumpyLimit)
        }

        let low = gravity < 16
        for id in Array(critters.keys) {
            guard var c = critters[id] else { continue }
            c.stateTime -= dt
            c.soundTimer -= dt
            c.hearts = max(0, c.hearts - dt)
            c.hurtFlash = max(0, c.hurtFlash - dt)

            let toPlayer = player.position - c.position
            let flat = SIMD2<Float>(toPlayer.x, toPlayer.z)
            let distance = simd_length(flat)
            think(&c, distance: distance, toPlayer: flat, events: &events)

            // Move.
            var speed: Float = 0
            switch c.state {
            case .idle: speed = 0
            case .wander: speed = c.kind.speed
            case .flee: speed = c.kind.speed * 2.4
            case .follow: speed = distance > 3.5 ? max(c.kind.speed * 2.2, 5) : 0
            case .chase: speed = c.kind.speed * (grumpyLimit > 2 ? 1.25 : 1)
            case .backOff: speed = c.kind.speed * 1.5
            }
            if c.kind.move == .hop {
                // Moves only while in the air.
                let hopPhase = (c.phase * 1.4).truncatingRemainder(dividingBy: 1)
                if hopPhase > 0.65 { speed = 0 }
            }

            if speed > 0 {
                let step = SIMD2<Float>(-sin(c.heading), -cos(c.heading)) * speed * dt
                let next = SIMD3<Float>(c.position.x + step.x, c.position.y, c.position.z + step.y)
                if let ground = Critters.ground(world, next) {
                    let climb = ground - c.ground
                    let ok = c.kind.move == .hover ? climb < 4 : (climb < 1.6 && climb > -4.5)
                    if ok {
                        c.position.x = next.x
                        c.position.z = next.z
                    } else if c.state == .wander || c.state == .flee {
                        c.heading += .pi * Float.random(in: 0.6...1.4)
                    }
                } else if c.state == .wander || c.state == .flee {
                    c.heading += .pi
                }
                c.phase += dt * (c.kind.move == .scuttle ? 2.5 : 1.6) * (speed / max(c.kind.speed, 0.1))
            } else if c.kind.move == .hover || c.kind.move == .hop {
                c.phase += dt * 0.9
            }

            // Followers that fall far behind (you flew off) catch up by magic.
            if c.friend && distance > 40 {
                let behind = player.position - SIMD3<Float>(-sin(player.yaw), 0, -cos(player.yaw)) * 3
                if let ground = Critters.ground(world, behind) {
                    c.position = SIMD3<Float>(behind.x, ground, behind.z)
                    c.ground = ground
                }
            }

            if let ground = Critters.ground(world, c.position) {
                c.ground += (ground - c.ground) * min(1, dt * 12)
            }
            c.position.y = c.ground

            // Turn smoothly toward where it's going.
            let face = c.kind.move == .scuttle && speed > 0 ? c.heading + .pi / 2 : c.heading
            c.yaw += Critters.angleDifference(face, c.yaw) * min(1, dt * 6)

            if c.soundTimer <= 0 {
                c.soundTimer = Float.random(in: 6...14)
                if distance < 30 {
                    events.append(.sound(c.kind.sound, at: c.position, pitch: Float.random(in: 0.9...1.15)))
                }
            }

            pose(&c, clock: clock, lowGravity: low)
            critters[id] = c
        }

        updateEffects(dt: dt)
        return events
    }

    /// Decide what to do next.
    private func think(_ c: inout Critter, distance: Float, toPlayer: SIMD2<Float>, events: inout [CritterEvent]) {
        let towardPlayer = atan2(-toPlayer.x, -toPlayer.y)
        if c.friend {
            c.state = .follow
            if distance > 3.5 { c.heading = towardPlayer }
            return
        }
        if c.kind.isGrumpy {
            switch c.state {
            case .backOff:
                if c.stateTime <= 0 { c.state = .wander; c.stateTime = 1 }
                return
            case .chase:
                if distance > 20 {
                    c.state = .wander
                    c.stateTime = 2
                } else {
                    c.heading = towardPlayer
                    if distance < 1.3 {
                        events.append(.bump(from: c.position))
                        c.state = .backOff
                        c.stateTime = 1.4
                        c.heading = towardPlayer + .pi
                    }
                }
                return
            default:
                if distance < 13 {
                    c.state = .chase
                    events.append(.sound("grumble", at: c.position, pitch: Float.random(in: 0.9...1.1)))
                    return
                }
            }
        }
        if c.state == .flee {
            if c.stateTime > 0 { return }
            c.state = .idle
            c.stateTime = 1
        }
        if c.stateTime <= 0 {
            if c.state == .idle {
                c.state = .wander
                c.stateTime = Float.random(in: 2...5)
                c.heading = Float.random(in: 0...(2 * .pi))
            } else {
                c.state = .idle
                c.stateTime = Float.random(in: 1...3)
            }
        }
    }

    /// Place the model: waddle, hop, hover or scuttle.
    private func pose(_ c: inout Critter, clock: Float, lowGravity: Bool) {
        var lift: Float = 0
        var roll: Float = 0
        var squash: Float = 1
        let p = c.phase
        switch c.kind.move {
        case .waddle:
            roll = sin(p * 9) * 0.12 * (c.state == .idle ? 0.2 : 1)
            lift = abs(sin(p * 9)) * 0.08
        case .hop:
            let t = (p * 1.4).truncatingRemainder(dividingBy: 1)
            if t < 0.65 {
                lift = sin(t / 0.65 * .pi) * (lowGravity ? 1.8 : 0.8)
                squash = 1.06
            } else {
                squash = 0.9 + 0.1 * (t - 0.65) / 0.35
            }
        case .hover:
            lift = 1.3 + sin(clock * 2.2 + Float(c.id)) * 0.22
            roll = sin(clock * 1.7 + Float(c.id)) * 0.1
        case .scuttle:
            lift = abs(sin(p * 14)) * 0.05
            roll = sin(p * 14) * 0.05
        }
        c.body.position = c.position + SIMD3<Float>(0, lift, 0)
        c.body.orientation = simd_quatf(angle: c.yaw, axis: SIMD3<Float>(0, 1, 0)) * simd_quatf(angle: roll, axis: SIMD3<Float>(0, 0, 1))
        let flash: Float = c.hurtFlash > 0 ? 1.15 : 1
        c.model.scale = SIMD3<Float>(flash / squash.squareRoot(), squash * flash, flash / squash.squareRoot()) / DetailModels.voxelsPerBlock
    }

    // MARK: Spawning

    private func spawn(around center: SIMD3<Float>, world: World, grumpyLimit: Int) {
        let catalog = CritterCatalog.shared
        for kind in catalog.friendly(on: planetID) {
            let have = critters.values.filter { $0.kind.id == kind.id && !$0.friend }.count
            if have < kind.count { _ = add(kind, around: center, world: world, minDistance: 14, maxDistance: 40) }
        }
        if grumpyLimit > 0 {
            let grumpy = catalog.grumpy(on: planetID)
            let have = critters.values.filter(\.kind.isGrumpy).count
            if have < grumpyLimit, let kind = grumpy.randomElement() {
                _ = add(kind, around: center, world: world, minDistance: 26, maxDistance: 48)
            }
        }
    }

    private func add(_ kind: CritterKind, around center: SIMD3<Float>, world: World, minDistance: Float, maxDistance: Float) -> Bool {
        let angle = Float.random(in: 0...(2 * .pi))
        let r = Float.random(in: minDistance...maxDistance)
        let spot = center + SIMD3<Float>(cos(angle) * r, 0, sin(angle) * r)
        guard let ground = Critters.ground(world, spot), ground > 1, ground < Float(World.height - 4),
              let model = model(for: kind.id) else { return false }
        let body = Entity()
        body.addChild(model)
        root.addChild(body)
        let id = nextID
        nextID += 1
        var critter = Critter(
            id: id, kind: kind, body: body, model: model,
            position: SIMD3<Float>(spot.x, ground, spot.z), ground: ground,
            yaw: angle, heading: angle, soundTimer: Float.random(in: 2...10)
        )
        critter.stateTime = Float.random(in: 0...2)
        pose(&critter, clock: 0, lowGravity: false)
        critters[id] = critter
        return true
    }

    private func despawnFar(from center: SIMD3<Float>) {
        for (id, critter) in critters where !critter.friend {
            if simd_distance(critter.position, center) > Critters.despawnDistance {
                critter.body.removeFromParent()
                critters[id] = nil
            }
        }
    }

    /// A copy of the critter's model. The mesh is shared, so this is cheap.
    private func model(for id: String) -> Entity? {
        if prototypes[id] == nil {
            prototypes[id] = DetailModels.entity(named: id)
        }
        return prototypes[id]?.clone(recursive: true)
    }

    /// Top of the ground, only where the world is already loaded (never makes new chunks here).
    private static func ground(_ world: World, _ p: SIMD3<Float>) -> Float? {
        let x = Int(floor(p.x))
        let z = Int(floor(p.z))
        guard world.cachedChunk(World.key(x: x, z: z)) != nil else { return nil }
        return Float(world.surfaceY(x: x, z: z))
    }

    // MARK: Aiming, petting and zapping

    /// The nearest critter along a ray, within reach.
    func target(origin: SIMD3<Float>, direction: SIMD3<Float>, maxDistance: Float) -> (id: Int, kind: CritterKind, distance: Float, point: SIMD3<Float>)? {
        var best: (id: Int, kind: CritterKind, distance: Float, point: SIMD3<Float>)?
        for critter in critters.values {
            let center = critter.body.position + SIMD3<Float>(0, 0.7, 0)
            let radius: Float = 0.85
            let along = simd_dot(center - origin, direction)
            guard along > 0, along < maxDistance + radius else { continue }
            let closest = origin + direction * along
            guard simd_distance(closest, center) < radius else { continue }
            if best == nil || along < best!.distance {
                best = (critter.id, critter.kind, along, center)
            }
        }
        return best
    }

    func isFriend(_ id: Int) -> Bool {
        critters[id]?.friend ?? false
    }

    /// Give a critter a pat. Returns true if it just became your friend.
    func pet(_ id: Int) -> Bool {
        guard var c = critters[id], !c.kind.isGrumpy else { return false }
        let wasFriend = c.friend
        if !wasFriend {
            // Too many followers: the one that's been along longest goes back to exploring.
            let followers = critters.values.filter(\.friend).sorted { $0.id < $1.id }
            if followers.count >= Critters.maxFollowers, let oldest = followers.first {
                critters[oldest.id]?.friend = false
                critters[oldest.id]?.state = .wander
                critters[oldest.id]?.stateTime = 3
            }
        }
        c.friend = true
        c.state = .follow
        c.hearts = 1.2
        critters[id] = c
        popHearts(at: c.body.position + SIMD3<Float>(0, 1.6, 0))
        return !wasFriend
    }

    func zap(_ id: Int, from origin: SIMD3<Float>, hitsToPoof: Int) -> ZapResult? {
        guard var c = critters[id] else { return nil }
        if !c.kind.isGrumpy {
            // Friendly critters just get a fright and run, even friends (they come back).
            if !c.friend {
                c.state = .flee
                c.stateTime = 2.2
                let away = c.position - origin
                c.heading = atan2(-away.x, -away.z)
            }
            c.hurtFlash = 0.15
            critters[id] = c
            return .startled(c.kind)
        }
        c.hits += 1
        c.hurtFlash = 0.15
        c.state = .backOff
        c.stateTime = 0.6
        let away = c.position - origin
        c.heading = atan2(-away.x, -away.z)
        if c.hits >= hitsToPoof {
            let at = c.body.position + SIMD3<Float>(0, 0.8, 0)
            c.body.removeFromParent()
            critters[id] = nil
            poof(at: at)
            return .poofed(c.kind, at: at)
        }
        critters[id] = c
        return .zapped(c.kind)
    }

    /// A blast or a black hole nearby: grumpy critters poof home, friendly ones get a fright and run.
    func blast(at point: SIMD3<Float>, radius: Float) -> [ZapResult] {
        var results: [ZapResult] = []
        for id in Array(critters.keys) {
            guard let c = critters[id], simd_distance(c.position, point) < radius else { continue }
            if let result = zap(id, from: point, hitsToPoof: 1) { results.append(result) }
        }
        return results
    }

    /// How far the nearest critter is, for mines.
    func nearestDistance(to point: SIMD3<Float>) -> Float {
        critters.values.map { simd_distance($0.position, point) }.min() ?? .infinity
    }

    // MARK: Little effects

    private func popHearts(at point: SIMD3<Float>) {
        for i in 0..<3 {
            let heart = Critters.makeHeart()
            heart.position = point + SIMD3<Float>(Float(i - 1) * 0.35, Float(i) * 0.15, 0)
            root.addChild(heart)
            hearts.append((heart, 1.3 + Float(i) * 0.15))
        }
    }

    private func poof(at point: SIMD3<Float>) {
        let colors: [SIMD3<Float>] = [SIMD3(1, 0.9, 0.4), SIMD3(0.6, 0.4, 1), SIMD3(1, 1, 1), SIMD3(1, 0.5, 0.8)]
        for i in 0..<14 {
            let c = colors[i % colors.count]
            let cube = ModelEntity(mesh: .generateBox(size: 0.18), materials: [UnlitMaterial(color: PlatformColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1))])
            cube.position = point
            root.addChild(cube)
            let direction = simd_normalize(SIMD3<Float>(Float.random(in: -1...1), Float.random(in: 0.2...1.2), Float.random(in: -1...1)))
            sparkles.append((cube, direction * Float.random(in: 2.5...5), 0.9))
        }
    }

    private func updateEffects(dt: Float) {
        for i in hearts.indices.reversed() {
            hearts[i].life -= dt
            let heart = hearts[i].entity
            heart.position.y += dt * 0.9
            heart.orientation = simd_quatf(angle: hearts[i].life * 3, axis: SIMD3<Float>(0, 1, 0))
            let s = min(1, hearts[i].life * 2)
            heart.scale = SIMD3<Float>(repeating: s)
            if hearts[i].life <= 0 {
                heart.removeFromParent()
                hearts.remove(at: i)
            }
        }
        for i in sparkles.indices.reversed() {
            sparkles[i].life -= dt
            sparkles[i].velocity.y -= 6 * dt
            sparkles[i].entity.position += sparkles[i].velocity * dt
            sparkles[i].entity.scale = SIMD3<Float>(repeating: max(0.01, sparkles[i].life))
            if sparkles[i].life <= 0 {
                sparkles[i].entity.removeFromParent()
                sparkles.remove(at: i)
            }
        }
    }

    /// A little pink voxel heart.
    private static func makeHeart() -> Entity {
        let heart = Entity()
        let material = UnlitMaterial(color: PlatformColor(red: 1, green: 0.4, blue: 0.62, alpha: 1))
        let cells: [SIMD2<Float>] = [SIMD2(-1, 1), SIMD2(1, 1), SIMD2(-1, 0), SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, -1)]
        for cell in cells {
            let cube = ModelEntity(mesh: .generateBox(size: 0.1), materials: [material])
            cube.position = SIMD3<Float>(cell.x * 0.1, cell.y * 0.1, 0)
            heart.addChild(cube)
        }
        return heart
    }

    private static func angleDifference(_ to: Float, _ from: Float) -> Float {
        var d = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d -= 2 * .pi }
        if d < -.pi { d += 2 * .pi }
        return d
    }
}
