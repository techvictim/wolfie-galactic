import Foundation
import RealityKit
import simd

/// A detail model: small voxels, 4 per big-block edge.
/// Made in MagicaVoxel (or any editor that saves .vox) and dropped into Resources.
struct VoxModel {
    /// Size in small voxels, in game axes (y is up).
    let size: SIMD3<Int>
    let voxels: [SIMD3<Int>: UInt8]
    /// 256 colours; index 0 is unused.
    let palette: [SIMD3<Float>]
}

enum VoxLoader {
    /// Reads the first model and the palette from a MagicaVoxel .vox file.
    static func load(_ data: Data) -> VoxModel? {
        let bytes = [UInt8](data)
        guard bytes.count >= 20, String(bytes: bytes[0..<4], encoding: .ascii) == "VOX " else { return nil }

        func u32(_ o: Int) -> Int {
            Int(bytes[o]) | (Int(bytes[o + 1]) << 8) | (Int(bytes[o + 2]) << 16) | (Int(bytes[o + 3]) << 24)
        }
        func tag(_ o: Int) -> String {
            String(bytes: bytes[o..<(o + 4)], encoding: .ascii) ?? ""
        }

        guard tag(8) == "MAIN" else { return nil }
        var offset = 8 + 12 + u32(12)
        var voxSize = SIMD3<Int>(0, 0, 0)
        var raw: [(Int, Int, Int, UInt8)] = []
        var palette = [SIMD3<Float>](repeating: SIMD3<Float>(0.7, 0.7, 0.7), count: 256)
        var haveModel = false

        while offset + 12 <= bytes.count {
            let id = tag(offset)
            let contentSize = u32(offset + 4)
            let childrenSize = u32(offset + 8)
            let c = offset + 12
            guard c + contentSize <= bytes.count else { break }
            switch id {
            case "SIZE":
                if !haveModel { voxSize = SIMD3<Int>(u32(c), u32(c + 4), u32(c + 8)) }
            case "XYZI":
                if !haveModel {
                    let count = u32(c)
                    for i in 0..<count {
                        let p = c + 4 + i * 4
                        guard p + 3 < bytes.count else { break }
                        raw.append((Int(bytes[p]), Int(bytes[p + 1]), Int(bytes[p + 2]), bytes[p + 3]))
                    }
                    haveModel = true
                }
            case "RGBA":
                for i in 0..<255 {
                    let p = c + i * 4
                    palette[i + 1] = SIMD3<Float>(Float(bytes[p]) / 255, Float(bytes[p + 1]) / 255, Float(bytes[p + 2]) / 255)
                }
            default:
                break
            }
            offset = c + contentSize + childrenSize
        }
        guard haveModel else { return nil }

        // MagicaVoxel uses z-up; the game uses y-up.
        var voxels: [SIMD3<Int>: UInt8] = [:]
        for (vx, vy, vz, color) in raw {
            voxels[SIMD3<Int>(vx, vz, voxSize.y - 1 - vy)] = color
        }
        return VoxModel(size: SIMD3<Int>(voxSize.x, voxSize.z, voxSize.y), voxels: voxels, palette: palette)
    }
}

@MainActor
enum DetailModels {
    static let voxelsPerBlock: Float = 4

    /// A model's size in small voxels (x, y up, z), without building it.
    static func size(named name: String) -> SIMD3<Int>? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "vox"),
              let data = try? Data(contentsOf: url),
              let model = VoxLoader.load(data) else { return nil }
        return model.size
    }

    /// Builds an entity for Resources/<name>.vox. Its origin is the bottom centre,
    /// so placing it at a block corner snaps it to the big-block grid.
    static func entity(named name: String) -> ModelEntity? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "vox"),
              let data = try? Data(contentsOf: url),
              let model = VoxLoader.load(data) else { return nil }

        var builder = MeshBuilder()
        let offset = SIMD3<Float>(Float(model.size.x) / 2, 0, Float(model.size.z) / 2)
        for (p, color) in model.voxels {
            for (faceIndex, face) in VoxelMesher.faces.enumerated() where model.voxels[p &+ face.dir] == nil {
                builder.addFace(
                    face,
                    at: SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z)) - offset,
                    u: PaletteTexture.u(index: Int(color), face: faceIndex, count: 256)
                )
            }
        }
        guard let mesh = try? builder.mesh(name: name),
              let texture = PaletteTexture.make(colors: model.palette) else { return nil }
        let entity = ModelEntity(mesh: mesh, materials: [PaletteTexture.material(texture)])
        entity.scale = SIMD3<Float>(repeating: 1 / voxelsPerBlock)
        entity.name = name
        return entity
    }
}
