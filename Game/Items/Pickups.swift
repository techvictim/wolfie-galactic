import Foundation
import RealityKit
import simd

/// Little spinning blocks dropped when you break or blast something. Walk near one and it flies
/// into your backpack. In a vehicle they're pulled in from further away.
@MainActor
final class Pickups {
    let root = Entity()

    private struct Pickup {
        let entity: ModelEntity
        let block: UInt8
        var position: SIMD3<Float>
        var velocity: SIMD3<Float>
        var age: Float = 0
        var pulled = false
        /// Resting on the ground: no need to check the terrain every frame.
        var settled = false
    }

    private var pickups: [Pickup] = []
    private var materials: [UInt8: UnlitMaterial] = [:]
    private let cube = MeshResource.generateBox(size: 0.32)
    private static let maxPickups = 160
    /// Seconds before an uncollected pickup fades away.
    private static let lifetime: Float = 180

    func clear() {
        for p in pickups { p.entity.removeFromParent() }
        pickups.removeAll()
    }

    /// Drop a pickup, popping out of where the block was.
    func drop(_ block: UInt8, at center: SIMD3<Float>) {
        if pickups.count >= Pickups.maxPickups, let oldest = pickups.first {
            oldest.entity.removeFromParent()
            pickups.removeFirst()
        }
        let entity = ModelEntity(mesh: cube, materials: [material(block)])
        entity.position = center
        root.addChild(entity)
        let spread = SIMD3<Float>(Float.random(in: -1.5...1.5), Float.random(in: 2.5...4.5), Float.random(in: -1.5...1.5))
        pickups.append(Pickup(entity: entity, block: block, position: center, velocity: spread))
    }

    /// Move them; returns the blocks collected this frame.
    func update(dt: Float, collector: SIMD3<Float>, reach: Float, world: World, clock: Float) -> [UInt8] {
        var collected: [UInt8] = []
        for i in pickups.indices.reversed() {
            var p = pickups[i]
            p.age += dt
            let toPlayer = collector - p.position
            let distance = simd_length(toPlayer)
            if p.age > 0.35 && distance < reach { p.pulled = true }
            if p.pulled {
                // Zip toward you, faster as it gets close.
                p.position += toPlayer / max(distance, 0.01) * min(distance, dt * (10 + 30 / max(distance, 0.5)))
                if distance < 0.7 {
                    collected.append(p.block)
                    p.entity.removeFromParent()
                    pickups.remove(at: i)
                    continue
                }
            } else if !p.settled {
                // Fall and settle on the ground.
                p.velocity.y -= 18 * dt
                p.velocity.x *= max(0, 1 - dt * 3)
                p.velocity.z *= max(0, 1 - dt * 3)
                var next = p.position + p.velocity * dt
                let floorY = Float(world.surfaceY(x: Int(floor(next.x)), z: Int(floor(next.z))))
                if next.y < floorY + 0.25 && p.position.y >= floorY - 0.5 {
                    next.y = floorY + 0.25
                    p.velocity = .zero
                    p.settled = true
                }
                p.position = next
            }
            if p.age > Pickups.lifetime {
                p.entity.removeFromParent()
                pickups.remove(at: i)
                continue
            }
            let bob = p.pulled ? 0 : sin(clock * 3 + Float(i)) * 0.08
            p.entity.position = p.position + SIMD3<Float>(0, bob, 0)
            p.entity.orientation = simd_quatf(angle: clock * 2 + Float(i), axis: SIMD3<Float>(0, 1, 0))
            pickups[i] = p
        }
        return collected
    }

    private func material(_ block: UInt8) -> UnlitMaterial {
        if let m = materials[block] { return m }
        let c = BlockRegistry.shared.rgb(block)
        let m = UnlitMaterial(color: PlatformColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1))
        materials[block] = m
        return m
    }
}
