import Foundation
import RealityKit
import simd

/// What hangs in a planet's sky: the other planets as their own little voxel models (Wolfie World
/// shows its wolf face), toy-block moons (some with rings), a drifting band of asteroids, and three
/// small far-off suns, a couple of them faint.
@MainActor
enum SkyDecor {
    /// Build the whole sky for a planet. Everything sits around the origin; the sky follows you.
    static func build(for planet: Planet, radius: Float) -> Entity {
        let root = Entity()
        var rng = SeededRandom(seed: planet.seed &+ 77)

        // Other planets and moons from planets.json.
        for body in planet.skyBodies where body.direction.count == 3 {
            let direction = simd_normalize(SIMD3<Float>(body.direction[0], body.direction[1], body.direction[2]))
            let size = body.size * radius / 400
            if let name = body.model, let holder = SpaceScene.ball(name, voxel: 1), let voxels = DetailModels.size(named: name) {
                let across = Float(max(voxels.x, voxels.z)) / DetailModels.voxelsPerBlock
                let wrapper = Entity()
                holder.scale *= 2 * size / max(across, 1)
                wrapper.addChild(holder)
                // Its face looks back at you, tipped a little.
                wrapper.orientation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: -direction)
                    * simd_quatf(angle: 0.25, axis: SIMD3<Float>(1, 0, 0))
                wrapper.position = direction * radius * 0.82
                root.addChild(wrapper)
            } else {
                let sphere = ModelEntity(mesh: .generateSphere(radius: size),
                                         materials: [UnlitMaterial(color: Game.color(BlockRegistry.parseHex(body.color)))])
                sphere.position = direction * radius * 0.82
                root.addChild(sphere)
            }
        }

        // Three small suns: one close and bright, two far away and faint.
        let suns: [(SIMD3<Float>, Float, Float)] = [
            (SIMD3(1, 0.93, 0.75), 0.022, 1),
            (SIMD3(1, 0.62, 0.38), 0.011, 0.6),
            (SIMD3(0.7, 0.85, 1), 0.006, 0.4),
        ]
        for (color, size, brightness) in suns {
            let direction = rng.skyDirection(minUp: 0.25)
            let sun = Entity()
            let r = size * radius
            let core = ModelEntity(mesh: .generateSphere(radius: r), materials: [Shots.material(simd_mix(color, SIMD3(1, 1, 1), SIMD3(repeating: 0.5)), opacity: brightness)])
            let glow = ModelEntity(mesh: .generateSphere(radius: r * 2.4), materials: [Shots.material(color, opacity: 0.22 * brightness)])
            let halo = ModelEntity(mesh: .generateSphere(radius: r * 4.5), materials: [Shots.material(color, opacity: 0.08 * brightness)])
            sun.addChild(halo)
            sun.addChild(glow)
            sun.addChild(core)
            sun.position = direction * radius * 0.9
            root.addChild(sun)
        }

        // Toy-block moons; some have rings.
        let moonColors: [[SIMD3<Float>]] = [
            [SIMD3(0.78, 0.76, 0.84), SIMD3(0.6, 0.58, 0.68), SIMD3(0.45, 0.43, 0.52)],
            [SIMD3(0.9, 0.62, 0.45), SIMD3(0.75, 0.45, 0.32), SIMD3(0.55, 0.32, 0.25)],
            [SIMD3(0.55, 0.75, 0.95), SIMD3(0.4, 0.58, 0.85), SIMD3(0.9, 0.95, 1)],
        ]
        for i in 0..<3 {
            let direction = rng.skyDirection(minUp: 0.15)
            let r = Int(rng.next(in: 4...7))
            guard let moon = ToyMesh.ball(radius: r, colors: moonColors[i % moonColors.count], seed: UInt64(i + 1) &* 977) else { continue }
            let holder = Entity()
            holder.addChild(moon)
            let size = rng.next(in: 28...60)
            holder.scale = SIMD3(repeating: size / Float(r))
            if i != 1 {
                holder.addChild(ToyMesh.ring(inner: Float(r) * 1.5, outer: Float(r) * 2.4, colors: [SIMD3(0.95, 0.85, 0.6), SIMD3(0.8, 0.7, 0.9)], seed: UInt64(i) &+ 5))
            }
            holder.orientation = simd_quatf(angle: rng.next(in: -0.7...0.7), axis: simd_normalize(SIMD3(1, 0, rng.next(in: -1...1))))
            holder.position = direction * radius * 0.8
            root.addChild(holder)
        }

        // A band of asteroids across the sky.
        let bandAxis = simd_normalize(SIMD3<Float>(rng.next(in: -1...1), 1.2, rng.next(in: -1...1)))
        let start = simd_normalize(simd_cross(bandAxis, SIMD3(0, 0, 1)))
        for k in 0..<34 {
            let angle = Float(k) / 34 * .pi * 1.2 + rng.next(in: -0.04...0.04)
            var direction = simd_quatf(angle: angle, axis: bandAxis).act(start)
            direction += SIMD3(rng.next(in: -0.05...0.05), rng.next(in: -0.05...0.05), rng.next(in: -0.05...0.05))
            direction = simd_normalize(direction)
            guard direction.y > 0.05, let rock = ToyMesh.rock(seed: UInt64(k) &+ 31) else { continue }
            let size = rng.next(in: 4...13)
            rock.scale = SIMD3(repeating: size)
            rock.orientation = simd_quatf(angle: rng.next(in: 0...6), axis: simd_normalize(SIMD3(rng.next(in: -1...1), 1, rng.next(in: -1...1))))
            rock.position = direction * radius * 0.78
            root.addChild(rock)
            // Now and then a big one with its own little ring.
            if k % 11 == 4 {
                rock.scale *= 2.2
                rock.addChild(ToyMesh.ring(inner: 1.6, outer: 2.4, colors: [SIMD3(0.7, 0.65, 0.6)], seed: UInt64(k)))
            }
        }
        return root
    }
}

