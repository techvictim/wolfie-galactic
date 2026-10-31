import Foundation
import simd

/// Which 16 x 16 column of blocks a chunk covers.
struct ChunkKey: Hashable, Sendable {
    var x: Int
    var z: Int
}

/// Division that rounds toward minus infinity, so negative coordinates land in the right chunk.
@inline(__always)
func floorDiv(_ a: Int, _ b: Int) -> Int {
    a >= 0 ? a / b : -((-a + b - 1) / b)
}

@inline(__always)
func floorMod(_ a: Int, _ b: Int) -> Int {
    a - floorDiv(a, b) * b
}

/// Builds any chunk of a planet from its seed, so worlds go on forever in every direction.
/// The same coordinates always give the same blocks, so only the chunks players change need saving.
struct TerrainGenerator: Sendable {
    let planet: Planet
    let noise: Noise
    let padHeight: Int

    /// You start here; the starship's landing pad is just to the west.
    static let spawn = SIMD2<Int>(0, 0)
    static let pad = SIMD2<Int>(-13, 3)

    init(planet: Planet) {
        self.planet = planet
        self.noise = Noise(seed: planet.seed)
        let t = planet.terrain
        let raw = Float(t.base) + noise.fbm(Float(TerrainGenerator.pad.x) * t.frequency, Float(TerrainGenerator.pad.y) * t.frequency) * t.amplitude
        self.padHeight = max(3, min(World.height - 20, Int(raw.rounded())))
    }

    // MARK: Height

    private func baseHeight(_ x: Int, _ z: Int) -> Float {
        let t = planet.terrain
        return Float(t.base) + noise.fbm(Float(x) * t.frequency, Float(z) * t.frequency) * t.amplitude
    }

    private static let craterCell = 24

    /// How much craters raise or lower this column.
    private func craterOffset(_ x: Int, _ z: Int) -> Float {
        let chance = planet.features.craters
        guard chance > 0 else { return 0 }
        let cell = TerrainGenerator.craterCell
        let cx = floorDiv(x, cell)
        let cz = floorDiv(z, cell)
        var offset: Float = 0
        for gz in (cz - 1)...(cz + 1) {
            for gx in (cx - 1)...(cx + 1) {
                guard noise.hash(gx &* 31 &+ 7, gz &* 17 &+ 11) < chance else { continue }
                let centerX = Float(gx * cell) + noise.hash(gx, gz &+ 50) * Float(cell)
                let centerZ = Float(gz * cell) + noise.hash(gx &+ 50, gz) * Float(cell)
                let radius = 4 + noise.hash(gx &+ 9, gz &+ 9) * 6
                let depth = radius * 0.55
                let spawnDistance = simd_distance(SIMD2<Float>(centerX, centerZ), SIMD2<Float>(Float(TerrainGenerator.spawn.x), Float(TerrainGenerator.spawn.y)))
                let padDistance = simd_distance(SIMD2<Float>(centerX, centerZ), SIMD2<Float>(Float(TerrainGenerator.pad.x), Float(TerrainGenerator.pad.y)))
                if spawnDistance < radius + 8 || padDistance < radius + 10 { continue }
                let d = simd_distance(SIMD2<Float>(Float(x), Float(z)), SIMD2<Float>(centerX, centerZ))
                if d < radius {
                    let k = d / radius
                    offset -= depth * (1 - k * k)
                } else if d < radius * 1.3 {
                    offset += depth * 0.3 * (1 - (d - radius) / (radius * 0.3))
                }
            }
        }
        return offset
    }

    /// Ground height: the first empty block above the terrain in this column.
    func height(_ x: Int, _ z: Int) -> Int {
        var h = baseHeight(x, z) + craterOffset(x, z)
        // Cities and bases sit on flat ground.
        h = settlementHeight(x, z, natural: h)
        // Flatten the ground around the landing pad.
        let pad = TerrainGenerator.pad
        let padDistance = max(abs(x - pad.x), abs(z - pad.y))
        if padDistance <= 7 {
            h = Float(padHeight)
        } else if padDistance <= 11 {
            let k = Float(padDistance - 7) / 4
            h = Float(padHeight) * (1 - k) + h * k
        }
        return max(3, min(World.height - 20, Int(h.rounded())))
    }

    /// The top block of a column, as the far-away terrain shows it.
    func surfaceBlock(height h: Int) -> UInt8 {
        let t = planet.terrain
        return (t.low != B.air && h <= t.lowLevel) ? t.low : t.surface
    }

    // MARK: Chunks

    @inline(__always)
    static func index(_ lx: Int, _ y: Int, _ lz: Int) -> Int {
        (y * World.chunkSize + lz) * World.chunkSize + lx
    }

