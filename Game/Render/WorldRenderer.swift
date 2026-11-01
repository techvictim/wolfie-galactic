import Foundation
import RealityKit
import simd

/// Keeps the land around the player on screen as they move: detailed chunks close by,
/// simple far terrain out to the horizon. Chunks are made and meshed in the background.
@MainActor
final class WorldRenderer {
    let root = Entity()
    private(set) var world: World
    /// Textured blocks up close.
    private let material: UnlitMaterial?
    /// Plain colours for the far-away land.
    private let farMaterial: UnlitMaterial?
    /// See-through blocks (the Glitch); changed to make them pulse.
    private var glassMaterial: UnlitMaterial?
    /// Chunks changed by blasts waiting to be rebuilt, a few each frame.
    private var changedQueue: [ChunkKey] = []

    private var detail: [ChunkKey: ModelEntity] = [:]
    private var far: [TileKey: (entity: ModelEntity, skipped: Set<ChunkKey>, cell: Int)] = [:]
    private var pendingDetail = Set<ChunkKey>()
    private var pendingFar = Set<TileKey>()
    private var detailQueue: [ChunkKey] = []
    private var farQueue: [TileKey] = []
    private var wantedTiles = Set<TileKey>()
    private var running = 0
    /// Bumped when the world is swapped, so late background work is thrown away.
    private var generation = 0
    private var focusChunk: ChunkKey?
    private var detailRadius = 0
    private var farRadius = 0
    private var detailChanged = false
    private var lastFarCheck = Date.distantPast

    private static let maxJobs = 3
    private static let detailBatch = 4

    init(world: World, material: UnlitMaterial?, farMaterial: UnlitMaterial?, glassMaterial: UnlitMaterial?) {
        self.world = world
        self.material = material
        self.farMaterial = farMaterial
        self.glassMaterial = glassMaterial
    }

    /// The Glitch's see-through blocks pulse: swap in a new material everywhere.
    func setGlass(_ material: UnlitMaterial) {
        glassMaterial = material
        for entity in detail.values {
            if let glass = entity.children.first as? ModelEntity, glass.model != nil {
                glass.model?.materials = [material]
            }
        }
    }

    /// Show a different world (a new planet, or a fresh start).
    func reset(world: World) {
        self.world = world
        generation += 1
        for entity in detail.values { entity.removeFromParent() }
        for tile in far.values { tile.entity.removeFromParent() }
        detail.removeAll()
        far.removeAll()
        pendingDetail.removeAll()
        pendingFar.removeAll()
        detailQueue.removeAll()
        farQueue.removeAll()
        changedQueue.removeAll()
        wantedTiles.removeAll()
        focusChunk = nil
        running = 0
    }

    /// True once the ground right around a point is on screen.
    func isReady(around point: SIMD3<Float>) -> Bool {
        let c = World.key(x: Int(floor(point.x)), z: Int(floor(point.z)))
        for dz in -2...2 {
            for dx in -2...2 where detail[ChunkKey(x: c.x + dx, z: c.z + dz)] == nil {
                return false
            }
        }
        return true
    }

    // MARK: Every frame

    func update(focus: SIMD3<Float>, detailRadius newDetail: Int, farRadius newFar: Int) {
        remeshChanged()

        let center = World.key(x: Int(floor(focus.x)), z: Int(floor(focus.z)))
        if center != focusChunk || newDetail != detailRadius || newFar != farRadius {
            focusChunk = center
            detailRadius = newDetail
            farRadius = newFar
            plan(around: center)
        }
        // While nearby chunks are still arriving, refresh the far land at most once a second.
        let settled = detailQueue.isEmpty && pendingDetail.isEmpty
        if detailChanged && (settled || Date().timeIntervalSince(lastFarCheck) > 1) {
            detailChanged = false
            checkFarTiles()
        }
        startJobs()
    }

