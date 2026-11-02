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
        /// Waits a moment before letting go, so a building comes apart bit by bit.
        var delay: Float = 0
    }

    /// Where a piece came down, and its blocks where they landed (to stack them up).
    struct Landing {
        let point: SIMD3<Float>
        let blocks: [(position: SIMD3<Float>, id: UInt8)]
        let radius: Float
    }

    private(set) var pieces: [Piece] = []
    /// Cells waiting to be checked, and how much checking is allowed each frame.
    private var queue: [SIMD3<Int>] = []
    private var queued = Set<SIMD3<Int>>()
    static let maxPieceBlocks = 2500
    /// Bits falling at once; anything over this lands straight away.
    static let maxFalling = 500
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

    private var cubes: [UInt8: MeshResource] = [:]

    /// A loose piece breaks apart: single blocks (or little clumps, for big pieces) that each
    /// fall and tumble on their own. Returns blocks that didn't fit and should land right away.
    func drop(_ blocks: [(SIMD3<Int>, UInt8)], material: UnlitMaterial?, push: SIMD3<Float>) -> [(SIMD3<Int>, UInt8)] {
        guard let material, !blocks.isEmpty else { return blocks }
        let size = blocks.count <= 300 ? 1 : (blocks.count <= 2400 ? 2 : 3)
        var groups: [SIMD3<Int>: [(SIMD3<Int>, UInt8)]] = [:]
        var top = Int.min
        for (p, id) in blocks {
            let g = SIMD3<Int>(floorDiv(p.x, size), floorDiv(p.y, size), floorDiv(p.z, size))
            groups[g, default: []].append((p, id))
            top = max(top, p.y)
        }
        var leftover: [(SIMD3<Int>, UInt8)] = []
        for (_, group) in groups {
            guard pieces.count < FallingBlocks.maxFalling else {
                leftover += group
                continue
            }
            let center = group.reduce(SIMD3<Float>(repeating: 0)) { $0 + SIMD3<Float>($1.0) } / Float(group.count) + 0.5
            let mesh: MeshResource?
            if group.count == 1 {
                mesh = cube(group[0].1)
            } else {
                var cells: [SIMD3<Int>: UInt8] = [:]
                for (p, id) in group { cells[p] = id }
                var builder = MeshBuilder()
                for (p, id) in group {
                    for (faceIndex, face) in VoxelMesher.faces.enumerated() where cells[p &+ face.dir] == nil {
                        builder.addFace(face, at: SIMD3<Float>(p) - center, rect: BlockTextures.rect(id: id, face: faceIndex))
                    }
                }
                mesh = try? builder.mesh(name: "falling")
            }
            guard let mesh else {
                leftover += group
                continue
            }
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.position = center
            root.addChild(entity)
            let spread = SIMD3<Float>(Float.random(in: -1.4...1.4), Float.random(in: 0...1.2), Float.random(in: -1.4...1.4))
            let axis = simd_normalize(SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -0.4...0.4), Float.random(in: -1...1)) + SIMD3(0.01, 0, 0))
            // Not all at once: it comes apart bit by bit.
            let delay = Float.random(in: 0...0.2)
            pieces.append(Piece(entity: entity, blocks: group.map { (SIMD3<Float>($0.0) + 0.5 - center, $0.1) },
                                position: center, velocity: push * 0.6 + spread, spinAxis: axis,
                                spinSpeed: Float.random(in: 1.5...5) / Float(size),
                                radius: Float(size) * 0.6, halfHeight: Float(size) * 0.5, delay: delay))
        }
        return leftover
    }

    /// A unit cube for one kind of block, made once.
    private func cube(_ id: UInt8) -> MeshResource? {
        if let mesh = cubes[id] { return mesh }
        var builder = MeshBuilder()
        for (faceIndex, face) in VoxelMesher.faces.enumerated() {
            builder.addFace(face, at: SIMD3<Float>(-0.5, -0.5, -0.5), rect: BlockTextures.rect(id: id, face: faceIndex))
        }
        let mesh = try? builder.mesh(name: "cube-\(id)")
        cubes[id] = mesh
        return mesh
    }

    func update(dt: Float, world: World, gravity: Float) -> [Landing] {
        var landings: [Landing] = []
        for i in pieces.indices.reversed() {
            var p = pieces[i]
            if p.delay > 0 {
                p.delay -= dt
                pieces[i] = p
                continue
            }
            p.age += dt
            p.velocity.y -= gravity * dt
            p.velocity.y = max(p.velocity.y, -40)
            p.velocity.x *= max(0, 1 - dt * 0.4)
            p.velocity.z *= max(0, 1 - dt * 0.4)
            p.position += p.velocity * dt
            p.rotation = simd_quatf(angle: p.spinSpeed * dt, axis: p.spinAxis) * p.rotation
            p.entity.position = p.position
            p.entity.orientation = p.rotation
            let x = Int(floor(p.position.x)), z = Int(floor(p.position.z))
            let ground = Float(world.surfaceY(x: x, z: z))
            if p.position.y - p.halfHeight <= ground || p.age > 12 {
                p.entity.removeFromParent()
                pieces.remove(at: i)
                // Land the blocks flat (no tilt), wherever they fell.
                let blocks = p.blocks.map { (SIMD3(p.position.x + $0.offset.x, ground, p.position.z + $0.offset.z), $0.id) }
                landings.append(Landing(point: SIMD3(p.position.x, ground, p.position.z), blocks: blocks, radius: p.radius))
                continue
            }
            pieces[i] = p
        }
        return landings
    }

    private static let directions = [SIMD3<Int>(1, 0, 0), SIMD3(-1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, -1, 0), SIMD3(0, 0, 1), SIMD3(0, 0, -1)]
}
