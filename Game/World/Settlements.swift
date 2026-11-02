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
    enum Kind: String, Sendable { case city, base, mine, military }

    let kind: Kind
    let center: SIMD2<Int>
    /// Half-width of its flat ground.
    let radius: Int
    let ground: Int
    let seed: UInt64

    /// Cities and the military base are square; bases and mines are round.
    var isSquare: Bool { kind == .city || kind == .military }

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

/// A building the Red Glitch has taken over. It glows red and makes robo-cats until it's wrecked
/// (cured); then the builder bots put it back clean.
struct GlitchNest: Sendable {
    /// "<settlement x>,<settlement z>,<number>", the same on every device.
    let id: String
    let name: String
    let min: SIMD3<Int>
    /// Exclusive.
    let max: SIMD3<Int>
    /// Wolfie Tower: the Glitch's heart.
    let heart: Bool
    /// The building as it should be, clean.
    let pieces: [Settlement.Piece]

    var center: SIMD3<Float> {
        SIMD3<Float>(Float(min.x + max.x) / 2, Float(min.y + max.y) / 2, Float(min.z + max.z) / 2)
    }

    var groundCenter: SIMD2<Float> {
        SIMD2<Float>(Float(min.x + max.x) / 2, Float(min.z + max.z) / 2)
    }

    /// The clean block for a cell, or nil if the building doesn't touch it.
    func clean(_ x: Int, _ y: Int, _ z: Int) -> UInt8? {
        var block: UInt8?
        for piece in pieces where x >= piece.min.x && x < piece.max.x && y >= piece.min.y && y < piece.max.y && z >= piece.min.z && z < piece.max.z {
            if let b = piece.paint(x, y, z) { block = b }
        }
        return block
    }

    /// Glitched blocks: the building's frame goes dark red, its windows and lights glow.
    static func glitched(_ block: UInt8) -> UInt8 {
        switch block {
        case B.air: return B.air
        case SB.nightGlass, SB.domeGlass, SB.neonCyan, SB.neonPink, B.lamp, 8, B.crystal, 17, 16: return SB.glitchGlow
        case 1, 2, 4, 6, 13, 14, 18, 19, 20, 21: return block   // ground and plants stay
        default: return SB.glitchBlock
        }
    }

    static func isGlitch(_ block: UInt8) -> Bool {
        block == SB.glitchBlock || block == SB.glitchGlow
    }
}

/// Block ids used by settlements (see Resources/blocks.json).
enum SB {
    static let glitchBlock: UInt8 = 35
    static let glitchGlow: UInt8 = 36
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
        // Wolfie Military's base has its own cell on the home planet.
        let military = TerrainGenerator.militaryBase
        if planet.id == TerrainGenerator.homePlanet, cellX == floorDiv(military.x, cell), cellZ == floorDiv(military.y, cell) {
            let raw = Float(planet.terrain.base) + noise.fbm(Float(military.x) * planet.terrain.frequency, Float(military.y) * planet.terrain.frequency) * planet.terrain.amplitude
            let ground = max(6, min(World.height - 62, Int(raw.rounded())))
            return Settlement(kind: .military, center: military, radius: 46, ground: ground, seed: noise.seed &+ 4242)
        }
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
    /// Wolfie Military's base on Wolfie World: south-west of where you start.
    static let militaryBase = SIMD2<Int>(-100, 100)
    static let homePlanet = "wolfie-world"

    /// The settlement whose ground covers this column, if any (with its edge slope).
    func settlement(near x: Int, _ z: Int) -> Settlement? {
        let cell = TerrainGenerator.settlementCell
        let cx = floorDiv(x, cell), cz = floorDiv(z, cell)
        // Quick check first (this runs for every column): is there one in this cell, close enough?
        guard planet.features.settlement != nil else { return nil }
        let first = TerrainGenerator.firstSettlement
        let isFirst = cx == floorDiv(first.x, cell) && cz == floorDiv(first.y, cell)
        let military = TerrainGenerator.militaryBase
        let isBase = planet.id == TerrainGenerator.homePlanet && cx == floorDiv(military.x, cell) && cz == floorDiv(military.y, cell)
        guard isFirst || isBase || noise.hash(cx &* 41 &+ 5, cz &* 23 &+ 9) < (planet.features.settlementChance ?? 0.3) else { return nil }
        guard let site = settlement(cellX: cx, cellZ: cz) else { return nil }
        let d = site.isSquare
            ? max(abs(x - site.center.x), abs(z - site.center.y))
            : Int(simd_distance(SIMD2<Float>(Float(x), Float(z)), SIMD2<Float>(Float(site.center.x), Float(site.center.y))))
        return d <= site.radius + 10 ? site : nil
    }

