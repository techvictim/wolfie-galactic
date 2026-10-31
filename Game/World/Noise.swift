import Foundation

/// Small, deterministic value noise used for terrain.
struct Noise: Sendable {
    let seed: UInt64

    /// A repeatable pseudo-random number in 0...1 for a grid point.
    func hash(_ x: Int, _ z: Int) -> Float {
        var h = (UInt64(bitPattern: Int64(x)) &* 0x9E37_79B9_7F4A_7C15)
        h = h ^ (UInt64(bitPattern: Int64(z)) &* 0xC2B2_AE3D_27D4_EB4F)
        h = h ^ seed
        h ^= h >> 33
        h = h &* 0xFF51_AFD7_ED55_8CCD
        h ^= h >> 33
        h = h &* 0xC4CE_B9FE_1A85_EC53
        h ^= h >> 33
        return Float(h & 0xFF_FFFF) / Float(0xFF_FFFF)
    }

    func value(_ x: Float, _ z: Float) -> Float {
        let x0 = Int(floor(x))
        let z0 = Int(floor(z))
        let fx = x - Float(x0)
        let fz = z - Float(z0)
        let sx = fx * fx * (3 - 2 * fx)
        let sz = fz * fz * (3 - 2 * fz)
        let a = hash(x0, z0)
        let b = hash(x0 + 1, z0)
        let c = hash(x0, z0 + 1)
        let d = hash(x0 + 1, z0 + 1)
        let ab = a + (b - a) * sx
        let cd = c + (d - c) * sx
        return ab + (cd - ab) * sz
    }

    /// Four octaves of value noise, roughly 0...1.
    func fbm(_ x: Float, _ z: Float) -> Float {
        var amplitude: Float = 0.5
        var frequency: Float = 1
        var sum: Float = 0
        for _ in 0..<4 {
            sum += value(x * frequency, z * frequency) * amplitude
            amplitude *= 0.5
            frequency *= 2
        }
        return sum / 0.9375
    }
}