    /// Work out which chunks and far tiles should be on screen.
    private func plan(around center: ChunkKey) {
        let r = detailRadius
        // Drop detailed chunks that are now too far away (with a little slack).
        for (key, entity) in detail {
            let dx = key.x - center.x
            let dz = key.z - center.z
            if dx * dx + dz * dz > (r + 1) * (r + 1) {
                entity.removeFromParent()
                detail[key] = nil
                detailChanged = true
            }
        }
        // Queue missing detailed chunks, nearest first.
        var wanted: [(ChunkKey, Int)] = []
        for dz in -r...r {
            for dx in -r...r where dx * dx + dz * dz <= r * r {
                let key = ChunkKey(x: center.x + dx, z: center.z + dz)
                if detail[key] == nil && !pendingDetail.contains(key) {
                    wanted.append((key, dx * dx + dz * dz))
                }
            }
        }
        detailQueue = wanted.sorted { $0.1 < $1.1 }.map { $0.0 }

        // Far tiles out to the far radius.
        let tileReach = farRadius / TileKey.blocks + 1
        let centerTile = TileKey.containing(center)
        let focusX = Float(center.x * World.chunkSize)
        let focusZ = Float(center.z * World.chunkSize)
        var tiles = Set<TileKey>()
        for dz in -tileReach...tileReach {
            for dx in -tileReach...tileReach {
                let tile = TileKey(x: centerTile.x + dx, z: centerTile.z + dz)
                // Distance to the nearest point of the tile.
                let minX = Float(tile.x * TileKey.blocks)
                let minZ = Float(tile.z * TileKey.blocks)
                let nx = min(max(focusX, minX), minX + Float(TileKey.blocks))
                let nz = min(max(focusZ, minZ), minZ + Float(TileKey.blocks))
                if simd_distance(SIMD2<Float>(nx, nz), SIMD2<Float>(focusX, focusZ)) <= Float(farRadius) {
                    tiles.insert(tile)
                }
            }
        }
        for (tile, value) in far where !tiles.contains(tile) {
            value.entity.removeFromParent()
            far[tile] = nil
        }
        wantedTiles = tiles
        checkFarTiles()

        world.forget(outside: r + 4, of: center)
    }

    /// Queue far tiles that are missing, or whose detailed area changed.
    private func checkFarTiles() {
        lastFarCheck = Date()
        var shown: [TileKey: Set<ChunkKey>] = [:]
        for key in detail.keys {
            shown[TileKey.containing(key), default: []].insert(key)
        }
        let centerTile = focusChunk.map(TileKey.containing) ?? TileKey(x: 0, z: 0)
        var queue: [(TileKey, Int)] = []
        for tile in wantedTiles where !pendingFar.contains(tile) {
            let skipped = shown[tile] ?? []
            let dx = tile.x - centerTile.x
            let dz = tile.z - centerTile.z
            if let existing = far[tile], existing.skipped == skipped, existing.cell == WorldRenderer.cell(dx, dz) { continue }
            queue.append((tile, dx * dx + dz * dz))
        }
        farQueue = queue.sorted { $0.1 < $1.1 }.map { $0.0 }
    }

    // MARK: Background work

    private func startJobs() {
        while running < WorldRenderer.maxJobs {
            if !detailQueue.isEmpty {
                let batch = Array(detailQueue.prefix(WorldRenderer.detailBatch))
                detailQueue.removeFirst(batch.count)
                startDetail(batch)
            } else if !farQueue.isEmpty {
                let tile = farQueue.removeFirst()
                startFar(tile)
            } else {
                break
            }
        }
    }

    private struct DetailResult: Sendable {
        let key: ChunkKey
        let mesh: VoxelMesher.ChunkMeshes
    }

    private func startDetail(_ keys: [ChunkKey]) {
        // Hand over the chunks already in memory; the rest are made in the background.
        var known: [ChunkKey: [UInt8]] = [:]
        for key in keys {
            for k in [key, ChunkKey(x: key.x + 1, z: key.z), ChunkKey(x: key.x - 1, z: key.z),
                      ChunkKey(x: key.x, z: key.z + 1), ChunkKey(x: key.x, z: key.z - 1)] {
                if let blocks = world.cachedChunk(k) { known[k] = blocks }
            }
            pendingDetail.insert(key)
        }
        let generator = world.generator
        let token = generation
        running += 1
        Task.detached(priority: .userInitiated) { [weak self] in
            var chunks = known
            var made: [ChunkKey: [UInt8]] = [:]
            func get(_ k: ChunkKey) -> [UInt8] {
                if let blocks = chunks[k] { return blocks }
                let blocks = generator.generateChunk(k)
                chunks[k] = blocks
                made[k] = blocks
                return blocks
            }
            var results: [DetailResult] = []
            for key in keys {
                let mesh = VoxelMesher.chunk(
                    get(key),
                    east: get(ChunkKey(x: key.x + 1, z: key.z)),
                    west: get(ChunkKey(x: key.x - 1, z: key.z)),
                    south: get(ChunkKey(x: key.x, z: key.z + 1)),
                    north: get(ChunkKey(x: key.x, z: key.z - 1))
                )
                results.append(DetailResult(key: key, mesh: mesh))
            }
            let finished = results
            let madeChunks = made
            await self?.finishDetail(finished, made: madeChunks, token: token)
        }
    }

    private func finishDetail(_ results: [DetailResult], made: [ChunkKey: [UInt8]], token: Int) {
        guard token == generation else { return }
        running -= 1
        for (key, blocks) in made { world.store(key, blocks) }
        for result in results {
            pendingDetail.remove(result.key)
            guard isWanted(result.key) else { continue }
            show(result.mesh, for: result.key)
        }
        detailChanged = true
    }

