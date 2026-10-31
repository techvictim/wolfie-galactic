import Foundation
import RealityKit
import simd

struct VoxelFace: Sendable {
    let dir: SIMD3<Int>
    let normal: SIMD3<Float>
    /// Four corners of a unit cube face, wound counter-clockwise seen from outside.
    let corners: [SIMD3<Float>]
}

/// Collects quads and turns them into a RealityKit mesh.
struct MeshBuilder: Sendable {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []

    var isEmpty: Bool { indices.isEmpty }

    mutating func addFace(_ face: VoxelFace, at origin: SIMD3<Float>, u: Float, size: Float = 1) {
        addBox(face, at: origin, size: SIMD3<Float>(repeating: size), u: u)
    }

    /// One face of a box of any size.
    mutating func addBox(_ face: VoxelFace, at origin: SIMD3<Float>, size: SIMD3<Float>, u: Float) {
        let base = UInt32(positions.count)
        for corner in face.corners {
            positions.append(origin + corner * size)
            normals.append(face.normal)
            uvs.append(SIMD2<Float>(u, 0.5))
        }
        indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
    }

    @MainActor
    func mesh(name: String) throws -> MeshResource? {
        guard !isEmpty else { return nil }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}

/// Builds meshes that only include the block faces you can see.
enum VoxelMesher {
    static let faces: [VoxelFace] = {
        let raw: [(SIMD3<Int>, [SIMD3<Float>])] = [
            (SIMD3<Int>(1, 0, 0), [SIMD3<Float>(1, 0, 0), SIMD3<Float>(1, 1, 0), SIMD3<Float>(1, 1, 1), SIMD3<Float>(1, 0, 1)]),
            (SIMD3<Int>(-1, 0, 0), [SIMD3<Float>(0, 0, 0), SIMD3<Float>(0, 0, 1), SIMD3<Float>(0, 1, 1), SIMD3<Float>(0, 1, 0)]),
            (SIMD3<Int>(0, 1, 0), [SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 1, 1), SIMD3<Float>(1, 1, 1), SIMD3<Float>(1, 1, 0)]),
            (SIMD3<Int>(0, -1, 0), [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(1, 0, 1), SIMD3<Float>(0, 0, 1)]),
            (SIMD3<Int>(0, 0, 1), [SIMD3<Float>(0, 0, 1), SIMD3<Float>(1, 0, 1), SIMD3<Float>(1, 1, 1), SIMD3<Float>(0, 1, 1)]),
            (SIMD3<Int>(0, 0, -1), [SIMD3<Float>(0, 0, 0), SIMD3<Float>(0, 1, 0), SIMD3<Float>(1, 1, 0), SIMD3<Float>(1, 0, 0)])
        ]
        return raw.map { entry in
            let dir = entry.0
            let c = entry.1
            let normal = SIMD3<Float>(Float(dir.x), Float(dir.y), Float(dir.z))
            let cross = simd_cross(c[1] - c[0], c[2] - c[0])
            let corners = simd_dot(cross, normal) >= 0 ? c : [c[0], c[3], c[2], c[1]]
            return VoxelFace(dir: dir, normal: normal, corners: corners)
        }
    }()

    /// Mesh for one chunk, in the chunk's local coordinates (1 unit = 1 big block).
    /// The four side neighbours decide which faces on the chunk's edges can be seen.
    static func chunk(_ c: [UInt8], east: [UInt8], west: [UInt8], south: [UInt8], north: [UInt8]) -> MeshBuilder {
        var builder = MeshBuilder()
        let s = World.chunkSize
        let paletteCount = BlockRegistry.maxBlocks

        // Skip the empty sky above the tallest block.
        var top = World.height
        let layer = s * s
        while top > 0 {
            let start = (top - 1) * layer
            if c[start..<(start + layer)].contains(where: { $0 != B.air }) { break }
            top -= 1
        }

        @inline(__always)
        func at(_ lx: Int, _ y: Int, _ lz: Int) -> UInt8 {
            if y < 0 { return 1 }
            if y >= World.height { return B.air }
            if lx < 0 { return west[TerrainGenerator.index(s - 1, y, lz)] }
            if lx >= s { return east[TerrainGenerator.index(0, y, lz)] }
            if lz < 0 { return north[TerrainGenerator.index(lx, y, s - 1)] }
            if lz >= s { return south[TerrainGenerator.index(lx, y, 0)] }
            return c[TerrainGenerator.index(lx, y, lz)]
        }

        for y in 0..<top {
            for lz in 0..<s {
                for lx in 0..<s {
                    let id = c[TerrainGenerator.index(lx, y, lz)]
                    if id == B.air { continue }
                    for (faceIndex, face) in faces.enumerated() {
                        if at(lx + face.dir.x, y + face.dir.y, lz + face.dir.z) != B.air { continue }
                        builder.addFace(
                            face,
                            at: SIMD3<Float>(Float(lx), Float(y), Float(lz)),
                            u: PaletteTexture.u(index: Int(id), face: faceIndex, count: paletteCount)
                        )
                    }
                }
            }
        }
        return builder
    }
}

