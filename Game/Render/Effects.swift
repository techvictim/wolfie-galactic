import Foundation
import RealityKit
import simd

/// Quick visual effects: laser bolts that fly to their target, and fiery bursts when a block
/// is blasted (a flash, flames that cool from white to red, chunks of the block, and smoke).
/// Small cubes are reused from a pool, and colours are shared materials, so this stays cheap.
@MainActor
final class Effects {
    let root = Entity()

    private struct Particle {
        let entity: ModelEntity
        var velocity: SIMD3<Float>
        var age: Float = 0
        let life: Float
        let startSize: Float
        let endSize: Float
        let gravity: Float
        let drag: Float
        let kind: Kind
        var stage = -1
        var spin: SIMD3<Float>
    }

    private enum Kind {
        case flash, flame, ember, debris(SIMD3<Float>), smoke
    }

    private struct Bolt {
        let entity: Entity
        var position: SIMD3<Float>
        let target: SIMD3<Float>
        let speed: Float
        let onHit: () -> Void
    }

    private var particles: [Particle] = []
    private var bolts: [Bolt] = []
    private var pool: [ModelEntity] = []
    private let cube = MeshResource.generateBox(size: 1)
    private var materials: [String: UnlitMaterial] = [:]

    private static let maxParticles = 260

    /// Flames cool as they age.
    private static let fire: [SIMD3<Float>] = [
        SIMD3(1.0, 0.97, 0.82), SIMD3(1.0, 0.86, 0.35), SIMD3(1.0, 0.6, 0.15),
        SIMD3(0.92, 0.33, 0.08), SIMD3(0.55, 0.16, 0.06)
    ]

    // MARK: Bolts

    /// A glowing laser bolt from a vehicle's blaster. onHit runs when it gets there.
    func fireBolt(from start: SIMD3<Float>, to end: SIMD3<Float>, color: SIMD3<Float>, speed: Float = 140, onHit: @escaping () -> Void) {
        let bolt = Entity()
        let core = ModelEntity(mesh: cube, materials: [material(SIMD3(1, 0.95, 0.98), opacity: 1)])
        core.scale = SIMD3(0.09, 0.09, 1.4)
        let glow = ModelEntity(mesh: cube, materials: [material(color, opacity: 0.5)])
        glow.scale = SIMD3(0.26, 0.26, 1.9)
        bolt.addChild(glow)
        bolt.addChild(core)
        let span = end - start
        let length = simd_length(span)
        guard length > 0.01 else {
            onHit()
            return
        }
        bolt.position = start
        bolt.orientation = simd_quatf(from: SIMD3<Float>(0, 0, -1), to: span / length)
        root.addChild(bolt)
        bolts.append(Bolt(entity: bolt, position: start, target: end, speed: speed, onHit: onHit))
        // A little muzzle flash.
        spawn(.flash, at: start, velocity: .zero, life: 0.06, size: (0.25, 0.7), gravity: 0, drag: 0)
    }

    // MARK: Bursts

    /// A block blown up: a bright flash, flames, sparks, bits of the block and a puff of smoke.
    func blockBurst(at center: SIMD3<Float>, blockColor: SIMD3<Float>) {
        spawn(.flash, at: center, velocity: .zero, life: 0.09, size: (0.6, 1.9), gravity: 0, drag: 0)
        for _ in 0..<12 {
            let dir = Effects.randomDirection(upward: 0.4)
            spawn(.flame, at: center + dir * 0.2, velocity: dir * Float.random(in: 2.5...5.5), life: Float.random(in: 0.28...0.5),
                  size: (Float.random(in: 0.28...0.45), 0.05), gravity: -2.5, drag: 3.5)
        }
        for _ in 0..<8 {
            let dir = Effects.randomDirection(upward: 0.6)
            spawn(.ember, at: center, velocity: dir * Float.random(in: 6...11), life: Float.random(in: 0.35...0.7),
                  size: (0.08, 0.02), gravity: 9, drag: 1)
        }
        for _ in 0..<7 {
            let dir = Effects.randomDirection(upward: 0.8)
            spawn(.debris(blockColor), at: center + dir * 0.25, velocity: dir * Float.random(in: 3...7), life: Float.random(in: 0.6...1.1),
                  size: (Float.random(in: 0.16...0.28), 0.05), gravity: 18, drag: 0.6)
        }
        for _ in 0..<5 {
            let dir = Effects.randomDirection(upward: 2)
            spawn(.smoke, at: center + dir * 0.3, velocity: SIMD3(dir.x * 0.8, Float.random(in: 1.2...2.2), dir.z * 0.8),
                  life: Float.random(in: 0.8...1.3), size: (0.35, 1.1), gravity: 0, drag: 1.2)
        }
    }

