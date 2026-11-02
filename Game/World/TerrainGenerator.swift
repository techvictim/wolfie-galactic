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
        let n = noise.fbm(Float(x) * t.frequency, Float(z) * t.frequency)
        // Plains: wide stretches where the hills settle down, good for driving.
        let flat = plains(x, z)
        return Float(t.base) + ((n - 0.5) * (1 - 0.85 * flat) + 0.5) * t.amplitude
    }

    // MARK: Plains and roads

    /// 0 in the hills, 1 out on the plains.
    func plains(_ x: Int, _ z: Int) -> Float {
        let p = noise.fbm(Float(x) * 0.0045 + 311, Float(z) * 0.0045 - 157)
        return min(1, max(0, (p - 0.5) / 0.08))
    }

    /// A road near this column: how far from its middle, how far along it, the line it follows
    /// (x for roads running north-south, z for east-west), and the height to keep it at, if set.
    struct RoadSpot {
        let distance: Int
        let along: Int
        let alongX: Bool
        let line: Int
        let ground: Float?
    }

    static let roadHalfWidth = 3
    private static let roadReach = 9

    /// Highways run along the edges of the big settlement cells; every settlement has roads out
    /// to them, and a ring road around it.
    func road(_ x: Int, _ z: Int) -> RoadSpot? {
        if planet.isStation { return nil }
        let reach = TerrainGenerator.roadReach
        let cell = TerrainGenerator.settlementCell
        var best: RoadSpot?
        func consider(_ spot: RoadSpot) {
            if spot.distance <= reach && (best == nil || spot.distance < best!.distance) { best = spot }
        }
        let mx = floorMod(x, cell), mz = floorMod(z, cell)
        // Highways.
        consider(RoadSpot(distance: min(mx, cell - mx), along: z, alongX: false, line: mx < cell / 2 ? x - mx : x - mx + cell, ground: nil))
        consider(RoadSpot(distance: min(mz, cell - mz), along: x, alongX: true, line: mz < cell / 2 ? z - mz : z - mz + cell, ground: nil))
        // Roads out of the settlement in this cell, and around it.
        if planet.features.settlement != nil, let site = settlement(cellX: floorDiv(x, cell), cellZ: floorDiv(z, cell)) {
            let cx = site.center.x, cz = site.center.y
            let square = site.isSquare
            let d = square ? max(abs(x - cx), abs(z - cz))
                           : Int(simd_distance(SIMD2<Float>(Float(x), Float(z)), SIMD2<Float>(Float(cx), Float(cz))))
            if d <= site.radius + 1 { return nil }     // the settlement's own streets
            let near = d < site.radius + 26 ? Float(site.ground) : nil
            consider(RoadSpot(distance: abs(z - cz), along: x, alongX: true, line: cz, ground: near))
            consider(RoadSpot(distance: abs(x - cx), along: z, alongX: false, line: cx, ground: near))
            let ring = site.radius + 6
            consider(RoadSpot(distance: abs(d - ring), along: x + z, alongX: true, line: 0, ground: Float(site.ground)))
        }
        return best
    }

    /// The road's height: the land, smoothed along the road so hills become gentle slopes.
    private func roadHeight(_ spot: RoadSpot) -> Float {
        if let ground = spot.ground { return ground }
        // The land averaged over about 90 blocks of road, worked out every 8 blocks and
        // blended in between, so the road climbs in gentle, even slopes.
        func smooth(_ a: Int) -> Float {
            var sum: Float = 0
            for k in -4...4 {
                let p = a + k * 10
                sum += spot.alongX ? baseHeight(p, spot.line) : baseHeight(spot.line, p)
            }
            return sum / 9
        }
        let a0 = floorDiv(spot.along, 8) * 8
        let t = Float(spot.along - a0) / 8
        return smooth(a0) * (1 - t) + smooth(a0 + 8) * t
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
        if planet.isStation { return StationPlan.height(x, z) }
        var h = baseHeight(x, z) + craterOffset(x, z)
        // Roads: flat across, gentle along, blending into the land at their edges.
        if let spot = road(x, z) {
            let target = roadHeight(spot)
            let edge = TerrainGenerator.roadHalfWidth
            if spot.distance <= edge {
                h = target
            } else {
                let k = Float(spot.distance - edge) / Float(TerrainGenerator.roadReach - edge)
                h = target * (1 - k) + h * k
            }
        }
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

    /// The top block of a column, with roads, as the far-away terrain shows it.
    func surfaceBlock(x: Int, z: Int, height h: Int) -> UInt8 {
        if let spot = road(x, z), spot.distance <= TerrainGenerator.roadHalfWidth { return SB.road }
        return surfaceBlock(height: h)
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
        if planet.isStation {
            // A space station: nothing but what was built.
            for piece in StationPlan.pieces(x0: x0, z0: z0, size: s) {
                paint(piece, into: &blocks, x0: x0, z0: z0)
            }
            return blocks
        }

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
                // Road: asphalt with a dashed yellow line down the middle.
                if let spot = road(x, z), spot.distance <= TerrainGenerator.roadHalfWidth, h > 0 {
                    let line = spot.distance == 0 && floorMod(spot.along, 8) < 4
                    blocks[TerrainGenerator.index(lx, h - 1, lz)] = line ? SB.roadLine : SB.road
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
                // Nothing grows on or right beside roads, and the plains are open.
                if let spot = road(x, z), spot.distance <= 6 { continue }
                if plains(x, z) > 0.6 { continue }
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
            paint(piece, into: &blocks, x0: x0, z0: z0)
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

    private func paint(_ piece: Settlement.Piece, into blocks: inout [UInt8], x0: Int, z0: Int) {
        let s = World.chunkSize
        let yRange = max(0, piece.min.y)..<min(World.height, piece.max.y)
        let zRange = max(piece.min.z, z0)..<min(piece.max.z, z0 + s)
        let xRange = max(piece.min.x, x0)..<min(piece.max.x, x0 + s)
        guard !yRange.isEmpty, !zRange.isEmpty, !xRange.isEmpty else { return }
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
}
