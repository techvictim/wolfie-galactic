import Foundation
import RealityKit
import simd

/// Space around a planet: the planet as a giant ball of blocks, the spaceport (around Wolfie
/// World), your ship, and far away the other planets, a sun, block nebulae and galaxies.
///
/// `root` holds things at real positions. `far` holds the distant scenery; the game keeps it
/// centred on the camera so it always looks far away, like the sky.
@MainActor
final class SpaceScene {
    let root = Entity()
    let far = Entity()
    /// Hyperspace streaks; the game parents this to the camera.
    let warp = Entity()

    private(set) var planetID = ""
    /// Radius of the planet you're orbiting, in blocks.
    private(set) var planetRadius: Float = 150
    /// The glowing air around the planet you're orbiting.
    private var atmosphere = Entity()

    /// Where another planet hangs in the sky, seen from here.
    static func direction(of id: String) -> SIMD3<Float>? {
        directions[id]
    }

    /// Fly inside this and you start coming down through the atmosphere.
    var atmosphereRadius: Float { planetRadius * 1.22 }
    private var planetModel: Entity?
    private var farPlanets: [String: Entity] = [:]
    private var spaceport: Entity?
    private var shipModel: Entity?
    private var shipKind: VehicleKind?
    private var dockModels: [Entity?] = []
    private var warpLines: [(entity: ModelEntity, speed: Float)] = []
    private var built = false

    /// Each block of a planet seen from space is this many blocks wide.
    static let voxelScale: Float = 14
    static let spaceportPosition = SIMD3<Float>(250, 110, -170)
    private static let spaceportScale: Float = 2
    /// The docking pads, as (distance from the station's centre, angle), before scaling.
    private static let pads: [(Float, Float)] = [(23, 0), (23, 2 * .pi / 3), (23, 4 * .pi / 3)]
    /// How high the pads' decks are above the bottom of the station model, before scaling.
    private static let padHeight: Float = 10.4

    /// Fixed directions for planets seen far away.
    private static let directions: [String: SIMD3<Float>] = [
        "wolfie-world": simd_normalize(SIMD3(-0.62, 0.22, -0.75)),
        "pup-moon": simd_normalize(SIMD3(0.72, 0.3, -0.62)),
        "glimmer": simd_normalize(SIMD3(0.25, -0.12, 0.96))
    ]

    // MARK: Building

    func buildOnce() {
        guard !built else { return }
        built = true
        far.addChild(SpaceScene.makeSun())
        far.addChild(SpaceScene.makeNebula(direction: SIMD3(0.55, 0.35, 0.75), colors: [SIMD3(1, 0.35, 0.8), SIMD3(0.55, 0.3, 1)], seed: 1))
        far.addChild(SpaceScene.makeNebula(direction: SIMD3(-0.8, -0.1, 0.4), colors: [SIMD3(0.3, 0.9, 1), SIMD3(0.35, 0.5, 1)], seed: 2))
        far.addChild(SpaceScene.makeNebula(direction: SIMD3(-0.1, 0.75, -0.6), colors: [SIMD3(1, 0.6, 0.3), SIMD3(1, 0.35, 0.5)], seed: 3))
        far.addChild(SpaceScene.makeGalaxy(direction: SIMD3(0.9, 0.45, -0.1), tilt: 0.9, seed: 4))
        far.addChild(SpaceScene.makeGalaxy(direction: SIMD3(-0.45, 0.6, 0.65), tilt: -0.5, seed: 5))
        far.addChild(SpaceScene.makeGalaxy(direction: SIMD3(-0.3, -0.5, -0.8), tilt: 0.3, seed: 6))
        buildWarp()
        warp.isEnabled = false
    }

