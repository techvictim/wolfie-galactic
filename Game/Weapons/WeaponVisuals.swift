import Foundation
import RealityKit
import simd

/// Little toy models for things in flight: rockets, grenades, charges, bombs, meteors and drones.
@MainActor
enum Shots {
    private static var materials: [String: UnlitMaterial] = [:]

    static func material(_ c: SIMD3<Float>, opacity: Float = 1) -> UnlitMaterial {
        let key = String(format: "%.2f,%.2f,%.2f,%.2f", c.x, c.y, c.z, opacity)
        if let cached = materials[key] { return cached }
        var m = UnlitMaterial(color: PlatformColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1))
        if opacity < 1 { m.blending = .transparent(opacity: .init(floatLiteral: opacity)) }
        materials[key] = m
        return m
    }

    static func box(_ size: SIMD3<Float>, _ at: SIMD3<Float>, _ c: SIMD3<Float>, opacity: Float = 1) -> ModelEntity {
        let e = ModelEntity(mesh: .generateBox(width: size.x, height: size.y, depth: size.z), materials: [material(c, opacity: opacity)])
        e.position = at
        return e
    }

    static let hazard = SIMD3<Float>(1, 0.76, 0.1)
    static let olive = SIMD3<Float>(0.42, 0.48, 0.23)
    static let steel = SIMD3<Float>(0.35, 0.38, 0.43)
    static let dark = SIMD3<Float>(0.16, 0.17, 0.2)
    static let red = SIMD3<Float>(0.86, 0.18, 0.16)

    /// A model pointing along -z. The light, if any, is returned so it can blink.
    static func model(_ look: String, size: Float) -> (entity: Entity, light: ModelEntity?) {
        let root = Entity()
        var light: ModelEntity?
        switch look {
        case "rocket":
            root.addChild(box(SIMD3(0.16, 0.16, 0.6), .zero, olive))
            root.addChild(box(SIMD3(0.12, 0.12, 0.14), SIMD3(0, 0, -0.36), red))
            root.addChild(box(SIMD3(0.4, 0.04, 0.12), SIMD3(0, 0, 0.26), dark))
            root.addChild(box(SIMD3(0.04, 0.4, 0.12), SIMD3(0, 0, 0.26), dark))
            root.addChild(box(SIMD3(0.1, 0.1, 0.12), SIMD3(0, 0, 0.36), SIMD3(1, 0.7, 0.2)))
        case "grenade":
            root.addChild(box(SIMD3(0.24, 0.26, 0.24), .zero, SIMD3(0.3, 0.42, 0.22)))
            root.addChild(box(SIMD3(0.26, 0.05, 0.26), .zero, hazard))
            root.addChild(box(SIMD3(0.08, 0.08, 0.08), SIMD3(0, 0.16, 0), steel))
        case "shell":
            root.addChild(box(SIMD3(0.2, 0.2, 0.5), .zero, steel))
            root.addChild(box(SIMD3(0.14, 0.14, 0.12), SIMD3(0, 0, -0.3), hazard))
        case "charge":
            for x: Float in [-0.12, 0, 0.12] {
                root.addChild(box(SIMD3(0.11, 0.36, 0.11), SIMD3(x, 0, 0), red))
            }
            root.addChild(box(SIMD3(0.38, 0.06, 0.13), SIMD3(0, 0.05, 0), dark))
            let l = box(SIMD3(0.08, 0.08, 0.04), SIMD3(0, 0.05, -0.08), SIMD3(1, 0.2, 0.2))
            root.addChild(l)
            light = l
        case "mine":
            root.addChild(box(SIMD3(0.6, 0.12, 0.6), .zero, SIMD3(0.28, 0.3, 0.22)))
            root.addChild(box(SIMD3(0.3, 0.06, 0.3), SIMD3(0, 0.08, 0), dark))
            let l = box(SIMD3(0.08, 0.06, 0.08), SIMD3(0, 0.13, 0), SIMD3(1, 0.2, 0.2))
            root.addChild(l)
            light = l
        case "bomb":
            root.addChild(box(SIMD3(0.5, 0.5, 1.3), .zero, SIMD3(0.3, 0.33, 0.28)))
            root.addChild(box(SIMD3(0.36, 0.36, 0.2), SIMD3(0, 0, -0.72), dark))
            root.addChild(box(SIMD3(0.9, 0.06, 0.3), SIMD3(0, 0, 0.62), dark))
            root.addChild(box(SIMD3(0.06, 0.9, 0.3), SIMD3(0, 0, 0.62), dark))
            root.addChild(box(SIMD3(0.52, 0.52, 0.08), SIMD3(0, 0, -0.3), hazard))
        case "meteor":
            root.addChild(box(SIMD3(1.1, 1.0, 1.2), .zero, SIMD3(0.42, 0.26, 0.18)))
            root.addChild(box(SIMD3(0.7, 0.7, 0.7), SIMD3(0.35, 0.3, -0.2), SIMD3(0.55, 0.32, 0.2)))
            root.addChild(box(SIMD3(1.6, 1.5, 1.6), .zero, SIMD3(1, 0.5, 0.1), opacity: 0.35))
        case "drone":
            root.addChild(box(SIMD3(0.4, 0.14, 0.4), .zero, steel))
            root.addChild(box(SIMD3(0.12, 0.08, 0.06), SIMD3(0, 0, -0.22), hazard))
            for (x, z) in [(Float(-0.3), Float(-0.3)), (0.3, -0.3), (-0.3, 0.3), (0.3, 0.3)] {
                root.addChild(box(SIMD3(0.28, 0.02, 0.06), SIMD3(x, 0.1, z), dark))
            }
        default: // ball
            root.addChild(box(SIMD3(0.36, 0.36, 0.36), .zero, dark))
            root.addChild(box(SIMD3(0.26, 0.4, 0.26), .zero, SIMD3(0.24, 0.24, 0.28)))
        }
        root.scale = SIMD3(repeating: size)
        return (root, light)
    }
}