/// A square of far-away land, 8 x 8 chunks, drawn simply: columns 4 blocks wide.
struct TileKey: Hashable, Sendable {
    var x: Int
    var z: Int

    static let chunks = 8
    static let blocks = chunks * World.chunkSize

    static func containing(_ chunk: ChunkKey) -> TileKey {
        TileKey(x: floorDiv(chunk.x, chunks), z: floorDiv(chunk.z, chunks))
    }
}

/// Builds the simple far-away terrain. Columns where detailed chunks are shown are left out.
enum FarMesher {
    static let cell = 4

    static func tile(_ tile: TileKey, generator: TerrainGenerator, skipping detailed: Set<ChunkKey>) -> MeshBuilder {
        var builder = MeshBuilder()
        let cells = TileKey.blocks / cell
        let x0 = tile.x * TileKey.blocks
        let z0 = tile.z * TileKey.blocks
        let paletteCount = BlockRegistry.maxBlocks
        let sink: Float = 0.35   // sit a little below the real ground, so near land always covers it

        // Heights for every cell plus a border of one cell.
        let span = cells + 2
        var heights = [Int](repeating: 0, count: span * span)
        var tops = [UInt8](repeating: 0, count: span * span)
        for j in 0..<span {
            for i in 0..<span {
                let x = x0 + (i - 1) * cell + cell / 2
                let z = z0 + (j - 1) * cell + cell / 2
                let h = generator.height(x, z)
                // Buildings show on the horizon as tall blocks in their colour.
                if let building = generator.farTop(x, z), building.height > h {
                    heights[j * span + i] = building.height
                    tops[j * span + i] = building.block
                } else {
                    heights[j * span + i] = h
                    tops[j * span + i] = generator.surfaceBlock(height: h)
                }
            }
        }

        let faces = VoxelMesher.faces
        let up = faces[2]
        let sides: [(face: VoxelFace, faceIndex: Int, di: Int, dj: Int)] = [
            (faces[0], 0, 1, 0), (faces[1], 1, -1, 0), (faces[4], 4, 0, 1), (faces[5], 5, 0, -1)
        ]
        let size = Float(cell)
        for j in 0..<cells {
            for i in 0..<cells {
                let bx = x0 + i * cell
                let bz = z0 + j * cell
                if detailed.contains(World.key(x: bx, z: bz)) { continue }
                let h = heights[(j + 1) * span + (i + 1)]
                let id = Int(tops[(j + 1) * span + (i + 1)])
                let topY = Float(h) - sink
                let origin = SIMD3<Float>(Float(i * cell), 0, Float(j * cell))
                builder.addBox(
                    up,
                    at: SIMD3<Float>(origin.x, topY - 1, origin.z),
                    size: SIMD3<Float>(size, 1, size),
                    u: PaletteTexture.u(index: id, face: 2, count: paletteCount)
                )
                for side in sides {
                    let hn = heights[(j + 1 + side.dj) * span + (i + 1 + side.di)]
                    guard hn < h else { continue }
                    let bottom = Float(hn) - sink
                    builder.addBox(
                        side.face,
                        at: SIMD3<Float>(origin.x, bottom, origin.z),
                        size: SIMD3<Float>(size, topY - bottom, size),
                        u: PaletteTexture.u(index: id, face: side.faceIndex, count: paletteCount)
                    )
                }
            }
        }
        return builder
    }
}