    /// A smaller burst where a bolt hits but doesn't break anything.
    func spark(at point: SIMD3<Float>) {
        spawn(.flash, at: point, velocity: .zero, life: 0.06, size: (0.3, 0.8), gravity: 0, drag: 0)
        for _ in 0..<5 {
            let dir = Effects.randomDirection(upward: 0.5)
            spawn(.ember, at: point, velocity: dir * Float.random(in: 4...8), life: 0.3, size: (0.07, 0.02), gravity: 9, drag: 1)
        }
    }

    func clear() {
        for p in particles { recycle(p.entity) }
        particles.removeAll()
        for b in bolts { b.entity.removeFromParent() }
        bolts.removeAll()
    }

    // MARK: Every frame

    func update(dt: Float) {
        // Bolts fly; when one arrives it bursts and does its job.
        var arrived: [Bolt] = []
        for i in bolts.indices.reversed() {
            let step = bolts[i].speed * dt
            let toTarget = bolts[i].target - bolts[i].position
            let remaining = simd_length(toTarget)
            if remaining <= step {
                arrived.append(bolts[i])
                bolts[i].entity.removeFromParent()
                bolts.remove(at: i)
            } else {
                bolts[i].position += toTarget / remaining * step
                bolts[i].entity.position = bolts[i].position
            }
        }
        for bolt in arrived { bolt.onHit() }

        for i in particles.indices.reversed() {
            var p = particles[i]
            p.age += dt
            if p.age >= p.life {
                recycle(p.entity)
                particles.remove(at: i)
                continue
            }
            let t = p.age / p.life
            p.velocity.y -= p.gravity * dt
            p.velocity *= max(0, 1 - p.drag * dt)
            p.entity.position += p.velocity * dt
            let size = p.startSize + (p.endSize - p.startSize) * Effects.ease(t, p.kind)
            p.entity.scale = SIMD3<Float>(repeating: max(0.001, size))
            if case .debris = p.kind {
                p.entity.orientation = simd_quatf(angle: p.age * 9, axis: simd_normalize(p.spin))
            }
            let stage = Effects.stage(t, p.kind)
            if stage != p.stage {
                p.stage = stage
                p.entity.model?.materials = [materialFor(p.kind, stage: stage)]
            }
            particles[i] = p
        }
    }

    // MARK: Helpers

    private func spawn(_ kind: Kind, at point: SIMD3<Float>, velocity: SIMD3<Float>, life: Float, size: (Float, Float), gravity: Float, drag: Float) {
        guard particles.count < Effects.maxParticles else { return }
        let entity = pool.popLast() ?? ModelEntity(mesh: cube, materials: [])
        entity.position = point
        entity.scale = SIMD3<Float>(repeating: size.0)
        entity.orientation = simd_quatf(angle: Float.random(in: 0...6), axis: simd_normalize(Effects.randomDirection(upward: 0)))
        entity.model?.materials = [materialFor(kind, stage: 0)]
        entity.isEnabled = true
        if entity.parent == nil { root.addChild(entity) }
        particles.append(Particle(entity: entity, velocity: velocity, life: life, startSize: size.0, endSize: size.1,
                                  gravity: gravity, drag: drag, kind: kind, stage: 0, spin: Effects.randomDirection(upward: 0)))
    }

    private func recycle(_ entity: ModelEntity) {
        entity.isEnabled = false
        pool.append(entity)
    }

    private static func stage(_ t: Float, _ kind: Kind) -> Int {
        switch kind {
        case .flame: return min(4, Int(t * 5))
        case .ember: return min(2, Int(t * 3))
        case .smoke: return min(2, Int(t * 3))
        case .flash, .debris: return 0
        }
    }

    private static func ease(_ t: Float, _ kind: Kind) -> Float {
        switch kind {
        case .flash: return t
        case .smoke: return 1 - (1 - t) * (1 - t)
        default: return t * t
        }
    }

    private func materialFor(_ kind: Kind, stage: Int) -> UnlitMaterial {
        switch kind {
        case .flash: return material(SIMD3(1, 0.98, 0.9), opacity: 0.85)
        case .flame: return material(Effects.fire[stage], opacity: stage < 3 ? 1 : 0.8)
        case .ember: return material(Effects.fire[min(stage + 1, 4)], opacity: 1)
        case .debris(let c): return material(c, opacity: 1)
        case .smoke: return material(SIMD3(0.3, 0.28, 0.3), opacity: [0.55, 0.38, 0.18][stage])
        }
    }

    private func material(_ c: SIMD3<Float>, opacity: Float) -> UnlitMaterial {
        let key = String(format: "%.2f,%.2f,%.2f,%.2f", c.x, c.y, c.z, opacity)
        if let cached = materials[key] { return cached }
        var m = UnlitMaterial(color: PlatformColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1))
        if opacity < 1 { m.blending = .transparent(opacity: .init(floatLiteral: opacity)) }
        materials[key] = m
        return m
    }

    private static func randomDirection(upward: Float) -> SIMD3<Float> {
        var d = SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1) + upward, Float.random(in: -1...1))
        if simd_length(d) < 0.01 { d = SIMD3(0, 1, 0) }
        return simd_normalize(d)
    }
}