/// The nuke's mushroom cloud: a fireball that rises on a stem into a rolling cap, with a skirt
/// of dust racing out along the ground. It glows hot, cools to brown and grey, and fades.
@MainActor
final class MushroomCloud {
    let root = Entity()
    private var age: Float = 0
    private var stem: [ModelEntity] = []
    private var cap: [ModelEntity] = []
    private var skirt: [ModelEntity] = []
    private var core: ModelEntity
    static let life: Float = 33
    private let sphere = MeshResource.generateSphere(radius: 1)

    init(at point: SIMD3<Float>) {
        root.position = point
        core = ModelEntity(mesh: sphere, materials: [])
        root.addChild(core)
        for _ in 0..<9 {
            let e = ModelEntity(mesh: sphere, materials: [])
            stem.append(e)
            root.addChild(e)
        }
        for _ in 0..<12 {
            let e = ModelEntity(mesh: sphere, materials: [])
            cap.append(e)
            root.addChild(e)
        }
        for _ in 0..<14 {
            let e = ModelEntity(mesh: sphere, materials: [])
            skirt.append(e)
            root.addChild(e)
        }
        update(dt: 0)
    }

    /// False once it's gone.
    func update(dt: Float) -> Bool {
        age += dt
        let t = age
        let rise = 1 - pow(1 - min(1, t / 9), 2)
        let top: Float = 8 + 48 * rise
        let fade = t < 24 ? 1 : max(0, 1 - (t - 24) / 9)
        let heat = max(0, 1 - t / 7)
        let hot = SIMD3<Float>(1, 0.9, 0.55)
        let warm = SIMD3<Float>(1, 0.48, 0.16)
        let brown = SIMD3<Float>(0.45, 0.33, 0.27)
        let grey = SIMD3<Float>(0.55, 0.52, 0.5)
        func shade(_ h: Float) -> SIMD3<Float> {
            if h > 0.6 { return simd_mix(warm, hot, SIMD3(repeating: (h - 0.6) / 0.4)) }
            if h > 0.15 { return simd_mix(brown, warm, SIMD3(repeating: (h - 0.15) / 0.45)) }
            return simd_mix(grey, brown, SIMD3(repeating: h / 0.15))
        }
        func paint(_ e: ModelEntity, _ c: SIMD3<Float>, _ opacity: Float) {
            let q = (c * 10).rounded(.toNearestOrAwayFromZero) / 10
            e.model?.materials = [Shots.material(q, opacity: (max(0.05, opacity) * 10).rounded() / 10)]
        }
        // The rolling cap.
        let wobble = t * 0.25
        core.position = SIMD3(0, top, 0)
        core.scale = SIMD3(repeating: (7 + 7 * rise))
        paint(core, shade(heat * 1.2 + 0.1), 0.92 * fade)
        for (i, e) in cap.enumerated() {
            let a = Float(i) / Float(cap.count) * 2 * .pi + wobble
            let r: Float = 8 + 8 * rise
            e.position = SIMD3(cos(a) * r, top - 2 + sin(a * 3 + t) * 0.8, sin(a) * r)
            e.scale = SIMD3(repeating: 5 + 3.5 * rise)
            paint(e, shade(heat * 0.9 + (i % 3 == 0 ? 0.1 : 0)), 0.85 * fade)
        }
        // The stem.
        for (i, e) in stem.enumerated() {
            let f = Float(i) / Float(stem.count)
            e.position = SIMD3(sin(f * 7 + t * 0.4) * 0.6, f * top, cos(f * 5) * 0.6)
            e.scale = SIMD3(repeating: (4.4 - f * 1.3) * (0.4 + 0.6 * rise))
            paint(e, shade(heat * (0.6 + f * 0.5)), 0.8 * fade)
        }
        // Dust racing out along the ground.
        let out = 1 - pow(1 - min(1, t / 5), 3)
        for (i, e) in skirt.enumerated() {
            let a = Float(i) / Float(skirt.count) * 2 * .pi
            let r = 6 + 30 * out
            e.position = SIMD3(cos(a) * r, 1.5, sin(a) * r)
            e.scale = SIMD3(3.5 + 2 * out, 2 + out, 3.5 + 2 * out)
            paint(e, shade(heat * 0.5), 0.75 * fade * max(0, 1 - t / 18))
        }
        return age < MushroomCloud.life
    }
}

