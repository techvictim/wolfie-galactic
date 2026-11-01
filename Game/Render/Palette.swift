import Foundation
import CoreGraphics
import Metal
import RealityKit
import simd
#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformColor = UIColor
#endif

/// Toy-voxel colouring without real-time lights: every colour is stored once per face
/// direction with a baked brightness, so blocks read clearly on any screen and stay cheap
/// on Apple TV. All voxels share one unlit material that samples this strip.
enum FaceShade {
    /// Brightness per face, in VoxelMesher.faces order: +x, -x, +y, -y, +z, -z.
    static let values: [Float] = [0.86, 0.72, 1.0, 0.55, 0.93, 0.78]
    /// Texels reserved per colour (6 used, padded to 8).
    static let slots = 8
    /// How far colours are lifted toward white for the soft toy look.
    static let lift: Float = 0.08
}

@MainActor
enum PaletteTexture {
    /// A one-pixel-tall strip: for each colour, one texel per face direction.
    static func make(colors: [SIMD3<Float>]) -> TextureResource? {
        guard let image = image(colors: colors) else { return nil }
        return try? TextureResource(
            image: image,
            withName: nil,
            options: TextureResource.CreateOptions(semantic: .color, mipmapsMode: .none)
        )
    }

    /// Change the colours in place, so everything using the texture updates (the Glitch's pulse).
    static func update(_ texture: TextureResource, colors: [SIMD3<Float>]) {
        guard let image = image(colors: colors) else { return }
        try? texture.replace(withImage: image, options: TextureResource.CreateOptions(semantic: .color, mipmapsMode: .none))
    }

    private static func image(colors: [SIMD3<Float>]) -> CGImage? {
        let width = colors.count * FaceShade.slots
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * 4)
        let one = SIMD3<Float>(repeating: 1)
        let zero = SIMD3<Float>(repeating: 0)
        for base in colors {
            let lifted = base + (one - base) * FaceShade.lift
            for slot in 0..<FaceShade.slots {
                let k: Float = slot < FaceShade.values.count ? FaceShade.values[slot] : 1
                let c = simd_clamp(lifted * k, zero, one)
                bytes.append(UInt8(c.x * 255))
                bytes.append(UInt8(c.y * 255))
                bytes.append(UInt8(c.z * 255))
                bytes.append(255)
            }
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                width: width,
                height: 1,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else { return nil }
        return image
    }

    /// Texture coordinate (u) for a colour index and face. v is always 0.5.
    nonisolated static func u(index: Int, face: Int, count: Int) -> Float {
        (Float(index * FaceShade.slots + face) + 0.5) / Float(count * FaceShade.slots)
    }

    static func material(_ texture: TextureResource) -> UnlitMaterial {
        let sampler = MTLSamplerDescriptor()
        sampler.minFilter = .nearest
        sampler.magFilter = .nearest
        sampler.mipFilter = .notMipmapped
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture, sampler: .init(sampler)))
        material.faceCulling = .none
        return material
    }
}
