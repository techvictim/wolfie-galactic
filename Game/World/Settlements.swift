import Foundation
import simd

/// Futuristic Wolfie cities on Wolfie World, domed bases on Pup Moon and mining colonies on
/// Glimmer. They're built from the planet's seed like everything else, so each one is always
/// in the same place and only the parts players change get saved.
///
/// The land is split into big cells; some cells have a settlement. Each settlement is a list of
/// pieces (towers, domes, streets…), each a box of space plus a rule for which block goes where.
/// A chunk asks for the pieces that overlap it and paints just its part.
struct Settlement: Sendable {
    enum Kind: String, Sendable { case city, base, mine }

    let kind: Kind
    let center: SIMD2<Int>
    /// Half-width of its flat ground.
    let radius: Int
    let ground: Int
    let seed: UInt64

    /// A box of the world and how to paint it. nil leaves a block alone; air carves.
    struct Piece: Sendable {
        let min: SIMD3<Int>
        let max: SIMD3<Int>   // exclusive
        /// For the far-away land: how tall this looks from a distance, and in which colour.
        let farTop: Int?
        let farBlock: UInt8
        let paint: @Sendable (Int, Int, Int) -> UInt8?
    }
}

/// Block ids used by settlements (see Resources/blocks.json).
enum SB {
    static let white: UInt8 = 22
    static let nightGlass: UInt8 = 23
    static let neonCyan: UInt8 = 24
    static let neonPink: UInt8 = 25
    static let roofTeal: UInt8 = 26
    static let road: UInt8 = 27
    static let roadLine: UInt8 = 28
    static let domeGlass: UInt8 = 29
    static let solar: UInt8 = 30
}

extension TerrainGenerator {
    static let settlementCell = 200

    // MARK: Where they are

    /// The settlement in a big cell, if there is one.
    func settlement(cellX: Int, cellZ: Int) -> Settlement? {
        guard let kindName = planet.features.settlement, let kind = Settlement.Kind(rawValue: kindName) else { return nil }
        let cell = TerrainGenerator.settlementCell
        let radius = kind == .city ? 34 : 24
        let margin = radius + 14
        var center: SIMD2<Int>
        // One is always close to where you start, so it's easy to find.
        let first = TerrainGenerator.firstSettlement
        if cellX == floorDiv(first.x, cell) && cellZ == floorDiv(first.y, cell) {
            center = first
        } else {
            guard noise.hash(cellX &* 41 &+ 5, cellZ &* 23 &+ 9) < (planet.features.settlementChance ?? 0.3) else { return nil }
            let span = Float(cell - 2 * margin)
            center = SIMD2<Int>(
                cellX * cell + margin + Int(noise.hash(cellX &+ 71, cellZ) * span),
                cellZ * cell + margin + Int(noise.hash(cellX, cellZ &+ 71) * span)
            )
            // Not on top of the start or the landing pad.
            let start = SIMD2<Float>(Float(TerrainGenerator.spawn.x), Float(TerrainGenerator.spawn.y))
            if simd_distance(SIMD2<Float>(Float(center.x), Float(center.y)), start) < Float(radius + 40) { return nil }
        }
        let rawGround = Float(planet.terrain.base) + noise.fbm(Float(center.x) * planet.terrain.frequency, Float(center.y) * planet.terrain.frequency) * planet.terrain.amplitude
        let ground = max(6, min(World.height - 62, Int(rawGround.rounded())))
        let seed = UInt64(bitPattern: Int64(cellX &* 73_856_093 ^ cellZ &* 19_349_663)) ^ noise.seed
        return Settlement(kind: kind, center: center, radius: radius, ground: ground, seed: seed)
    }

    /// The first settlement: a short walk north-east of where you start.
    static let firstSettlement = SIMD2<Int>(92, -96)