    /// Flatten the ground under a settlement, sloping back to the hills around it.
    func settlementHeight(_ x: Int, _ z: Int, natural: Float) -> Float {
        guard let site = settlement(near: x, z) else { return natural }
        let d: Float = site.isSquare
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

    /// For far-away land: a building over a patch of ground, with the colour of each layer of its
    /// walls (windows, white bands, neon stripes), so skylines look like buildings from far away.
    func farColumn(_ x: Int, _ z: Int, cell: Int) -> (height: Int, top: UInt8, ground: Int, bands: [UInt8])? {
        guard let site = settlement(near: x, z) else { return nil }
        let pieces = Settlements.pieces(site, planet: planet).filter {
            $0.farTop != nil && $0.max.x > x && $0.min.x < x + cell && $0.max.z > z && $0.min.z < z + cell
        }
        guard !pieces.isEmpty else { return nil }
        var height = 0
        var top: UInt8 = SB.white
        for p in pieces where (p.farTop ?? 0) > height {
            height = p.farTop ?? 0
            top = p.farBlock
        }
        let ground = site.ground
        guard height > ground else { return nil }
        // Look at a few spots in the patch, outside first, for each layer.
        let spots = [(x, z), (x + cell - 1, z), (x, z + cell - 1), (x + cell - 1, z + cell - 1), (x + cell / 2, z + cell / 2)]
        var bands: [UInt8] = []
        bands.reserveCapacity(height - ground)
        for y in ground..<height {
            var found: UInt8 = B.air
            search: for (sx, sz) in spots {
                for p in pieces.reversed() where sx >= p.min.x && sx < p.max.x && sz >= p.min.z && sz < p.max.z && y >= p.min.y && y < p.max.y {
                    if let b = p.paint(sx, y, sz), b != B.air {
                        found = b
                        break search
                    }
                }
            }
            bands.append(found == B.air ? (bands.last ?? top) : found)
        }
        return (height, top, ground, bands)
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
    private struct Plan {
        let pieces: [Settlement.Piece]
        let nests: [GlitchNest]
    }

    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var plans: [String: Plan] = [:]
    }
    private static let cache = Cache()

    /// A settlement's pieces, worked out once and remembered (chunks are made on several threads).
    static func pieces(_ site: Settlement, planet: Planet) -> [Settlement.Piece] {
        plan(site, planet: planet).pieces
    }

    /// The settlement's Glitch Nests.
    static func nests(_ site: Settlement, planet: Planet) -> [GlitchNest] {
        plan(site, planet: planet).nests
    }

    private static func plan(_ site: Settlement, planet: Planet) -> Plan {
        let key = "\(planet.id):\(site.center.x),\(site.center.y)"
        cache.lock.lock()
        if let plan = cache.plans[key] {
            cache.lock.unlock()
            return plan
        }
        cache.lock.unlock()
        var builder = PlanBuilder(site: site)
        switch site.kind {
        case .city: city(site, planet: planet, into: &builder)
        case .base: base(site, planet: planet, mine: false, into: &builder)
        case .mine: base(site, planet: planet, mine: true, into: &builder)
        case .military: military(site, planet: planet, into: &builder)
        }
        let plan = Plan(pieces: builder.pieces, nests: builder.nests)
        cache.lock.lock()
        cache.plans[key] = plan
        cache.lock.unlock()
        return plan
    }

    /// Collects pieces; buildings marked as nests get glitched copies.
    private struct PlanBuilder {
        let site: Settlement
        var pieces: [Settlement.Piece] = []
        var nests: [GlitchNest] = []

        mutating func add(_ piece: Settlement.Piece) {
            pieces.append(piece)
        }

        mutating func building(_ parts: [Settlement.Piece], name: String, nest: Bool, heart: Bool = false) {
            guard nest, let first = parts.first else {
                pieces += parts
                return
            }
            var lo = first.min, hi = first.max
            for p in parts {
                lo = simd_min(lo, p.min)
                hi = simd_max(hi, p.max)
            }
            nests.append(GlitchNest(id: "\(site.center.x),\(site.center.y),\(nests.count)", name: name, min: lo, max: hi, heart: heart, pieces: parts))
            for p in parts {
                let paint = p.paint
                pieces.append(Settlement.Piece(min: p.min, max: p.max, farTop: p.farTop, farBlock: SB.glitchGlow) { x, y, z in
                    paint(x, y, z).map(GlitchNest.glitched)
                })
            }
        }
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

    private static func city(_ site: Settlement, planet: Planet, into plan: inout PlanBuilder) {
        let g = site.ground
        let r = site.radius
        let x0 = site.center.x - r
        let z0 = site.center.y - r
        let side = r * 2
        let street = 17

        // Streets on a grid, with dashed yellow lines; pavement everywhere else. Clear the air above.
        plan.add(box(SIMD3(x0, g - 1, z0), SIMD3(x0 + side + 1, g + 1, z0 + side + 1)) { x, y, z in
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
                // About one building in five is a Glitch Nest.
                let nest = roll(site, i + 17, j + 29) < 0.22
                if i == middle && j == middle {
                    // The landmark: Wolfie Tower, tallest in town, with ears.
                    plan.building(tower(x0: lx + 1, z0: lz + 1, w: 12, d: 12, ground: g, height: min(54, World.height - g - 12), neon: SB.neonPink, ears: true),
                                  name: "Wolfie Tower", nest: true, heart: true)
                } else if pick < 0.42 {
                    let w = 8 + Int(roll(site, i + 9, j) * 4)
                    let h = 16 + Int(roll(site, i, j + 9) * 26)
                    let neon = roll(site, i + 3, j + 3) < 0.5 ? SB.neonCyan : SB.neonPink
                    plan.building(tower(x0: lx + (lot - w) / 2, z0: lz + (lot - w) / 2, w: w, d: w, ground: g, height: min(h, World.height - g - 8), neon: neon),
                                  name: "Tower", nest: nest)
                } else if pick < 0.6 {
                    plan.building([roundTower(cx: lx + lot / 2, cz: lz + lot / 2, r: 4 + Int(roll(site, i, j + 4) * 2), ground: g, height: 12 + Int(roll(site, i + 4, j) * 20))],
                                  name: "Round Tower", nest: nest)
                } else if pick < 0.72 {
                    plan.building([dome(cx: lx + lot / 2, cz: lz + lot / 2, r: 6, ground: g, floor: planet.terrain.surface)], name: "Dome", nest: nest)
                } else if pick < 0.82 {
                    plan.building([ziggurat(x0: lx + 1, z0: lz + 1, size: lot - 2, ground: g)], name: "Pyramid", nest: nest)
                } else if pick < 0.9 {
                    plan.add(landingPad(x0: lx + 1, z0: lz + 1, size: lot - 2, ground: g))
                } else {
                    for piece in park(x0: lx, z0: lz, size: lot, ground: g, planet: planet) { plan.add(piece) }
                }
            }
        }
    }

    // MARK: Moon bases and mining colonies

    private static func base(_ site: Settlement, planet: Planet, mine: Bool, into plan: inout PlanBuilder) {
        let g = site.ground
        let c = site.center

        // Clear the air and lay a metal floor in a ring path.
        let r = site.radius
        plan.add(box(SIMD3(c.x - r, g - 1, c.y - r), SIMD3(c.x + r + 1, g + 1, c.y + r + 1)) { x, y, z in
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
            plan.add(box(SIMD3(minX, g - 1, minZ), SIMD3(maxX, g + 3, maxZ)) { x, y, z in
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
        plan.add(dome(cx: c.x, cz: c.y, r: 9, ground: g, floor: mine ? B.metal : 13))
        if !mine, planet.terrain.trunk == B.air {
            plan.add(box(SIMD3(c.x - 3, g, c.y - 3), SIMD3(c.x + 4, g + 6, c.y + 4)) { x, y, z in
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
            plan.building([dome(cx: cx, cz: cz, r: 5, ground: g, floor: SB.white, glass: i == 1 ? SB.nightGlass : SB.domeGlass)],
                          name: mine ? "Mine Dome" : "Base Dome", nest: roll(site, i + 31, 7) < 0.4)
        }

        // Radar tower, or a drilling rig at a mine.
        let tx = c.x - 12, tz = c.y + 12
        let towerHeight = mine ? 22 : 15
        // The radar tower or drilling rig is always a nest: the Glitch loves antennas.
        plan.building([box(SIMD3(tx - 1, g, tz - 1), SIMD3(tx + 2, g + towerHeight + 3, tz + 2), far: g + towerHeight + 2, farBlock: B.metal) { x, y, z in
            let k = y - g
            if k >= towerHeight {
                if mine { return x == tx && z == tz ? (k == towerHeight + 2 ? B.lamp : B.crystal) : nil }
                return k == towerHeight ? SB.white : (x == tx && z == tz ? B.lamp : nil)
            }
            let corner = x != tx && z != tz
            if corner { return B.metal }
            return k % 4 == 0 ? B.metal : nil
        }], name: mine ? "Drilling Rig" : "Radar Tower", nest: true)

        // Solar panels in rows.
        let sx = c.x + 8, sz = c.y - 18
        plan.add(box(SIMD3(sx, g, sz), SIMD3(sx + 12, g + 3, sz + 6)) { x, y, z in
            let row = (z - sz) % 3
            if row == 2 { return nil }
            if y == g + 2 { return SB.solar }
            return (x - sx) % 4 == 0 && row == 0 ? B.metal : nil
        })

        // A landing pad, and at a mine, piles of crystals and crates.
        plan.add(landingPad(x0: c.x - 20, z0: c.y - 20, size: 9, ground: g))
        if mine {
            for (px, pz) in [(c.x + 14, c.y + 9), (c.x + 16, c.y + 5), (c.x - 3, c.y - 17)] {
                plan.add(box(SIMD3(px - 2, g, pz - 2), SIMD3(px + 3, g + 4, pz + 3)) { x, y, z in
                    let d = abs(x - px) + abs(z - pz) + (y - g) * 2
                    return d <= 4 ? (d % 2 == 0 ? B.crystal : 17) : nil
                })
            }
            plan.add(box(SIMD3(c.x + 4, g, c.y + 17), SIMD3(c.x + 10, g + 3, c.y + 19)) { x, y, z in
                (x + y + z) % 3 == 0 && y == g + 2 ? nil : B.crate
            })
        }
    }
    // MARK: Wolfie Military's base

    private static func military(_ site: Settlement, planet: Planet, into plan: inout PlanBuilder) {
        let g = site.ground
        let L = MilitaryLayout.self
        let x0 = site.center.x - site.radius, z0 = site.center.y - site.radius
        let n = L.size
        let gateX = x0 + n / 2
        let surface = planet.terrain.surface

        // Tarmac everywhere, a grassy drill yard, and clear air above.
        plan.add(box(SIMD3(x0, g - 1, z0), SIMD3(x0 + n + 1, g + 1, z0 + n + 1)) { x, y, z in
            if y == g { return B.air }
            let lx = x - x0, lz = z - z0
            if L.yard.contains(lx, lz) { return surface }
            // The road in from the gate, with a yellow line.
            if abs(x - gateX) <= 3 && lz < L.yard.z0 { return x == gateX && lz % 4 < 2 ? SB.roadLine : SB.road }
            return (lx / 6 + lz / 6) % 2 == 0 ? SB.road : B.metal
        })

        // The runway: long, with a dashed centre line, edge lights and stripes at both ends.
        let rw = L.runway
        plan.add(box(SIMD3(x0 + rw.x0, g - 1, z0 + rw.z0), SIMD3(x0 + rw.x1, g + 1, z0 + rw.z1)) { x, y, z in
            let lx = x - x0, lz = z - z0
            let edge = lz == rw.z0 || lz == rw.z1 - 1
            if y == g { return edge && lx % 6 == 0 ? B.lamp : B.air }
            let mid = (rw.z0 + rw.z1) / 2
            if lx < rw.x0 + 4 || lx >= rw.x1 - 4 { return (lz - rw.z0) % 2 == 1 && !edge ? SB.white : SB.road }
            if lz == mid && lx % 8 < 4 { return SB.white }
            return SB.road
        })

        // The helipad.
        plan.add(landingPad(x0: x0 + L.helipad.x, z0: z0 + L.helipad.y, size: 13, ground: g))

        // An electric fence all the way round, with a gap for the main gate.
        plan.add(box(SIMD3(x0, g, z0), SIMD3(x0 + n + 1, g + 5, z0 + n + 1)) { x, y, z in
            let lx = x - x0, lz = z - z0
            let onEdge = lx == 0 || lx == n || lz == 0 || lz == n
            guard onEdge else { return nil }
            if lz == 0 && abs(x - gateX) <= 4 { return nil }
            let along = (lx == 0 || lx == n) ? lz : lx
            let k = y - g
            if along % 5 == 0 { return k == 4 ? B.lamp : B.metal }
            return k == 1 || k == 3 ? SB.neonCyan : nil
        })

        // The main gate: an arch with lights and a striped bar, between two guard towers.
        plan.add(box(SIMD3(gateX - 6, g, z0 - 1), SIMD3(gateX + 7, g + 10, z0 + 2), far: g + 9, farBlock: SB.white) { x, y, z in
            let dx = abs(x - gateX), k = y - g
            if dx >= 5 { return k <= 8 ? (k == 8 ? B.lamp : SB.white) : nil }
            if k == 7 { return z == z0 ? (dx % 2 == 0 ? SB.neonPink : SB.white) : SB.white }
            if k == 8 && z == z0 && dx <= 3 { return SB.neonCyan }
            if k == 2 && z == z0 + 1 && dx <= 4 { return dx % 2 == 0 ? SB.white : SB.neonPink }   // the barrier
            return nil
        })
        for (gx, gz) in [(gateX - 9, z0 + 1), (gateX + 9, z0 + 1), (x0 + 2, z0 + 2), (x0 + n - 2, z0 + 2), (x0 + 2, z0 + n - 2), (x0 + n - 2, z0 + n - 2)] {
            plan.add(guardTower(cx: gx, cz: gz, ground: g))
        }

        // The armory: thick metal walls, a wide door, racks of crates inside.
        let a = L.armory
        plan.building([box(SIMD3(x0 + a.x0, g, z0 + a.z0), SIMD3(x0 + a.x1, g + 8, z0 + a.z1), far: g + 8, farBlock: B.metal) { x, y, z in
            let lx = x - x0, lz = z - z0, k = y - g
            let ex = lx == a.x0 || lx == a.x1 - 1, ez = lz == a.z0 || lz == a.z1 - 1
            if k == 7 { return ex || ez ? SB.neonPink : B.metal }
            if ex || ez {
                // Door on the south side, facing the yard.
                if lz == a.z1 - 1 && abs(lx - (a.x0 + a.x1) / 2) <= 1 && k >= 1 && k <= 3 { return B.air }
                if k == 5 && !(ex && ez) && (lx + lz) % 3 == 0 { return SB.nightGlass }
                return B.metal
            }
            if k == 0 { return SB.white }
            // Crates along the inside walls.
            let rack = lx == a.x0 + 1 || lx == a.x1 - 2 || lz == a.z0 + 1
            return rack && k <= 2 ? B.crate : B.air
        }], name: "Armory", nest: false)

        // Barracks: long and low with windows and a teal roof.
        let br = L.barracks
        plan.building([box(SIMD3(x0 + br.x0, g, z0 + br.z0), SIMD3(x0 + br.x1, g + 7, z0 + br.z1), far: g + 7, farBlock: SB.roofTeal) { x, y, z in
            let lx = x - x0, lz = z - z0, k = y - g
            let ex = lx == br.x0 || lx == br.x1 - 1, ez = lz == br.z0 || lz == br.z1 - 1
            if k == 6 { return SB.roofTeal }
            if ex || ez {
                if lz == br.z1 - 1 && (lx - br.x0) % 8 == 4 && k >= 1 && k <= 3 { return B.air }   // doors
                if (k == 2 || k == 3) && (lx + lz) % 3 != 0 && !(ex && ez) { return SB.nightGlass }
                return SB.white
            }
            return k == 0 ? SB.white : B.air
        }], name: "Barracks", nest: false)

        // Headquarters: a tower with a radar dish on top.
        let hq = L.hq
        plan.building(tower(x0: x0 + hq.x, z0: z0 + hq.y, w: 10, d: 10, ground: g, height: 22, neon: SB.neonCyan), name: "Headquarters", nest: false)
        let rx = x0 + hq.x + 5, rz = z0 + hq.y + 5, rTop = g + 28
        plan.add(box(SIMD3(rx - 3, rTop, rz - 3), SIMD3(rx + 4, rTop + 4, rz + 4), far: rTop + 3, farBlock: SB.white) { x, y, z in
            let dx = x - rx, dz = z - rz, k = y - rTop
            if dx == 0 && dz == 0 { return k == 3 ? B.lamp : B.metal }
            // A tilted dish facing south.
            let tilt = dz + 1
            return k == max(0, min(3, tilt)) && dx * dx + dz * dz <= 9 && dz >= -1 ? SB.white : nil
        })

        // Hangars facing the runway, open at the front.
        for hx in L.hangars {
            let hz0 = L.hangarZ0, hz1 = L.hangarZ1
            plan.building([box(SIMD3(x0 + hx, g, z0 + hz0), SIMD3(x0 + hx + L.hangarWidth, g + 11, z0 + hz1), far: g + 10, farBlock: B.metal) { x, y, z in
                let lx = x - x0 - hx, lz = z - z0, k = y - g
                let w = L.hangarWidth
                // A curved roof: higher in the middle.
                let fromMiddle = abs(Float(lx) - Float(w - 1) / 2)
                let roof = 10 - Int(fromMiddle * fromMiddle / 9)
                if k > roof { return nil }
                if k == roof { return lx % 4 == 0 ? SB.neonCyan : B.metal }
                if lx == 0 || lx == w - 1 { return k % 3 == 2 ? SB.nightGlass : B.metal }
                if lz == hz0 { return B.metal }
                if lz == hz1 - 1 && k == roof - 1 { return SB.white }   // a beam over the open door
                return k == 0 ? SB.white : B.air
            }], name: "Hangar", nest: false)
        }

        // A flagpole in the middle of the yard, with a pink-and-white flag.
        let fx = x0 + L.flag.x, fz = z0 + L.flag.y
        plan.add(box(SIMD3(fx, g, fz), SIMD3(fx + 6, g + 13, fz + 1), far: g + 12, farBlock: SB.neonPink) { x, y, _ in
            let k = y - g, dx = x - fx
            if dx == 0 { return k == 12 ? B.lamp : B.metal }
            guard k >= 8 && k <= 11 else { return nil }
            return (k + dx) % 2 == 0 ? SB.neonPink : SB.white
        })

        // Obstacle course in the yard: low walls to jump over.
        let yd = L.yard
        plan.add(box(SIMD3(x0 + yd.x0 + 2, g, z0 + yd.z1 - 4), SIMD3(x0 + yd.x1 - 2, g + 2, z0 + yd.z1 - 1)) { x, _, z in
            (x - x0) % 5 == 0 && z == z0 + yd.z1 - 3 ? SB.white : nil
        })
    }

    /// A small lookout tower: four legs, a platform and a lamp.
    private static func guardTower(cx: Int, cz: Int, ground g: Int) -> Settlement.Piece {
        box(SIMD3(cx - 1, g, cz - 1), SIMD3(cx + 2, g + 10, cz + 2), far: g + 9, farBlock: B.metal) { x, y, z in
            let k = y - g
            let corner = x != cx && z != cz
            if k == 6 { return SB.white }
            if k == 7 { return corner ? B.metal : nil }
            if k == 8 { return x == cx && z == cz ? nil : (corner ? SB.neonCyan : nil) }
            if k == 9 { return x == cx && z == cz ? B.lamp : nil }
            return corner ? B.metal : nil
        }
    }
}

/// Where things are at the military base, from its north-west corner. Shared by the building
/// plans and the troops, drones and parked vehicles.
enum MilitaryLayout {
    struct Area: Sendable {
        let x0, z0, x1, z1: Int
        func contains(_ x: Int, _ z: Int) -> Bool { x >= x0 && x < x1 && z >= z0 && z < z1 }
        var center: SIMD2<Float> { SIMD2(Float(x0 + x1) / 2, Float(z0 + z1) / 2) }
    }
    static let size = 92
    static let armory = Area(x0: 6, z0: 8, x1: 22, z1: 22)
    static let barracks = Area(x0: 6, z0: 26, x1: 26, z1: 36)
    static let hq = SIMD2<Int>(60, 8)
    static let helipad = SIMD2<Int>(74, 8)
    static let yard = Area(x0: 30, z0: 24, x1: 62, z1: 44)
    static let flag = SIMD2<Int>(46, 22)
    static let hangars = [8, 30, 52]
    static let hangarWidth = 18
    static let hangarZ0 = 48
    static let hangarZ1 = 62
    static let runway = Area(x0: 4, z0: 72, x1: 88, z1: 84)

    /// The base's north-west corner, in the world.
    static var origin: SIMD2<Int> {
        TerrainGenerator.militaryBase &- SIMD2(repeating: size / 2)
    }
}

// MARK: - Wolfie Station

/// The space station over Wolfie World, as a little world of its own: a deck floating in space
/// with a big hangar you can fly into, ships parked inside and more coming and going.
enum StationPlan {
    /// The top of the deck: you walk at this height.
    static let deck = 40
    /// The hangar: open at both ends (north and south) for ships to fly through.
    static let hangarHalfWidth = 32
    static let hangarHalfDepth = 26
    static let hangarRoof = deck + 26
    /// surfaceY looks down from here, so the hangar roof isn't taken for the ground.
    static let scanTop = deck + 24
    /// Pads outside the hangar where visiting ships land.
    static let trafficPads: [SIMD2<Int>] = [SIMD2(46, 30), SIMD2(-46, 34)]
    /// Parked inside the hangar: (kind, x, z, which way it faces).
    static let parking: [(String, Int, Int, Float)] = [
        ("comet", 14, -12, .pi), ("hauler", 14, 12, .pi), ("zoomer", -13, -14, .pi),
        ("hoverbike", 0, 20, .pi), ("buggy", -24, 18, .pi),
    ]

    static func onDeck(_ x: Int, _ z: Int) -> Bool {
        abs(x) <= 64 && abs(z) <= 64 && abs(x) + abs(z) <= 100
    }

    /// The ground height (first empty block) of a column; 0 off the edge, where there's only space.
    static func height(_ x: Int, _ z: Int) -> Int {
        onDeck(x, z) ? deck : 0
    }

    static func pieces(x0: Int, z0: Int, size: Int) -> [Settlement.Piece] {
        Settlements.station.filter { $0.max.x > x0 && $0.min.x < x0 + size && $0.max.z > z0 && $0.min.z < z0 + size }
    }
}

extension Settlements {
    static let station: [Settlement.Piece] = {
        let d = StationPlan.deck
        let hw = StationPlan.hangarHalfWidth, hd = StationPlan.hangarHalfDepth, roof = StationPlan.hangarRoof
        var pieces: [Settlement.Piece] = []

        // The deck: four blocks thick, with a grid of light lines on top and lamps underneath.
        pieces.append(box(SIMD3(-65, d - 4, -65), SIMD3(66, d + 2, 66), far: d, farBlock: B.metal) { x, y, z in
            guard StationPlan.onDeck(x, z) else { return nil }
            let edge = !StationPlan.onDeck(x + 1, z) || !StationPlan.onDeck(x - 1, z) || !StationPlan.onDeck(x, z + 1) || !StationPlan.onDeck(x, z - 1)
            let k = y - d
            if k >= 0 {
                // A glass rail round the edge, on metal posts, so nobody walks off into space.
                guard edge else { return nil }
                return (x + z) % 4 == 0 ? (k == 1 ? B.lamp : B.metal) : SB.domeGlass
            }
            if k == -1 {
                if edge { return SB.neonCyan }
                if floorMod(x, 16) == 0 && floorMod(z, 16) == 0 { return B.lamp }
                if floorMod(x, 8) == 0 || floorMod(z, 8) == 0 { return SB.white }
                return B.metal
            }
            if k == -4 { return floorMod(x, 6) == 0 && floorMod(z, 6) == 0 ? B.lamp : B.metal }
            return edge ? SB.white : B.metal
        })

        // The station's spine, hanging down below the deck, with glowing rings.
        pieces.append(box(SIMD3(-9, d - 30, -9), SIMD3(10, d - 4, 10), far: d - 4, farBlock: B.metal) { x, y, z in
            let k = d - 4 - y            // 1 ... 26 down
            let r = 8 - k / 4
            let dist = (Float(x * x + z * z)).squareRoot()
            guard dist <= Float(max(2, r)) + 0.4 else { return nil }
            if dist > Float(max(2, r)) - 0.8 { return k % 5 == 0 ? SB.neonCyan : B.metal }
            return k == 26 ? B.lamp : nil
        })

        // The hangar: tall walls with windows out to space, a roof with skylights, open ends.
        pieces.append(box(SIMD3(-hw, d, -hd), SIMD3(hw + 1, roof + 1, hd + 1), far: roof + 1, farBlock: B.metal) { x, y, z in
            let wall = abs(x) == hw
            let endFrame = abs(z) == hd
            let k = y - d
            if y == roof {
                if endFrame { return SB.neonPink }
                return floorMod(x, 8) < 2 && abs(x) < hw - 2 ? SB.domeGlass : B.metal
            }
            if wall {
                if k == roof - d - 2 { return SB.neonCyan }
                if k >= 6 && k <= 12 && abs(z) < hd - 1 { return floorMod(z, 6) == 0 ? B.metal : SB.nightGlass }
                return endFrame ? SB.white : B.metal
            }
            // Beams across the open ends.
            if endFrame && y == roof - 1 { return SB.white }
            // Lights hanging under the roof.
            if y == roof - 1 && floorMod(x, 12) == 0 && floorMod(z, 12) == 0 { return B.lamp }
            return nil
        })
        // Glowing guide lines on the hangar floor, leading ships in.
        pieces.append(box(SIMD3(-2, d - 1, -hd), SIMD3(3, d, hd + 1)) { x, _, z in
            abs(x) == 2 && floorMod(z, 4) < 2 ? SB.neonCyan : nil
        })

        // Pads: the starship's, one for each parked ship, and two outside for visitors.
        let pad = TerrainGenerator.pad
        pieces.append(landingPad(x0: pad.x - 5, z0: pad.y - 5, size: 11, ground: d))
        for (kind, x, z, _) in StationPlan.parking where kind != "hoverbike" && kind != "buggy" {
            pieces.append(landingPad(x0: x - 5, z0: z - 5, size: 11, ground: d))
        }
        for p in StationPlan.trafficPads {
            pieces.append(landingPad(x0: p.x - 6, z0: p.y - 6, size: 13, ground: d))
        }

        // Outside: the control tower, a greenhouse dome, solar arrays and an antenna mast.
        pieces.append(roundTower(cx: 44, cz: -42, r: 6, ground: d, height: 22))
        pieces.append(dome(cx: -44, cz: -40, r: 10, ground: d, floor: 13))
        pieces.append(box(SIMD3(-50, d, -46), SIMD3(-37, d + 6, -33)) { x, y, z in
            // Glowing plants under the dome.
            if floorMod(x * 3 + z, 5) == 0 && y <= d + 1 { return 17 }
            if floorMod(x + z * 3, 7) == 0 && y < d + 4 { return 16 }
            return nil
        })
        for row in 0..<3 {
            let sz = 40 + row * 5
            pieces.append(box(SIMD3(-16, d, sz), SIMD3(17, d + 3, sz + 3)) { x, y, z in
                if y == d + 2 { return z < sz + 2 ? SB.solar : nil }
                return floorMod(x, 6) == 0 && z == sz ? B.metal : nil
            })
        }
        pieces.append(box(SIMD3(54, d, -2), SIMD3(55, d + 30, -1), far: d + 30, farBlock: B.metal) { _, y, _ in
            y == d + 29 ? B.lamp : (floorMod(y, 6) == 0 ? SB.neonPink : B.metal)
        })
        return pieces
    }()
}
