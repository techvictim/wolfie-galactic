import CoreGraphics
import Foundation
import ImageIO
import RealityKit
import simd

/// Minecraft-style block textures: Resources/block-textures.png has a 16 x 16 tile for the top,
/// sides and bottom of every block (Tools/make_block_textures.py). The game stacks six copies of
/// it, each lit for one face direction, so blocks keep their soft toy shading with no real lights.
enum BlockTextures {
    static let tile = 16
    static let columns = 16
    static let rows = 12
    static let width = tile * columns
    static let height = tile * rows
    static let shades = 6

    /// Glitch blocks are see-through.
    nonisolated static func isGlass(_ id: UInt8) -> Bool {
        id == 35 || id == 36
    }

    /// 0 top, 1 side, 2 bottom, for a face in VoxelMesher.faces order.
    nonisolated static func kind(face: Int) -> Int {
        face == 2 ? 0 : (face == 3 ? 2 : 1)
    }

    /// The texture rectangle for a block's face: (u0, v0, u1, v1), v0 at the bottom.
    nonisolated static func rect(id: UInt8, face: Int) -> SIMD4<Float> {
        let index = Int(id) * 3 + kind(face: face)
        let col = index % columns
        let row = index / columns
        let w = Float(width)
        let h = Float(height * shades)
        // A hair inside the tile so neighbours never bleed in.
        let x0 = Float(col * tile) + 0.02
        let x1 = Float((col + 1) * tile) - 0.02
        let top = Float(face * height + row * tile) + 0.02
        let bottom = Float(face * height + (row + 1) * tile) - 0.02
        return SIMD4(x0 / w, 1 - bottom / h, x1 / w, 1 - top / h)
    }

    @MainActor static func makeTexture() -> TextureResource? {
        guard let url = Bundle.main.url(forResource: "block-textures", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let w = width, h = height
        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        var out = [UInt8](repeating: 255, count: w * h * shades * 4)
        let lift = FaceShade.lift
        for s in 0..<shades {
            let k = s < FaceShade.values.count ? FaceShade.values[s] : 1
            for i in 0..<(w * h) {
                let o = (s * w * h + i) * 4
                for c in 0..<3 {
                    let base = Float(pixels[i * 4 + c]) / 255
                    let lifted = base + (1 - base) * lift
                    out[o + c] = UInt8(min(1, max(0, lifted * k)) * 255)
                }
                out[o + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(out) as CFData),
              let atlas = CGImage(width: w, height: h * shades, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
                                  decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return try? TextureResource(image: atlas, withName: nil, options: TextureResource.CreateOptions(semantic: .color, mipmapsMode: .none))
    }

    /// See-through blocks: the same texture, partly transparent.
    @MainActor static func glassMaterial(_ texture: TextureResource, opacity: Float) -> UnlitMaterial {
        var m = PaletteTexture.material(texture)
        m.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return m
    }
}