/// Small meshes made of toy blocks, built in code.
@MainActor
enum ToyMesh {
    /// A ball of blocks with a few craters, coloured from the list.
    static func ball(radius r: Int, colors: [SIMD3<Float>], seed: UInt64) -> ModelEntity? {
        var rng = SeededRandom(seed: seed)
        var voxels: [SIMD3<Int>: Int] = [:]
        let rr = Float(r) + 0.4
        for x in -r...r {
            for y in -r...r {
                for z in -r...r where Float(x * x + y * y + z * z) <= rr * rr {
                    let n = sin(Float(x) * 0.9 + Float(seed % 7)) + cos(Float(y) * 0.8 - Float(z) * 0.6)
                    voxels[SIMD3(x, y, z)] = n > 0.7 ? 0 : (n > -0.6 ? 1 : 2)
                }
            }
        }
        // Craters.
        for _ in 0..<4 {
            let d = simd_normalize(SIMD3<Float>(rng.next(in: -1...1), rng.next(in: -1...1), rng.next(in: -1...1))) * Float(r)
            let c = SIMD3<Int>(Int(d.x.rounded()), Int(d.y.rounded()), Int(d.z.rounded()))
            for (p, _) in voxels where simd_length(SIMD3<Float>(p &- c)) < 1.6 { voxels[p] = nil }
        }
        return mesh(voxels, colors: colors, name: "moon-\(seed)")
    }

    /// A lumpy little asteroid, about one unit across.
    static func rock(seed: UInt64) -> ModelEntity? {
        var rng = SeededRandom(seed: seed)
        var voxels: [SIMD3<Int>: Int] = [:]
        for _ in 0..<Int(rng.next(in: 4...9)) {
            let p = SIMD3<Int>(Int(rng.next(in: -1.5...1.5)), Int(rng.next(in: -1...1)), Int(rng.next(in: -1.5...1.5)))
            voxels[p] = Int(rng.next(in: 0...2.99))
        }
        guard let entity = mesh(voxels, colors: [SIMD3(0.5, 0.46, 0.44), SIMD3(0.38, 0.35, 0.36), SIMD3(0.62, 0.55, 0.5)], name: "rock-\(seed)") else { return nil }
        entity.scale = SIMD3(repeating: 0.33)
        let holder = ModelEntity()
        holder.addChild(entity)
        return holder
    }

    /// A flat ring of little blocks around the origin, in the x-z plane, as one mesh.
    static func ring(inner: Float, outer: Float, colors: [SIMD3<Float>], seed: UInt64) -> Entity {
        var rng = SeededRandom(seed: seed)
        // About 24 blocks across the ring's width, whatever its size.
        let step = max(0.05, outer / 24)
        let reach = Int(ceil(outer / step))
        var voxels: [SIMD3<Int>: Int] = [:]
        for x in -reach...reach {
            for z in -reach...reach {
                let d = Float(x * x + z * z).squareRoot() * step
                guard d >= inner, d <= outer, rng.next(in: 0...1) < 0.75 else { continue }
                // Bands of colour.
                let band = Int((d - inner) / (outer - inner) * 4) % max(1, colors.count)
                voxels[SIMD3(x, 0, z)] = band
            }
        }
        guard let ring = mesh(voxels, colors: colors, name: "ring-\(seed)") else { return Entity() }
        ring.scale = SIMD3(step, step * 0.5, step)
        return ring
    }

    private static func mesh(_ voxels: [SIMD3<Int>: Int], colors: [SIMD3<Float>], name: String) -> ModelEntity? {
        guard !voxels.isEmpty, let texture = PaletteTexture.make(colors: colors) else { return nil }
        var builder = MeshBuilder()
        for (p, color) in voxels {
            for (faceIndex, face) in VoxelMesher.faces.enumerated() where voxels[p &+ face.dir] == nil {
                builder.addFace(face, at: SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z)) - 0.5,
                                u: PaletteTexture.u(index: min(color, colors.count - 1), face: faceIndex, count: colors.count))
            }
        }
        guard let mesh = try? builder.mesh(name: name) else { return nil }
        return ModelEntity(mesh: mesh, materials: [PaletteTexture.material(texture)])
    }
}

/// Repeatable random numbers, so each planet's sky is always the same.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func nextBits() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func next(in range: ClosedRange<Float>) -> Float {
        let unit = Float(nextBits() % 1_000_000) / 1_000_000
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }

    /// A direction in the sky, at least this far above the horizon.
    mutating func skyDirection(minUp: Float) -> SIMD3<Float> {
        let a = next(in: 0...(2 * .pi))
        let up = next(in: minUp...0.85)
        let flat = (1 - up * up).squareRoot()
        return SIMD3(cos(a) * flat, up, sin(a) * flat)
    }
}