    /// Smaller columns for the far tiles right around you.
    private static func cell(_ dx: Int, _ dz: Int) -> Int {
        max(abs(dx), abs(dz)) <= 1 ? 2 : 4
    }

    private func startFar(_ tile: TileKey) {
        let centerTile = focusChunk.map(TileKey.containing) ?? TileKey(x: 0, z: 0)
        let cell = WorldRenderer.cell(tile.x - centerTile.x, tile.z - centerTile.z)
        var skipped = Set<ChunkKey>()
        for key in detail.keys where TileKey.containing(key) == tile { skipped.insert(key) }
        pendingFar.insert(tile)
        let generator = world.generator
        let token = generation
        let skip = skipped
        running += 1
        Task.detached(priority: .utility) { [weak self] in
            let mesh = FarMesher.tile(tile, generator: generator, skipping: skip, cell: cell)
            await self?.finishFar(tile, mesh: mesh, skipped: skip, cell: cell, token: token)
        }
    }

    private func finishFar(_ tile: TileKey, mesh builder: MeshBuilder, skipped: Set<ChunkKey>, cell: Int, token: Int) {
        guard token == generation else { return }
        running -= 1
        pendingFar.remove(tile)
        guard wantedTiles.contains(tile) else { return }
        let entity = far[tile]?.entity ?? {
            let e = ModelEntity()
            e.position = SIMD3<Float>(Float(tile.x * TileKey.blocks), 0, Float(tile.z * TileKey.blocks))
            root.addChild(e)
            return e
        }()
        if let material = farMaterial, let mesh = try? builder.mesh(name: "far-\(tile.x)-\(tile.z)") {
            entity.model = ModelComponent(mesh: mesh, materials: [material])
            entity.isEnabled = true
        } else {
            entity.model = nil
            entity.isEnabled = false
        }
        far[tile] = (entity, skipped, cell)
        // The detailed area may have moved on while this was being built.
        detailChanged = true
    }

    private func isWanted(_ key: ChunkKey) -> Bool {
        guard let c = focusChunk else { return false }
        let dx = key.x - c.x
        let dz = key.z - c.z
        return dx * dx + dz * dz <= (detailRadius + 1) * (detailRadius + 1)
    }

    private func show(_ meshes: VoxelMesher.ChunkMeshes, for key: ChunkKey) {
        let entity = detail[key] ?? {
            let e = ModelEntity()
            e.position = SIMD3<Float>(Float(key.x * World.chunkSize), 0, Float(key.z * World.chunkSize))
            // The see-through part is always the first child.
            e.addChild(ModelEntity())
            root.addChild(e)
            return e
        }()
        if let material, let mesh = try? meshes.solid.mesh(name: "chunk-\(key.x)-\(key.z)") {
            entity.model = ModelComponent(mesh: mesh, materials: [material])
        } else {
            entity.model = nil
        }
        if let glass = entity.children.first as? ModelEntity {
            if let glassMaterial, let mesh = try? meshes.glass.mesh(name: "glass-\(key.x)-\(key.z)") {
                glass.model = ModelComponent(mesh: mesh, materials: [glassMaterial])
                glass.isEnabled = true
            } else {
                glass.model = nil
                glass.isEnabled = false
            }
        }
        entity.isEnabled = true
        detail[key] = entity
    }

    // MARK: Building and blasting

    /// Rebuild chunks that just changed. A few each frame, nearest first, so a big blast
    /// doesn't freeze the game while every chunk it touched is rebuilt at once.
    private func remeshChanged() {
        for key in world.takeChanged() where detail[key] != nil && !changedQueue.contains(key) {
            changedQueue.append(key)
        }
        guard !changedQueue.isEmpty else { return }
        if let focus = focusChunk, changedQueue.count > 1 {
            changedQueue.sort { abs($0.x - focus.x) + abs($0.z - focus.z) < abs($1.x - focus.x) + abs($1.z - focus.z) }
        }
        for _ in 0..<min(3, changedQueue.count) {
            let key = changedQueue.removeFirst()
            guard detail[key] != nil else { continue }
            let mesh = VoxelMesher.chunk(
                world.chunkData(key),
                east: world.chunkData(ChunkKey(x: key.x + 1, z: key.z)),
                west: world.chunkData(ChunkKey(x: key.x - 1, z: key.z)),
                south: world.chunkData(ChunkKey(x: key.x, z: key.z + 1)),
                north: world.chunkData(ChunkKey(x: key.x, z: key.z - 1))
            )
            show(mesh, for: key)
        }
    }
}
