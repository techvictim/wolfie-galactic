import Foundation
import simd

/// The big-block world of one planet. It has no edges: chunks of 16 x 16 columns,
/// 96 blocks tall, are made from the planet's seed as they are needed.
/// One big block = 1 metre. The host's copy of this is the truth in multiplayer.
final class World {
    static let chunkSize = 16
    static let height = 96
    static let chunkVolume = chunkSize * chunkSize * height

    let planet: Planet
    let generator: TerrainGenerator
    var seed: UInt64 { planet.seed }

    /// Chunks in memory: generated ones near the player, plus every chunk anyone has changed.
    private(set) var chunks: [ChunkKey: [UInt8]] = [:]
    /// Chunks players have changed. Only these are saved.
    private(set) var edited = Set<ChunkKey>()
    /// Chunks whose look changed and need a new mesh.
    private var changed = Set<ChunkKey>()
    /// Where machines are (jump pads, teleporters…), by block id.
    private(set) var machines: [UInt8: Set<SIMD3<Int>>] = [:]
    private static let machineIDs: ClosedRange<UInt8> = 31...34

    init(planet: Planet) {
        self.planet = planet
        self.generator = TerrainGenerator(planet: planet)
    }

    convenience init?(planet: Planet, save: SaveFile) {
        guard save.version == SaveFile.currentVersion, save.height == World.height else { return nil }
        self.init(planet: planet)
        apply(edits: save.edits)
    }

    /// A copy of someone else's world: the planet plus the chunks they've changed.
    convenience init(planet: Planet, edits: [String: Data]) {
        self.init(planet: planet)
        apply(edits: edits)
    }

    /// Put in changed chunks, as saved by compressedEdits().
    private func apply(edits: [String: Data]) {
        for (name, data) in edits {
            let parts = name.split(separator: ",").compactMap { Int($0) }
            guard parts.count == 2,
                  let raw = try? WorldStore.decompress(data),
                  raw.count == World.chunkVolume else { continue }
            let key = ChunkKey(x: parts[0], z: parts[1])
            let blocks = [UInt8](raw)
            chunks[key] = blocks
            edited.insert(key)
            // Find machines built in this chunk.
            for (i, id) in blocks.enumerated() where World.machineIDs.contains(id) {
                let lx = i % World.chunkSize
                let lz = (i / World.chunkSize) % World.chunkSize
                let y = i / (World.chunkSize * World.chunkSize)
                machines[id, default: []].insert(SIMD3(key.x * World.chunkSize + lx, y, key.z * World.chunkSize + lz))
            }
        }
    }

    // MARK: Chunks

    static func key(x: Int, z: Int) -> ChunkKey {
        ChunkKey(x: floorDiv(x, chunkSize), z: floorDiv(z, chunkSize))
    }

    /// The chunk's blocks, making it now if needed.
    func chunkData(_ key: ChunkKey) -> [UInt8] {
        if let blocks = chunks[key] { return blocks }
        let blocks = generator.generateChunk(key)
        chunks[key] = blocks
        return blocks
    }

    /// The chunk's blocks only if already in memory.
    func cachedChunk(_ key: ChunkKey) -> [UInt8]? {
        chunks[key]
    }

    /// Keep a chunk made in the background, unless one is already here.
    func store(_ key: ChunkKey, _ blocks: [UInt8]) {
        if chunks[key] == nil { chunks[key] = blocks }
    }

    /// Drop unchanged chunks far from the player to save memory. They can be made again.
    func forget(outside radius: Int, of center: ChunkKey) {
        for key in Array(chunks.keys) where !edited.contains(key) {
            let dx = key.x - center.x
            let dz = key.z - center.z
            if dx * dx + dz * dz > radius * radius { chunks[key] = nil }
        }
    }

    func takeChanged() -> Set<ChunkKey> {
        let result = changed
        changed.removeAll()
        return result
    }

    /// Goes up every time a block changes, so things can tell when to look again.
    private(set) var revision = 0
    /// Blocks that just became air, so the game can check whether anything above lost its support.
    var removed: [SIMD3<Int>] = []

    // MARK: Blocks

    @inline(__always)
    func inBounds(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        y >= 0 && y < World.height
    }

    /// Block id, or air above or below the world.
    func block(_ x: Int, _ y: Int, _ z: Int) -> UInt8 {
        guard y >= 0, y < World.height else { return B.air }
        let key = World.key(x: x, z: z)
        let blocks = chunks[key] ?? chunkData(key)
        let i = TerrainGenerator.index(floorMod(x, World.chunkSize), y, floorMod(z, World.chunkSize))
        return blocks[i]
    }

    func block(_ p: SIMD3<Int>) -> UInt8 {
        block(p.x, p.y, p.z)
    }

    /// For collisions: the bottom of the world is solid, above the top is open sky.
    func isSolidForPhysics(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        if y < 0 { return true }
        if y >= World.height { return false }
        return block(x, y, z) != B.air
    }

    /// Change a block and mark the chunks that need a new mesh.
    func set(_ p: SIMD3<Int>, _ id: UInt8) {
        guard p.y >= 0, p.y < World.height else { return }
        let key = World.key(x: p.x, z: p.z)
        if chunks[key] == nil { chunks[key] = generator.generateChunk(key) }
        let lx = floorMod(p.x, World.chunkSize)
        let lz = floorMod(p.z, World.chunkSize)
        let index = TerrainGenerator.index(lx, p.y, lz)
        if let old = chunks[key]?[index], World.machineIDs.contains(old) { machines[old]?.remove(p) }
        if id == B.air, let old = chunks[key]?[index], old != B.air, removed.count < 20_000 { removed.append(p) }
        if World.machineIDs.contains(id) { machines[id, default: []].insert(p) }
        chunks[key]?[index] = id
        revision &+= 1
        edited.insert(key)
        changed.insert(key)
        if lx == 0 { changed.insert(ChunkKey(x: key.x - 1, z: key.z)) }
        if lx == World.chunkSize - 1 { changed.insert(ChunkKey(x: key.x + 1, z: key.z)) }
        if lz == 0 { changed.insert(ChunkKey(x: key.x, z: key.z - 1)) }
        if lz == World.chunkSize - 1 { changed.insert(ChunkKey(x: key.x, z: key.z + 1)) }
    }

    // MARK: Places

    /// The first empty y above the highest solid block in a column.
    func surfaceY(x: Int, z: Int) -> Int {
        var y = World.height - 1
        while y >= 0 && block(x, y, z) == B.air { y -= 1 }
        return y + 1
    }

    func spawnPoint() -> SIMD3<Float> {
        let s = TerrainGenerator.spawn
        return SIMD3<Float>(Float(s.x) + 0.5, Float(surfaceY(x: s.x, z: s.y)), Float(s.y) + 0.5)
    }

    /// Centre of the landing pad where the starship parks.
    var padCenter: SIMD2<Int> {
        TerrainGenerator.pad
    }

    /// Where you stand after landing: just in front of the starship.
    func arrivalPoint() -> SIMD3<Float> {
        let x = padCenter.x
        let z = padCenter.y + 7
        return SIMD3<Float>(Float(x) + 0.5, Float(surfaceY(x: x, z: z)), Float(z) + 0.5)
    }

    // MARK: Saving

    /// Every changed chunk, compressed, keyed "x,z".
    func compressedEdits() throws -> [String: Data] {
        var result: [String: Data] = [:]
        for key in edited {
            guard let blocks = chunks[key] else { continue }
            result["\(key.x),\(key.z)"] = try WorldStore.compress(Data(blocks))
        }
        return result
    }
}