    /// Orbit a different planet.
    func setPlanet(_ id: String) {
        buildOnce()
        planetID = id
        planetModel?.removeFromParent()
        if let holder = SpaceScene.ball("space-\(id)", voxel: SpaceScene.voxelScale),
           let size = DetailModels.size(named: "space-\(id)") {
            root.addChild(holder)
            planetModel = holder
            planetRadius = Float(min(size.x, size.z)) / 2 * SpaceScene.voxelScale * 0.95
            // A soft glow of air around it, in the colour of its sky.
            atmosphere.removeFromParent()
            atmosphere = Entity()
            let color = BlockRegistry.parseHex(PlanetCatalog.shared.planet(id: id)?.sky ?? "#c4b6ff")
            let sphere = MeshResource.generateSphere(radius: 1)
            for (scale, opacity) in [(Float(1.1), Float(0.22)), (1.2, 0.12), (1.3, 0.06)] {
                let shell = ModelEntity(mesh: sphere, materials: [Shots.material(color, opacity: opacity)])
                shell.scale = SIMD3(repeating: planetRadius * scale)
                atmosphere.addChild(shell)
            }
            root.addChild(atmosphere)
        }

        // Every other planet hangs far off in its own direction.
        for entity in farPlanets.values { entity.removeFromParent() }
        farPlanets.removeAll()
        for planet in PlanetCatalog.shared.planets where planet.id != id {
            guard let holder = SpaceScene.ball("space-\(planet.id)", voxel: 7) else { continue }
            holder.position = (SpaceScene.directions[planet.id] ?? SIMD3(0, 0, -1)) * 1700
            far.addChild(holder)
            farPlanets[planet.id] = holder
        }

        // The spaceport only orbits Wolfie World.
        if id == PlanetCatalog.shared.homeID {
            if spaceport == nil, let station = DetailModels.entity(named: "spaceport") {
                station.scale *= SpaceScene.spaceportScale
                station.position = SpaceScene.spaceportPosition
                root.addChild(station)
                spaceport = station
            }
            spaceport?.isEnabled = true
        } else {
            spaceport?.isEnabled = false
        }
        for model in dockModels { model?.isEnabled = id == PlanetCatalog.shared.homeID }
    }

    /// A planet model centred on its holder, each voxel `voxel` blocks wide.
    static func ball(_ name: String, voxel: Float) -> Entity? {
        guard let model = DetailModels.entity(named: name), let size = DetailModels.size(named: name) else { return nil }
        let holder = Entity()
        // Models sit on their bottom; lift the centre to the holder's origin. Units here are voxels / 4.
        model.position = SIMD3<Float>(0, -Float(size.y) / 2 / DetailModels.voxelsPerBlock, 0)
        holder.addChild(model)
        holder.scale = SIMD3<Float>(repeating: voxel * DetailModels.voxelsPerBlock)
        return holder
    }

    // MARK: Your ship and the docks

    func showShip(_ v: Vehicle) {
        if shipKind != v.kind {
            shipModel?.removeFromParent()
            shipModel = DetailModels.entity(named: v.kind.modelName)
            if let shipModel { root.addChild(shipModel) }
            shipKind = v.kind
        }
        shipModel?.position = v.position
        shipModel?.orientation = v.orientation
        shipModel?.isEnabled = true
    }

    func hideShip() {
        shipModel?.isEnabled = false
    }

    /// Where a docking pad's deck is, in space.
    static func padPosition(_ index: Int) -> SIMD3<Float> {
        let (distance, angle) = pads[index]
        let s = spaceportScale
        return spaceportPosition + SIMD3<Float>(cos(angle) * distance * s, padHeight * s, sin(angle) * distance * s)
    }

    static var padCount: Int { pads.count }

    /// Put ships on the spaceport's pads, noses pointing outward.
    func showDocks(_ docked: [VehicleKind?]) {
        for model in dockModels { model?.removeFromParent() }
        dockModels = docked.enumerated().map { index, kind in
            guard let kind, index < SpaceScene.pads.count, let model = DetailModels.entity(named: kind.modelName) else { return nil }
            let angle = SpaceScene.pads[index].1
            model.position = SpaceScene.padPosition(index)
            // Nose (the model's +z) pointing away from the station.
            model.orientation = simd_quatf(angle: .pi / 2 - angle, axis: SIMD3<Float>(0, 1, 0))
            model.isEnabled = planetID == PlanetCatalog.shared.homeID
            root.addChild(model)
            return model
        }
    }

    // MARK: Hyperspace

