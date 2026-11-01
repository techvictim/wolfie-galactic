import Foundation
import RealityKit
import simd

/// Pieces of buildings (or anything) left hanging with nothing holding them up. Each piece
/// falls as one, tumbling, and crumbles into rubble where it lands.
@MainActor
final class FallingBlocks {
    let root = Entity()

    struct Piece {
        let entity: ModelEntity
        /// The blocks, relative to the piece's centre.
        let blocks: [(offset: SIMD3<Float>, id: UInt8)]
        var position: SIMD3<Float>
        var velocity: SIMD3<Float>
        var spinAxis: SIMD3<Float>
        var spinSpeed: Float
        var rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        let radius: Float
        let halfHeight: Float
        var age: Float = 0
    }

    /// Where a piece came down.
    struct Landing {
        let point: SIMD3<Float>
        let blocks: [UInt8]
        let radius: Float
    }

    private(set) var pieces: [Piece] = []
    /// Cells waiting to be checked, and how much checking is allowed each frame.
    private var queue: [SIMD3<Int>] = []
    private var queued = Set<SIMD3<Int>>()
    static let maxPieceBlocks = 2500
    static let maxFalling = 12
    private static let budget = 40_000

    var isEmpty: Bool { pieces.isEmpty && queue.isEmpty }

    func clear() {
        for p in pieces { p.entity.removeFromParent() }
        pieces.removeAll()
        queue.removeAll()
        queued.removeAll()
    }

    // MARK: Finding loose pieces

    /// Blocks just became air: their neighbours might have lost their support.
    func note(_ cells: [SIMD3<Int>]) {
        for c in cells {
            for d in FallingBlocks.directions {
                let n = c &+ d
                if queued.insert(n).inserted { queue.append(n) }
            }
        }
        if queue.count > 30_000 {
            queue.removeFirst(queue.count - 30_000)
        }
    }

    /// Check some of the waiting cells. Returns pieces that should fall: their blocks have been
    /// taken out of the world already.
    func findLoose(in world: World) -> [[(SIMD3<Int>, UInt8)]] {
        var found: [[(SIMD3<Int>, UInt8)]] = []
        var work = 0
        var checked = Set<SIMD3<Int>>()
        while work < FallingBlocks.budget, let seed = queue.popLast() {
            queued.remove(seed)
            if checked.contains(seed) || world.block(seed) == B.air { continue }
            // Flood out from the seed. Touching the bottom of the world, unloaded land, or
            // growing very big means it's held up (it's part of the ground).
            var piece: [SIMD3<Int>] = []
            var seen: Set<SIMD3<Int>> = [seed]
            var stack = [seed]
            var supported = false
            while let p = stack.popLast() {
                work += 1
                piece.append(p)
                if p.y <= 1 || piece.count > FallingBlocks.maxPieceBlocks || world.cachedChunk(World.key(x: p.x, z: p.z)) == nil {
                    supported = true
                    break
                }
                for d in FallingBlocks.directions {
                    let q = p &+ d
                    if seen.contains(q) || q.y >= World.height { continue }
                    if world.block(q) != B.air {
                        seen.insert(q)
                        stack.append(q)
                    }
                }
            }
            checked.formUnion(seen)
            guard !supported, !piece.isEmpty else { continue }
            var blocks: [(SIMD3<Int>, UInt8)] = []
            for p in piece {
                blocks.append((p, world.block(p)))
            }
            for (p, _) in blocks { world.set(p, B.air) }
            found.append(blocks)
        }
        return found
    }

    // MARK: Falling

    /// Start a loose piece falling. material: the blocks' material.
    func drop(_ blocks: [(SIMD3<Int>, UInt8)], material: UnlitMaterial?, push: SIMD3<Float>) -> Bool {
        guard pieces.count < FallingBlocks.maxFalling, let material, !blocks.isEmpty else { return false }
        var lo = blocks[0].0, hi = blocks[0].0
        for (p, _) in blocks {
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        let center = (SIMD3<Float>(lo) + SIMD3<Float>(hi &+ 1)) / 2
        var cells: [SIMD3<Int>: UInt8] = [:]
        for (p, id) in blocks { cells[p] = id }
        var builder = MeshBuilder()
        for (p, id) in blocks {
            for (faceIndex, face) in VoxelMesher.faces.enumerated() where cells[p &+ face.dir] == nil {
                builder.addFace(face, at: SIMD3<Float>(p) - center, rect: BlockTextures.rect(id: id, face: faceIndex))
            }
        }
        guard let mesh = try? builder.mesh(name: "falling") else { return false }
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = center
        root.addChild(entity)
        let size = SIMD3<Float>(hi &- lo) + 1
        // Bigger pieces turn more slowly.
        let seed = Float((lo.x &* 31 &+ lo.y &* 17 &+ lo.z &* 7) & 1023) / 1023
        let axis = simd_normalize(SIMD3<Float>(cos(seed * 6.28), 0.3, sin(seed * 6.28)))
        pieces.append(Piece(entity: entity, blocks: blocks.map { (SIMD3<Float>($0.0) + 0.5 - center, $0.1) },
                            position: center, velocity: push, spinAxis: axis,
                            spinSpeed: (0.6 + seed * 0.9) * min(1, 6 / max(size.x, size.z)),
                            radius: max(size.x, size.z) / 2, halfHeight: size.y / 2))
        return true
    }

    func update(dt: Float, world: World, gravity: Float) -> [Landing] {
        var landings: [Landing] = []
        for i in pieces.indices.reversed() {
            var p = pieces[i]
            p.age += dt
            p.velocity.y -= gravity * dt
            p.velocity.y = max(p.velocity.y, -40)
            p.position += p.velocity * dt
            p.rotation = simd_quatf(angle: p.spinSpeed * dt, axis: p.spinAxis) * p.rotation
            p.entity.position = p.position
            p.entity.orientation = p.rotation
            // The ground under it: the highest of a few spots across its footprint.
            var ground: Float = 0
            let r = max(0.5, p.radius * 0.6)
            for (dx, dz) in [(Float(0), Float(0)), (r, 0), (-r, 0), (0, r), (0, -r)] {
                let x = Int(floor(p.position.x + dx)), z = Int(floor(p.position.z + dz))
                ground = max(ground, Float(world.surfaceY(x: x, z: z)))
            }
            // Tilted pieces reach a bit lower.
            let reach = p.halfHeight * 0.8 + p.radius * 0.3
            if p.position.y - reach <= ground || p.age > 12 {
                p.entity.removeFromParent()
                pieces.remove(at: i)
                landings.append(Landing(point: SIMD3(p.position.x, ground, p.position.z), blocks: p.blocks.map(\.id), radius: p.radius))
                continue
            }
            pieces[i] = p
        }
        return landings
    }

    private static let directions = [SIMD3<Int>(1, 0, 0), SIMD3(-1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, -1, 0), SIMD3(0, 0, 1), SIMD3(0, 0, -1)]
}