    /// The settlement whose ground covers this column, if any (with its edge slope).
    func settlement(near x: Int, _ z: Int) -> Settlement? {
        let cell = TerrainGenerator.settlementCell
        let cx = floorDiv(x, cell), cz = floorDiv(z, cell)
        // Quick check first (this runs for every column): is there one in this cell, close enough?
        guard planet.features.settlement != nil else { return nil }
        let first = TerrainGenerator.firstSettlement
        let isFirst = cx == floorDiv(first.x, cell) && cz == floorDiv(first.y, cell)
        guard isFirst || noise.hash(cx &* 41 &+ 5, cz &* 23 &+ 9) < (planet.features.settlementChance ?? 0.3) else { return nil }
        guard let site = settlement(cellX: cx, cellZ: cz) else { return nil }
        let d = site.kind == .city
            ? max(abs(x - site.center.x), abs(z - site.center.y))
            : Int(simd_distance(SIMD2<Float>(Float(x), Float(z)), SIMD2<Float>(Float(site.center.x), Float(site.center.y))))
        return d <= site.radius + 10 ? site : nil
    }

    /// Flatten the ground under a settlement, sloping back to the hills around it.
    func settlementHeight(_ x: Int, _ z: Int, natural: Float) -> Float {
        guard let site = settlement(near: x, z) else { return natural }
        let d: Float = site.kind == .city
            ? Float(max(abs(x - site.center.x), abs(z - site.center.y)))
            : simd_distance(SIMD2<Float>(Float(x), Float(z)), SIMD2<Float>(Float(site.center.x), Float(site.center.y)))
        let r = Float(site.radius)
        if d <= r + 1 { return Float(site.ground) }
        let k = min(1, (d - r - 1) / 9)
        return Float(site.ground) * (1 - k) + natural * k
    }

    /// True inside a settlement, where trees and crystals don't grow.
    func insideSettlement(_ x: Int, _ z: Int) -> Bool {
        guard let site = settlement(near: x, z) else { return false }
        let d = max(abs(x - site.center.x), abs(z - site.center.y))
        return d <= site.radius + 3
    }

    // MARK: Painting chunks

    /// Every piece of every settlement that reaches into a chunk.
    func settlementPieces(x0: Int, z0: Int, size: Int) -> [Settlement.Piece] {
        let cell = TerrainGenerator.settlementCell
        var cells = Set<SIMD2<Int>>()
        for (dx, dz) in [(0, 0), (size - 1, 0), (0, size - 1), (size - 1, size - 1)] {
            cells.insert(SIMD2(floorDiv(x0 + dx, cell), floorDiv(z0 + dz, cell)))
        }
        var pieces: [Settlement.Piece] = []
        for c in cells {
            guard let site = settlement(cellX: c.x, cellZ: c.y) else { continue }
            for piece in Settlements.pieces(site, planet: planet) where
                piece.max.x > x0 && piece.min.x < x0 + size && piece.max.z > z0 && piece.min.z < z0 + size {
                pieces.append(piece)
            }
        }
        return pieces
    }

    /// For far-away land: the tallest building over a spot, so cities show on the horizon.
    func farTop(_ x: Int, _ z: Int) -> (height: Int, block: UInt8)? {
        guard let site = settlement(near: x, z) else { return nil }
        var best: (Int, UInt8)?
        for piece in Settlements.pieces(site, planet: planet) {
            guard let top = piece.farTop, x >= piece.min.x, x < piece.max.x, z >= piece.min.z, z < piece.max.z else { continue }
            if best == nil || top > best!.0 { best = (top, piece.farBlock) }
        }
        return best
    }
}