/// The Black Hole: a black core with two swirling purple, cyan and gold disks and a glow.
/// It opens, eats what's around it, snaps shut and sends out three rings of light.
@MainActor
final class BlackHoleVisual {
    let root = Entity()
    private let disk1 = Entity()
    private let disk2 = Entity()
    private let body = Entity()
    private var rings: [ModelEntity] = []
    private var closing: Float = -1
    private var age: Float = 0

    init(at point: SIMD3<Float>) {
        root.position = point
        let sphere = MeshResource.generateSphere(radius: 1)
        let core = ModelEntity(mesh: sphere, materials: [Shots.material(SIMD3(0.01, 0.0, 0.03))])
        core.scale = SIMD3(repeating: 1.3)
        let glow = ModelEntity(mesh: sphere, materials: [Shots.material(SIMD3(0.55, 0.2, 1), opacity: 0.3)])
        glow.scale = SIMD3(repeating: 2.4)
        let disk = MeshResource.generateCylinder(height: 0.08, radius: 1)
        let purple = ModelEntity(mesh: disk, materials: [Shots.material(SIMD3(0.62, 0.28, 1), opacity: 0.6)])
        purple.scale = SIMD3(4.2, 1, 4.2)
        let cyan = ModelEntity(mesh: disk, materials: [Shots.material(SIMD3(0.3, 0.95, 1), opacity: 0.45)])
        cyan.scale = SIMD3(3.2, 1, 3.2)
        let gold = ModelEntity(mesh: disk, materials: [Shots.material(SIMD3(1, 0.8, 0.3), opacity: 0.55)])
        gold.scale = SIMD3(5.2, 0.6, 5.2)
        disk1.addChild(purple)
        disk1.addChild(gold)
        disk2.addChild(cyan)
        disk1.orientation = simd_quatf(angle: 0.35, axis: SIMD3(1, 0, 0))
        disk2.orientation = simd_quatf(angle: -0.6, axis: SIMD3(0, 0, 1))
        body.addChild(disk1)
        body.addChild(disk2)
        body.addChild(glow)
        body.addChild(core)
        body.scale = SIMD3(repeating: 0.01)
        root.addChild(body)
    }

    func close() {
        guard closing < 0 else { return }
        closing = 0
        let ring = MeshResource.generateCylinder(height: 0.05, radius: 1)
        for i in 0..<3 {
            let colors: [SIMD3<Float>] = [SIMD3(0.75, 0.5, 1), SIMD3(0.4, 1, 1), SIMD3(1, 0.85, 0.4)]
            let r = ModelEntity(mesh: ring, materials: [Shots.material(colors[i], opacity: 0.6)])
            r.isEnabled = false
            r.orientation = simd_quatf(angle: Float(i) * 0.5 - 0.5, axis: SIMD3(1, 0, 0))
            rings.append(r)
            root.addChild(r)
        }
    }

    /// False once it's all over.
    func update(dt: Float) -> Bool {
        age += dt
        let spin1 = simd_quatf(angle: dt * 2.2, axis: SIMD3(0, 1, 0))
        let spin2 = simd_quatf(angle: -dt * 3.1, axis: SIMD3(0, 1, 0))
        disk1.orientation = disk1.orientation * spin1
        disk2.orientation = disk2.orientation * spin2
        if closing < 0 {
            let open = min(1, age / 0.5)
            body.scale = SIMD3(repeating: 0.01 + open * (1 + 0.06 * sin(age * 9)))
            return true
        }
        closing += dt
        body.scale = SIMD3(repeating: max(0.001, 1 - closing / 0.3))
        for (i, r) in rings.enumerated() {
            let t = closing - 0.25 - Float(i) * 0.12
            r.isEnabled = t > 0 && t < 1.1
            if t > 0 {
                let size = 1 + 20 * min(1, t)
                r.scale = SIMD3(size, 1, size)
            }
        }
        return closing < 1.6
    }
}