    /// Streaks of light rushing past, in the camera's own space (it looks down -z).
    private func buildWarp() {
        let colors: [SIMD3<Float>] = [SIMD3(1, 1, 1), SIMD3(0.6, 0.95, 1), SIMD3(0.8, 0.7, 1)]
        let mesh = MeshResource.generateBox(size: 1)
        for i in 0..<140 {
            let c = colors[i % colors.count]
            let line = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: PlatformColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1))])
            resetWarpLine(line, anywhere: true)
            warp.addChild(line)
            warpLines.append((line, Float.random(in: 500...900)))
        }
    }

    private func resetWarpLine(_ line: ModelEntity, anywhere: Bool) {
        let angle = Float.random(in: 0...(2 * .pi))
        let r = Float.random(in: 6...60)
        let z = anywhere ? Float.random(in: -500 ... -10) : Float.random(in: -520 ... -420)
        line.position = SIMD3<Float>(cos(angle) * r, sin(angle) * r, z)
        line.scale = SIMD3<Float>(0.18, 0.18, Float.random(in: 20...60))
    }

    func updateWarp(dt: Float, strength: Float) {
        for (line, speed) in warpLines {
            line.position.z += speed * dt * strength
            if line.position.z > 30 { resetWarpLine(line, anywhere: false) }
            line.scale.z = max(1, line.scale.z * 0.5 + 60 * strength * 0.5)
        }
    }

    // MARK: Scenery

    private static func material(_ c: SIMD3<Float>, opacity: Float = 1) -> UnlitMaterial {
        var m = UnlitMaterial(color: PlatformColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1))
        if opacity < 1 { m.blending = .transparent(opacity: .init(floatLiteral: opacity)) }
        return m
    }

    private static func cubes(_ centers: [SIMD3<Float>], sizes: [Float]) -> MeshResource? {
        var builder = MeshBuilder()
        for (center, size) in zip(centers, sizes) {
            for face in VoxelMesher.faces {
                builder.addFace(face, at: center - SIMD3<Float>(repeating: size / 2), u: 0.5, size: size)
            }
        }
        return try? builder.mesh(name: "space")
    }

    private static func gaussian(_ noise: inout SystemRandomNumberGenerator) -> Float {
        let u = Float.random(in: 0.0001...1, using: &noise)
        let v = Float.random(in: 0...1, using: &noise)
        return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
    }

    /// A glowing cloud of see-through blocks.
    private static func makeNebula(direction: SIMD3<Float>, colors: [SIMD3<Float>], seed: Int) -> Entity {
        let nebula = Entity()
        let center = simd_normalize(direction) * 2050
        var random = SystemRandomNumberGenerator()
        for (layer, color) in colors.enumerated() {
            var centers: [SIMD3<Float>] = []
            var sizes: [Float] = []
            for _ in 0..<70 {
                let offset = SIMD3<Float>(gaussian(&random) * 260, gaussian(&random) * 110, gaussian(&random) * 260)
                centers.append(center + offset + SIMD3<Float>(Float(layer) * 60, 0, 0))
                sizes.append(Float.random(in: 40...120))
            }
            if let mesh = cubes(centers, sizes: sizes) {
                nebula.addChild(ModelEntity(mesh: mesh, materials: [material(color, opacity: layer == 0 ? 0.16 : 0.12)]))
            }
        }
        return nebula
    }

    /// A spiral galaxy made of little bright blocks, seen far away and tipped over.
    private static func makeGalaxy(direction: SIMD3<Float>, tilt: Float, seed: Int) -> Entity {
        let galaxy = Entity()
        let groups: [(SIMD3<Float>, Int)] = [(SIMD3(1, 0.93, 0.75), 0), (SIMD3(0.6, 0.75, 1), 1), (SIMD3(1, 0.6, 0.9), 2)]
        for (color, group) in groups {
            var centers: [SIMD3<Float>] = []
            var sizes: [Float] = []
            if group == 0 {
                for _ in 0..<40 {
                    let r = Float.random(in: 0...28)
                    let a = Float.random(in: 0...(2 * .pi))
                    centers.append(SIMD3(cos(a) * r, Float.random(in: -6...6), sin(a) * r))
                    sizes.append(Float.random(in: 7...12))
                }
            } else {
                for i in 0..<110 {
                    let t = Float(i) / 110
                    let a = t * 3.6 * .pi + (group == 2 ? .pi : 0)
                    let r = 25 + t * 150
                    centers.append(SIMD3(cos(a) * r + Float.random(in: -10...10), Float.random(in: -3...3), sin(a) * r + Float.random(in: -10...10)))
                    sizes.append(Float.random(in: 4...9))
                }
            }
            if let mesh = cubes(centers, sizes: sizes) {
                galaxy.addChild(ModelEntity(mesh: mesh, materials: [material(color, opacity: group == 0 ? 1 : 0.85)]))
            }
        }
        galaxy.position = simd_normalize(direction) * 2150
        galaxy.orientation = simd_quatf(angle: tilt, axis: SIMD3<Float>(1, 0, 0)) * simd_quatf(angle: Float(seed), axis: SIMD3<Float>(0, 1, 0))
        return galaxy
    }

    private static func makeSun() -> Entity {
        let sun = Entity()
        sun.position = simd_normalize(SIMD3<Float>(-0.3, 0.5, 0.8)) * 2100
        sun.addChild(ModelEntity(mesh: .generateBox(size: 150), materials: [material(SIMD3(1, 0.97, 0.85))]))
        let glow = ModelEntity(mesh: .generateBox(size: 260), materials: [material(SIMD3(1, 0.85, 0.5), opacity: 0.18)])
        sun.addChild(glow)
        sun.orientation = simd_quatf(angle: 0.6, axis: simd_normalize(SIMD3<Float>(1, 1, 0)))
        return sun
    }
}