/// The building plans.
enum Settlements {
    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var plans: [String: [Settlement.Piece]] = [:]
    }
    private static let cache = Cache()

    /// A settlement's pieces, worked out once and remembered (chunks are made on several threads).
    static func pieces(_ site: Settlement, planet: Planet) -> [Settlement.Piece] {
        let key = "\(planet.id):\(site.center.x),\(site.center.y)"
        cache.lock.lock()
        if let plan = cache.plans[key] {
            cache.lock.unlock()
            return plan
        }
        cache.lock.unlock()
        let plan: [Settlement.Piece]
        switch site.kind {
        case .city: plan = city(site, planet: planet)
        case .base: plan = base(site, planet: planet, mine: false)
        case .mine: plan = base(site, planet: planet, mine: true)
        }
        cache.lock.lock()
        cache.plans[key] = plan
        cache.lock.unlock()
        return plan
    }

    /// A repeatable random number 0..<1 for a settlement.
    private static func roll(_ site: Settlement, _ a: Int, _ b: Int) -> Float {
        Noise(seed: site.seed).hash(a, b)
    }

    // MARK: Shapes

    private static func box(_ min: SIMD3<Int>, _ max: SIMD3<Int>, far: Int? = nil, farBlock: UInt8 = SB.white,
                            _ paint: @escaping @Sendable (Int, Int, Int) -> UInt8?) -> Settlement.Piece {
        Settlement.Piece(min: min, max: max, farTop: far, farBlock: farBlock, paint: paint)
    }

    /// A hollow tower with window bands, a glowing stripe at the top and an antenna.
    private static func tower(x0: Int, z0: Int, w: Int, d: Int, ground g: Int, height h: Int, neon: UInt8, ears: Bool = false) -> [Settlement.Piece] {
        let top = g + h
        var pieces: [Settlement.Piece] = [
            box(SIMD3(x0, g, z0), SIMD3(x0 + w, top + 1, z0 + d), far: top + 1) { x, y, z in
                let edgeX = x == x0 || x == x0 + w - 1
                let edgeZ = z == z0 || z == z0 + d - 1
                if y == top { return SB.white }                 // roof
                if y == top - 1 && (edgeX || edgeZ) { return neon }
                guard edgeX || edgeZ else { return y == g ? SB.white : B.air }   // floor, then hollow
                if edgeX && edgeZ { return SB.white }           // corners
                if y == g { return SB.white }
                return (y - g) % 3 == 2 ? SB.white : SB.nightGlass
            }
        ]
        let cx = x0 + w / 2
        let cz = z0 + d / 2
        if ears {
            // Two pointed wolf ears on the roof of the tallest tower.
            for side in [-1, 1] {
                let ex = cx + side * (w / 4)
                pieces.append(box(SIMD3(ex - 2, top + 1, cz - 1), SIMD3(ex + 3, top + 8, cz + 2), far: top + 8, farBlock: SB.neonPink) { x, y, z in
                    let k = y - top - 1               // 0...6
                    let half = 2 - k / 3
                    guard abs(x - ex) <= half else { return nil }
                    return k >= 5 ? SB.neonPink : SB.white
                })
            }
        } else {
            pieces.append(box(SIMD3(cx, top + 1, cz), SIMD3(cx + 1, top + 6, cz + 1)) { _, y, _ in
                y == top + 5 ? B.lamp : B.metal
            })
        }
        return pieces
    }

    /// A round tower with a teal dome on top.
    private static func roundTower(cx: Int, cz: Int, r: Int, ground g: Int, height h: Int) -> Settlement.Piece {
        let top = g + h
        return box(SIMD3(cx - r, g, cz - r), SIMD3(cx + r + 1, top + r + 1, cz + r + 1), far: top + r / 2) { x, y, z in
            let dx = Float(x - cx), dz = Float(z - cz)
            let d = (dx * dx + dz * dz).squareRoot()
            if y >= top {
                let dy = Float(y - top)
                let dd = (dx * dx + dz * dz + dy * dy).squareRoot()
                if dd <= Float(r) + 0.5 { return dd > Float(r) - 0.9 ? SB.roofTeal : B.air }
                return nil
            }
            guard d <= Float(r) + 0.5 else { return nil }
            if d > Float(r) - 0.6 {
                if y == top - 1 { return SB.neonCyan }
                return (y - g) % 4 == 3 ? SB.white : SB.nightGlass
            }
            return y == g ? SB.white : B.air
        }
    }

    /// A glass dome with a floor inside.
    private static func dome(cx: Int, cz: Int, r: Int, ground g: Int, floor: UInt8, glass: UInt8 = SB.domeGlass) -> Settlement.Piece {
        box(SIMD3(cx - r, g - 1, cz - r), SIMD3(cx + r + 1, g + r + 1, cz + r + 1), far: g + r * 2 / 3, farBlock: glass) { x, y, z in
            let dx = Float(x - cx), dy = Float(y - g), dz = Float(z - cz)
            let flat = (dx * dx + dz * dz).squareRoot()
            if y == g - 1 { return flat <= Float(r) + 0.5 ? (flat > Float(r) - 1.2 ? SB.white : floor) : nil }
            let d = (dx * dx + dy * dy + dz * dz).squareRoot()
            guard d <= Float(r) + 0.5 else { return nil }
            if y == g && flat > Float(r) - 1.5 { return SB.white }   // base ring
            return d > Float(r) - 0.6 ? glass : B.air
        }
    }

    /// A stepped pyramid with glowing edges.
    private static func ziggurat(x0: Int, z0: Int, size: Int, ground g: Int) -> Settlement.Piece {
        let steps = size / 2
        return box(SIMD3(x0, g, z0), SIMD3(x0 + size, g + steps * 2 + 2, z0 + size), far: g + steps * 2) { x, y, z in
            let level = (y - g) / 2
            let inset = level
            guard x >= x0 + inset, x < x0 + size - inset, z >= z0 + inset, z < z0 + size - inset else { return nil }
            if inset * 2 >= size - 1 { return y - g == level * 2 ? B.lamp : nil }
            let edge = x == x0 + inset || x == x0 + size - inset - 1 || z == z0 + inset || z == z0 + size - inset - 1
            if (y - g) % 2 == 1 && edge { return SB.neonCyan }
            return SB.white
        }
    }

    /// A landing pad with lamps on its corners.
    private static func landingPad(x0: Int, z0: Int, size: Int, ground g: Int) -> Settlement.Piece {
        box(SIMD3(x0, g - 1, z0), SIMD3(x0 + size, g, z0 + size)) { x, _, z in
            let cornerX = x == x0 || x == x0 + size - 1
            let cornerZ = z == z0 || z == z0 + size - 1
            if cornerX && cornerZ { return B.lamp }
            let mid = size / 2
            // A big "H".
            let hx = x - x0, hz = z - z0
            if (hx == 2 || hx == size - 3) && hz >= 2 && hz <= size - 3 { return SB.roadLine }
            if hz == mid && hx >= 2 && hx <= size - 3 { return SB.roadLine }
            return B.metal
        }
    }

    /// A little park: moss, two trees and lamp posts.
    private static func park(x0: Int, z0: Int, size: Int, ground g: Int, planet: Planet) -> [Settlement.Piece] {
        let t = planet.terrain
        var pieces = [box(SIMD3(x0, g - 1, z0), SIMD3(x0 + size, g, z0 + size)) { _, _, _ in t.surface }]
        for (tx, tz) in [(x0 + 3, z0 + 4), (x0 + size - 4, z0 + size - 5)] where t.trunk != B.air {
            pieces.append(box(SIMD3(tx - 2, g, tz - 2), SIMD3(tx + 3, g + 8, tz + 3), far: g + 7, farBlock: t.leaves) { x, y, z in
                if x == tx && z == tz && y < g + 5 { return t.trunk }
                let dx = x - tx, dz = z - tz, dy = y - (g + 5)
                return Float(dx * dx + dz * dz) + Float(dy * dy) * 1.6 <= 5.2 ? t.leaves : nil
            })
        }
        pieces.append(box(SIMD3(x0, g, z0), SIMD3(x0 + 1, g + 3, z0 + 1)) { _, y, _ in y == g + 2 ? B.lamp : B.metal })
        pieces.append(box(SIMD3(x0 + size - 1, g, z0 + size - 1), SIMD3(x0 + size, g + 3, z0 + size)) { _, y, _ in y == g + 2 ? B.lamp : B.metal })
        return pieces
    }

    // MARK: Wolfie cities

    private static func city(_ site: Settlement, planet: Planet) -> [Settlement.Piece] {
        let g = site.ground
        let r = site.radius
        let x0 = site.center.x - r
        let z0 = site.center.y - r
        let side = r * 2
        let street = 17
        var pieces: [Settlement.Piece] = []

        // Streets on a grid, with dashed yellow lines; pavement everywhere else. Clear the air above.
        pieces.append(box(SIMD3(x0, g - 1, z0), SIMD3(x0 + side + 1, g + 1, z0 + side + 1)) { x, y, z in
            if y == g { return B.air }
            let sx = (x - x0) % street, sz = (z - z0) % street
            let onStreetX = sx < 3, onStreetZ = sz < 3
            if onStreetX || onStreetZ {
                if onStreetX && sx == 1 && !onStreetZ && (z - z0) % 4 < 2 { return SB.roadLine }
                if onStreetZ && sz == 1 && !onStreetX && (x - x0) % 4 < 2 { return SB.roadLine }
                return SB.road
            }
            return SB.white
        })

        let lots = side / street
        let middle = lots / 2
        for i in 0..<lots {
            for j in 0..<lots {
                let lx = x0 + i * street + 3
                let lz = z0 + j * street + 3
                let lot = street - 3
                let pick = roll(site, i, j)
                if i == middle && j == middle {
                    // The landmark: Wolfie Tower, tallest in town, with ears.
                    pieces += tower(x0: lx + 1, z0: lz + 1, w: 12, d: 12, ground: g, height: min(54, World.height - g - 12), neon: SB.neonPink, ears: true)
                } else if pick < 0.42 {
                    let w = 8 + Int(roll(site, i + 9, j) * 4)
                    let h = 16 + Int(roll(site, i, j + 9) * 26)
                    let neon = roll(site, i + 3, j + 3) < 0.5 ? SB.neonCyan : SB.neonPink
                    pieces += tower(x0: lx + (lot - w) / 2, z0: lz + (lot - w) / 2, w: w, d: w, ground: g, height: min(h, World.height - g - 8), neon: neon)
                } else if pick < 0.6 {
                    pieces.append(roundTower(cx: lx + lot / 2, cz: lz + lot / 2, r: 4 + Int(roll(site, i, j + 4) * 2), ground: g, height: 12 + Int(roll(site, i + 4, j) * 20)))
                } else if pick < 0.72 {
                    pieces.append(dome(cx: lx + lot / 2, cz: lz + lot / 2, r: 6, ground: g, floor: planet.terrain.surface))
                } else if pick < 0.82 {
                    pieces.append(ziggurat(x0: lx + 1, z0: lz + 1, size: lot - 2, ground: g))
                } else if pick < 0.9 {
                    pieces.append(landingPad(x0: lx + 1, z0: lz + 1, size: lot - 2, ground: g))
                } else {
                    pieces += park(x0: lx, z0: lz, size: lot, ground: g, planet: planet)
                }
            }
        }
        return pieces
    }

    // MARK: Moon bases and mining colonies

    private static func base(_ site: Settlement, planet: Planet, mine: Bool) -> [Settlement.Piece] {
        let g = site.ground
        let c = site.center
        var pieces: [Settlement.Piece] = []

        // Clear the air and lay a metal floor in a ring path.
        let r = site.radius
        pieces.append(box(SIMD3(c.x - r, g - 1, c.y - r), SIMD3(c.x + r + 1, g + 1, c.y + r + 1)) { x, y, z in
            let d = simd_distance(SIMD2<Float>(Float(x), Float(z)), SIMD2<Float>(Float(c.x), Float(c.y)))
            guard d <= Float(r) else { return nil }
            if y == g { return B.air }
            return abs(d - 14) < 1.5 ? B.metal : nil
        })

        // Tubes from the big dome to the small ones.
        let angles: [Float] = [0.3, 2.4, 4.4]
        for a in angles {
            let ex = c.x + Int((cos(a) * 15).rounded())
            let ez = c.y + Int((sin(a) * 15).rounded())
            let minX = min(c.x, ex) - 1, maxX = max(c.x, ex) + 2
            let minZ = min(c.y, ez) - 1, maxZ = max(c.y, ez) + 2
            let from = SIMD2<Float>(Float(c.x), Float(c.y)), to = SIMD2<Float>(Float(ex), Float(ez))
            pieces.append(box(SIMD3(minX, g - 1, minZ), SIMD3(maxX, g + 3, maxZ)) { x, y, z in
                let p = SIMD2<Float>(Float(x), Float(z))
                let line = to - from
                let t = max(0, min(1, simd_dot(p - from, line) / simd_length_squared(line)))
                let d = simd_distance(p, from + line * t)
                guard d <= 1.6 else { return nil }
                if y == g - 1 { return B.metal }
                if d > 0.9 || y == g + 2 { return SB.domeGlass }
                return B.air
            })
        }

        // The big dome in the middle is a greenhouse; the small ones are labs and homes.
        pieces.append(dome(cx: c.x, cz: c.y, r: 9, ground: g, floor: mine ? B.metal : 13))
        if !mine, planet.terrain.trunk == B.air {
            pieces.append(box(SIMD3(c.x - 3, g, c.y - 3), SIMD3(c.x + 4, g + 6, c.y + 4)) { x, y, z in
                // A little glowing garden.
                if (x == c.x - 2 || x == c.x + 2) && (z == c.y - 2 || z == c.y + 2) && y <= g + 1 { return 17 }
                if x == c.x && z == c.y && y < g + 4 { return 16 }
                if y == g + 4 && abs(x - c.x) <= 1 && abs(z - c.y) <= 1 { return 17 }
                return nil
            })
        }
        for (i, a) in angles.enumerated() {
            let cx = c.x + Int((cos(a) * 15).rounded())
            let cz = c.y + Int((sin(a) * 15).rounded())
            pieces.append(dome(cx: cx, cz: cz, r: 5, ground: g, floor: SB.white, glass: i == 1 ? SB.nightGlass : SB.domeGlass))
        }

        // Radar tower, or a drilling rig at a mine.
        let tx = c.x - 12, tz = c.y + 12
        let towerHeight = mine ? 22 : 15
        pieces.append(box(SIMD3(tx - 1, g, tz - 1), SIMD3(tx + 2, g + towerHeight + 3, tz + 2), far: g + towerHeight + 2, farBlock: B.metal) { x, y, z in
            let k = y - g
            if k >= towerHeight {
                if mine { return x == tx && z == tz ? (k == towerHeight + 2 ? B.lamp : B.crystal) : nil }
                return k == towerHeight ? SB.white : (x == tx && z == tz ? B.lamp : nil)
            }
            let corner = x != tx && z != tz
            if corner { return B.metal }
            return k % 4 == 0 ? B.metal : nil
        })

        // Solar panels in rows.
        let sx = c.x + 8, sz = c.y - 18
        pieces.append(box(SIMD3(sx, g, sz), SIMD3(sx + 12, g + 3, sz + 6)) { x, y, z in
            let row = (z - sz) % 3
            if row == 2 { return nil }
            if y == g + 2 { return SB.solar }
            return (x - sx) % 4 == 0 && row == 0 ? B.metal : nil
        })

        // A landing pad, and at a mine, piles of crystals and crates.
        pieces.append(landingPad(x0: c.x - 20, z0: c.y - 20, size: 9, ground: g))
        if mine {
            for (px, pz) in [(c.x + 14, c.y + 9), (c.x + 16, c.y + 5), (c.x - 3, c.y - 17)] {
                pieces.append(box(SIMD3(px - 2, g, pz - 2), SIMD3(px + 3, g + 4, pz + 3)) { x, y, z in
                    let d = abs(x - px) + abs(z - pz) + (y - g) * 2
                    return d <= 4 ? (d % 2 == 0 ? B.crystal : 17) : nil
                })
            }
            pieces.append(box(SIMD3(c.x + 4, g, c.y + 17), SIMD3(c.x + 10, g + 3, c.y + 19)) { x, y, z in
                (x + y + z) % 3 == 0 && y == g + 2 ? nil : B.crate
            })
        }
        return pieces
    }
}
