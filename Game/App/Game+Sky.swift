import Foundation
import RealityKit
import simd

/// The Wolfie day: the sun crosses the sky, evenings glow orange and pink, and nights turn a deep,
/// starry blue that's never too dark to play. Blocky clouds drift overhead, like Minecraft's.
/// Planets with no air (Pup Moon) keep their starry black sky.
extension Game {
    /// A whole day, in seconds.
    static let dayLength: Float = 900
    static let cloudTile: Float = 512

    private var hasWeather: Bool { !planet.stars }

    func setupDayCycle() {
        for child in Array(clouds.children) { child.removeFromParent() }
        dayTint = -1
        if hasWeather, let mesh = Game.cloudMesh(seed: planet.seed) {
            var m = UnlitMaterial(color: .white)
            m.blending = .transparent(opacity: .init(floatLiteral: 0.82))
            for _ in 0..<9 {
                clouds.addChild(ModelEntity(mesh: mesh, materials: [m]))
            }
        }
        sun.isEnabled = hasWeather
        updateDayColors()
    }

    func updateDayCycle(dt: Float) {
        guard place == .surface, hasWeather else { return }
        dayClock += dt
        dayTimer -= dt
        guard dayTimer <= 0 else { return }
        dayTimer = 0.5
        updateDayColors()
        applySky(darkness: max(0, skyDarkness), force: true)
    }

    private func updateDayColors() {
        let base = BlockRegistry.parseHex(planet.sky)
        guard hasWeather else {
            daySky = base
            dayLight = 1
            setLandLight(SIMD3(1, 1, 1))
            return
        }
        let phase = (dayClock / Game.dayLength).truncatingRemainder(dividingBy: 1)
        let angle = phase * 2 * .pi
        let height = sin(angle)                      // 1 at noon, -1 at midnight
        dayLight = min(1, max(0, 0.45 + height * 1.6))
        let glow = exp(-pow(height / 0.22, 2))       // around sunrise and sunset
        let night = base * 0.3 + SIMD3<Float>(0.06, 0.07, 0.2)
        var sky = simd_mix(night, base, SIMD3(repeating: dayLight))
        sky = simd_mix(sky, SIMD3(1, 0.55, 0.45), SIMD3(repeating: glow * 0.4))
        daySky = sky
        // The land dims to a soft blue at night, never dark; warm at sunset.
        var light = simd_mix(SIMD3<Float>(0.58, 0.62, 0.82), SIMD3(1, 1, 1), SIMD3(repeating: dayLight))
        light = simd_mix(light, SIMD3(1, 0.86, 0.76), SIMD3(repeating: glow * 0.35))
        setLandLight(light)
        // The sun, low and orange at the ends of the day.
        let direction = simd_normalize(SIMD3<Float>(cos(angle) * 0.9, height, 0.35))
        sun.position = direction * Game.skyRadius * 0.88
        sun.isEnabled = height > -0.12
        // Clouds pick up the light too.
        let cloud = simd_mix(SIMD3<Float>(0.55, 0.58, 0.72), SIMD3(1, 1, 1), SIMD3(repeating: dayLight))
        let tinted = simd_mix(cloud, SIMD3(1, 0.78, 0.7), SIMD3(repeating: glow * 0.5))
        var m = UnlitMaterial(color: Game.color(tinted))
        m.blending = .transparent(opacity: .init(floatLiteral: 0.82))
        for case let c as ModelEntity in clouds.children { c.model?.materials = [m] }
    }

    private func setLandLight(_ light: SIMD3<Float>) {
        let level = light.x + light.y * 3 + light.z * 7
        guard abs(level - dayTint) > 0.04 else { return }
        dayTint = level
        renderer.setTint(light)
    }

    func buildSun() {
        let r: Float = 70
        let core = ModelEntity(mesh: .generateSphere(radius: r), materials: [Shots.material(SIMD3(1, 0.97, 0.85))])
        let glow = ModelEntity(mesh: .generateSphere(radius: r * 2), materials: [Shots.material(SIMD3(1, 0.9, 0.6), opacity: 0.25)])
        let halo = ModelEntity(mesh: .generateSphere(radius: r * 4), materials: [Shots.material(SIMD3(1, 0.85, 0.6), opacity: 0.08)])
        sun.addChild(halo)
        sun.addChild(glow)
        sun.addChild(core)
    }

    /// Clouds follow you around, drifting slowly, tiled so they never run out.
    func moveClouds(_ eye: SIMD3<Float>) {
        guard !clouds.children.isEmpty else { return }
        let tile = Game.cloudTile
        let drift = clock * 1.6
        let height: Float = 118
        let baseX = floor((eye.x - drift) / tile) * tile + drift
        let baseZ = floor(eye.z / tile) * tile
        var i = 0
        for dz in -1...1 {
            for dx in -1...1 {
                guard i < clouds.children.count else { return }
                clouds.children[i].position = SIMD3(baseX + Float(dx) * tile, height, baseZ + Float(dz) * tile)
                i += 1
            }
        }
    }

    /// One tile of blocky clouds: flat slabs 4 blocks thick, in cells 8 blocks wide.
    static func cloudMesh(seed: UInt64) -> MeshResource? {
        let cell: Float = 8
        let n = Int(cloudTile / cell)
        let noise = Noise(seed: seed &+ 99)
        var on = [Bool](repeating: false, count: n * n)
        for j in 0..<n {
            for i in 0..<n {
                // Fade toward the tile's edges so neighbouring tiles join without a hard line.
                let edge = min(min(i, n - 1 - i), min(j, n - 1 - j))
                let fade = min(1, Float(edge) / 6)
                on[j * n + i] = noise.fbm(Float(i) * 0.11, Float(j) * 0.11) * fade > 0.57
            }
        }
        func at(_ i: Int, _ j: Int) -> Bool { on[((j % n + n) % n) * n + ((i % n + n) % n)] }
        var builder = MeshBuilder()
        let faces = VoxelMesher.faces
        let size = SIMD3<Float>(cell, 4, cell)
        for j in 0..<n {
            for i in 0..<n where at(i, j) {
                let origin = SIMD3<Float>(Float(i) * cell, 0, Float(j) * cell)
                builder.addBox(faces[2], at: origin, size: size, u: 0.5)
                builder.addBox(faces[3], at: origin, size: size, u: 0.5)
                if !at(i + 1, j) { builder.addBox(faces[0], at: origin, size: size, u: 0.5) }
                if !at(i - 1, j) { builder.addBox(faces[1], at: origin, size: size, u: 0.5) }
                if !at(i, j + 1) { builder.addBox(faces[4], at: origin, size: size, u: 0.5) }
                if !at(i, j - 1) { builder.addBox(faces[5], at: origin, size: size, u: 0.5) }
            }
        }
        return try? builder.mesh(name: "clouds")
    }
}