    func generateChunk(_ key: ChunkKey) -> [UInt8] {
        let s = World.chunkSize
        let t = planet.terrain
        var blocks = [UInt8](repeating: B.air, count: World.chunkVolume)
        let x0 = key.x * s
        let z0 = key.z * s
        let pad = TerrainGenerator.pad

        func put(_ x: Int, _ y: Int, _ z: Int, _ id: UInt8, onlyAir: Bool) {
            let lx = x - x0
            let lz = z - z0
            guard lx >= 0, lz >= 0, lx < s, lz < s, y >= 0, y < World.height else { return }
            let i = TerrainGenerator.index(lx, y, lz)
            if onlyAir && blocks[i] != B.air { return }
            blocks[i] = id
        }

        // Ground.
        for lz in 0..<s {
            for lx in 0..<s {
                let x = x0 + lx
                let z = z0 + lz
                let h = height(x, z)
                let isLow = t.low != B.air && h <= t.lowLevel
                for y in 0..<h {
                    let id: UInt8
                    if y == h - 1 {
                        id = isLow ? t.low : t.surface
                    } else if y >= h - 4 {
                        id = isLow ? t.low : t.under
                    } else {
                        id = t.stone
                    }
                    blocks[TerrainGenerator.index(lx, y, lz)] = id
                }
                let padDistance = max(abs(x - pad.x), abs(z - pad.y))
                if padDistance <= 5 {
                    let corner = abs(x - pad.x) == 5 && abs(z - pad.y) == 5
                    blocks[TerrainGenerator.index(lx, h - 1, lz)] = corner ? B.lamp : B.metal
                }
            }
        }

        // Trees, crystals and crate stacks. Trees reach 2 blocks sideways,
        // so look at columns just outside this chunk too.
        let f = planet.features
        for z in (z0 - 2)..<(z0 + s + 2) {
            for x in (x0 - 2)..<(x0 + s + 2) {
                if abs(x - TerrainGenerator.spawn.x) < 7 && abs(z - TerrainGenerator.spawn.y) < 7 { continue }
                if max(abs(x - pad.x), abs(z - pad.y)) <= 8 { continue }
                if insideSettlement(x, z) { continue }
                let roll = noise.hash(x &* 7 &+ 3, z &* 13 &+ 5)
                guard roll < f.trees + f.crystals + f.crates else { continue }
                let top = height(x, z)
                guard top + 9 < World.height else { continue }
                if roll < f.trees, t.trunk != B.air {
                    let tall = noise.hash(x, z &+ 99) > 0.5
                    let trunkHeight = tall ? 6 : 4
                    for dy in 0..<trunkHeight { put(x, top + dy, z, t.trunk, onlyAir: false) }
                    let cy = top + trunkHeight
                    for dy in -1...2 {
                        for dz in -2...2 {
                            for dx in -2...2 {
                                let d = Float(dx * dx + dz * dz) + Float(dy * dy) * 1.6
                                if d <= 5.2 { put(x + dx, cy + dy, z + dz, t.leaves, onlyAir: true) }
                            }
                        }
                    }
                } else if roll >= f.trees && roll < f.trees + f.crystals {
                    let tallest = f.crystals > 0.01 ? 6 : 3
                    let crystalHeight = 1 + Int(noise.hash(x &+ 17, z) * Float(tallest))
                    for y in top..<(top + crystalHeight) { put(x, y, z, B.crystal, onlyAir: false) }
                } else if roll >= f.trees + f.crystals {
                    let crateHeight = 1 + Int(noise.hash(x &+ 5, z &+ 3) * 3)
                    for y in top..<(top + crateHeight) { put(x, y, z, B.crate, onlyAir: false) }
                }
            }
        }

        // Cities, bases and mines.
        for piece in settlementPieces(x0: x0, z0: z0, size: s) {
            let yRange = max(0, piece.min.y)..<min(World.height, piece.max.y)
            let zRange = max(piece.min.z, z0)..<min(piece.max.z, z0 + s)
            let xRange = max(piece.min.x, x0)..<min(piece.max.x, x0 + s)
            guard !yRange.isEmpty, !zRange.isEmpty, !xRange.isEmpty else { continue }
            for y in yRange {
                for z in zRange {
                    for x in xRange {
                        if let id = piece.paint(x, y, z) {
                            blocks[TerrainGenerator.index(x - x0, y, z - z0)] = id
                        }
                    }
                }
            }
        }

        // A row of crate stacks in front of where you start, to try the laser on.
        for (dx, crateHeight) in [(-4, 2), (0, 3), (4, 2)] {
            let x = TerrainGenerator.spawn.x + dx
            let z = TerrainGenerator.spawn.y - 9
            let top = height(x, z)
            for y in top..<(top + crateHeight) { put(x, y, z, B.crate, onlyAir: false) }
        }
        return blocks
    }
}
