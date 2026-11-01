import Foundation
import RealityKit
import simd

/// One of the Wolfie Military crew you can play as.
struct CrewMember: Identifiable, Hashable {
    let id: String
    let name: String
    /// Who they are, for the character picker.
    let role: String
    /// Gizmo is a small robot.
    let scale: Float
    /// How far back the jetpack nozzles are, in toy pixels (16 per metre).
    let jetZ: Float
}

enum Crew {
    static let all: [CrewMember] = [
        CrewMember(id: "wolfie", name: "Wolfie", role: "Boss of the crew. His nose can sniff out the Red Glitch.", scale: 1, jetZ: 4),
        CrewMember(id: "gecko", name: "Gecko Kid", role: "Superhero who sticks to anything and climbs the tallest towers.", scale: 1, jetZ: 4),
        CrewMember(id: "bubbles", name: "Bubbles", role: "Puffer-fish diver who giggles in bubbles.", scale: 1, jetZ: 4),
        CrewMember(id: "nova", name: "Nova", role: "Space ranger. Keeps watch on the stars from the Space Dome.", scale: 1, jetZ: 4),
        CrewMember(id: "gizmo", name: "Gizmo", role: "Tiny robot inventor with very big plans.", scale: 0.8, jetZ: 4),
        CrewMember(id: "barnacle", name: "Captain Barnacle", role: "Old sea-turtle captain. Runs the boat dock.", scale: 1, jetZ: 6),
        CrewMember(id: "thunderhoof", name: "Baron Thunderhoof", role: "Retired crash champion who loves a big crash.", scale: 1, jetZ: 4),
    ]

    static func member(_ id: String?) -> CrewMember {
        all.first { $0.id == id } ?? all[0]
    }

    /// The parts in each crew .vox, in order (Tools/make_crew.py).
    fileprivate enum Part: Int, CaseIterable { case head, body, armL, armR, legL, legR }

    /// The toy pixels per metre the crew are drawn with.
    fileprivate static let pixels: Float = 16
    /// The grid corner of every part, in toy pixels.
    fileprivate static let gridOrigin = SIMD3<Float>(-11, 0, -11)

    /// Where each part turns, in toy pixels: the neck, shoulders and hips.
    fileprivate static func joint(_ part: Part) -> SIMD3<Float> {
        switch part {
        case .head: return SIMD3(0, 21, 0)
        case .body: return SIMD3(0, 11, 0)
        case .armL: return SIMD3(-6, 20, 0)
        case .armR: return SIMD3(6, 20, 0)
        case .legL: return SIMD3(-2, 11, 0)
        case .legR: return SIMD3(2, 11, 0)
        }
    }

    /// Parsed models, so friends with the same character share the work.
    @MainActor private static var cache: [String: (meshes: [MeshResource], material: UnlitMaterial)] = [:]

    @MainActor fileprivate static func parts(_ id: String) -> (meshes: [MeshResource], material: UnlitMaterial)? {
        if let cached = cache[id] { return cached }
        guard let url = Bundle.main.url(forResource: "crew-\(id)", withExtension: "vox")
                ?? Bundle.main.url(forResource: "crew-\(id)", withExtension: "vox", subdirectory: "Crew"),
              let data = try? Data(contentsOf: url) else { return nil }
        let models = VoxLoader.loadAll(data)
        guard models.count >= Part.allCases.count,
              let texture = PaletteTexture.make(colors: models[0].palette) else { return nil }
        var meshes: [MeshResource] = []
        for part in Part.allCases {
            let model = models[part.rawValue]
            let shift = gridOrigin - joint(part)
            var builder = MeshBuilder()
            for (p, color) in model.voxels {
                for (faceIndex, face) in VoxelMesher.faces.enumerated() where model.voxels[p &+ face.dir] == nil {
                    builder.addFace(face, at: SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z)) + shift,
                                    u: PaletteTexture.u(index: Int(color), face: faceIndex, count: 256))
                }
            }
            guard let mesh = try? builder.mesh(name: "crew-\(id)-\(part)") else { return nil }
            meshes.append(mesh)
        }
        let result = (meshes, PaletteTexture.material(texture))
        cache[id] = result
        return result
    }
}

/// A crew member you can see: the toy figure, with joints to swing the arms and legs,
/// a head that looks up and down, jetpack flames and a little blaster.
@MainActor
final class CrewRig {
    let member: CrewMember
    /// Feet at the origin, facing -z.
    let root = Entity()
    private let body = Entity()
    private let head = Entity()
    private let armL = Entity()
    private let armR = Entity()
    private let legL = Entity()
    private let legR = Entity()
    private let flames = Entity()
    private let blaster = Entity()

    private var phase: Float = 0
    private var flameClock: Float = 0
    private var heldStyle: String?
    private var swingTime: Float = 0

    init(_ id: String) {
        member = Crew.member(id)
        let joints: [(Entity, Crew.Part, Entity)] = [
            (body, .body, root), (legL, .legL, root), (legR, .legR, root),
            (head, .head, body), (armL, .armL, body), (armR, .armR, body),
        ]
        let built = Crew.parts(member.id)
        for (entity, part, parent) in joints {
            var at = Crew.joint(part)
            if parent === body { at -= Crew.joint(.body) }
            entity.position = at / Crew.pixels
            if let built {
                let model = ModelEntity(mesh: built.meshes[part.rawValue], materials: [built.material])
                model.scale = SIMD3<Float>(repeating: 1 / Crew.pixels)
                entity.addChild(model)
            }
            parent.addChild(entity)
        }
        root.scale = SIMD3<Float>(repeating: member.scale)

        // Flames under the jetpack: pointed, with a blue core, like in Wolfie Military.
        for side: Float in [-1, 1] {
            let flame = Entity()
            flame.position = SIMD3(side * 2, 9 - 11, member.jetZ) / Crew.pixels
            flame.addChild(CrewRig.box(SIMD3(0.09, 0.32, 0.09), at: SIMD3(0, -0.16, 0), SIMD3(1, 0.55, 0.15), opacity: 0.85))
            flame.addChild(CrewRig.box(SIMD3(0.05, 0.2, 0.05), at: SIMD3(0, -0.1, 0), SIMD3(0.45, 0.8, 1), opacity: 1))
            flames.addChild(flame)
        }
        flames.isEnabled = false
        body.addChild(flames)

        // Whatever's in hand sits in the right paw.
        blaster.position = SIMD3(0, -10, -1) / Crew.pixels
        blaster.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
        blaster.isEnabled = false
        armR.addChild(blaster)
    }

    /// What's in hand: laser, gun, launcher, tool, charge, radio or alien; nil for nothing.
    func hold(_ style: String?) {
        guard style != heldStyle else { return }
        heldStyle = style
        for child in Array(blaster.children) { child.removeFromParent() }
        let steel = SIMD3<Float>(0.24, 0.27, 0.33)
        let dark = SIMD3<Float>(0.14, 0.15, 0.18)
        let olive = SIMD3<Float>(0.42, 0.48, 0.23)
        let hazard = SIMD3<Float>(1, 0.76, 0.1)
        func add(_ size: SIMD3<Float>, _ at: SIMD3<Float>, _ c: SIMD3<Float>, _ opacity: Float = 1) {
            blaster.addChild(CrewRig.box(size, at: at, c, opacity: opacity))
        }
        switch style {
        case "laser":
            add(SIMD3(0.09, 0.11, 0.3), SIMD3(0, 0, -0.08), steel)
            add(SIMD3(0.05, 0.05, 0.06), SIMD3(0, 0.01, -0.26), SIMD3(1, 0.45, 0.85))
        case "gun":
            add(SIMD3(0.08, 0.12, 0.5), SIMD3(0, 0, -0.14), dark)
            add(SIMD3(0.05, 0.05, 0.22), SIMD3(0, 0.02, -0.48), steel)
            add(SIMD3(0.06, 0.14, 0.08), SIMD3(0, -0.1, -0.02), dark)
        case "launcher":
            add(SIMD3(0.16, 0.16, 0.8), SIMD3(0, 0.08, -0.1), olive)
            add(SIMD3(0.18, 0.18, 0.06), SIMD3(0, 0.08, -0.5), dark)
            add(SIMD3(0.06, 0.12, 0.08), SIMD3(0, -0.06, -0.05), dark)
        case "tool":
            add(SIMD3(0.05, 0.05, 0.55), SIMD3(0, 0, -0.18), SIMD3(0.55, 0.38, 0.2))
            add(SIMD3(0.14, 0.26, 0.12), SIMD3(0, 0, -0.46), steel)
        case "charge":
            add(SIMD3(0.18, 0.12, 0.14), SIMD3(0, 0, -0.06), SIMD3(0.86, 0.18, 0.16))
            add(SIMD3(0.19, 0.03, 0.15), SIMD3(0, 0, -0.06), hazard)
        case "radio":
            add(SIMD3(0.1, 0.16, 0.06), SIMD3(0, 0, -0.04), olive)
            add(SIMD3(0.02, 0.02, 0.2), SIMD3(0.03, 0.05, -0.16), dark)
        case "alien":
            add(SIMD3(0.1, 0.12, 0.42), SIMD3(0, 0, -0.14), SIMD3(0.55, 0.25, 0.95))
            add(SIMD3(0.04, 0.16, 0.12), SIMD3(0.07, 0.02, -0.1), SIMD3(0.35, 0.95, 1))
            add(SIMD3(0.04, 0.16, 0.12), SIMD3(-0.07, 0.02, -0.16), SIMD3(1, 0.5, 0.85))
            add(SIMD3(0.02, 0.08, 0.1), SIMD3(0, 0.1, -0.02), SIMD3(1, 0.8, 0.3))
            add(SIMD3(0.09, 0.09, 0.09), SIMD3(0, 0, -0.4), SIMD3(0.05, 0.02, 0.1))
        default:
            break
        }
    }

    /// A hammer swing.
    func swing() {
        swingTime = 0.28
    }

    /// Move the figure for this frame.
    /// - speed: how fast they're moving along the ground, in metres a second.
    /// - pitch: where they're looking, up is positive.
    func animate(dt: Float, speed: Float, pitch: Float, flying: Bool, aiming: Bool) {
        let stride = min(speed / 4.5, 1.4)
        if flying {
            phase += dt * 2
        } else if stride > 0.05 {
            phase += dt * (5 + speed * 1.1)
        } else {
            // Ease back to standing.
            phase = phase.remainder(dividingBy: .pi) * max(0, 1 - dt * 8)
        }
        let swing = flying ? 0.12 * sin(phase) : sin(phase) * 0.75 * min(stride, 1)

        legL.orientation = simd_quatf(angle: flying ? -0.35 + swing : swing, axis: SIMD3(1, 0, 0))
        legR.orientation = simd_quatf(angle: flying ? -0.2 - swing : -swing, axis: SIMD3(1, 0, 0))
        armL.orientation = simd_quatf(angle: flying ? 0.35 : -swing * 0.8, axis: SIMD3(1, 0, 0))
            * simd_quatf(angle: flying ? -0.25 : 0, axis: SIMD3(0, 0, 1))
        let look = max(min(pitch, 1.1), -1.1)
        if swingTime > 0 {
            // Up high, then down hard.
            swingTime = max(0, swingTime - dt)
            let t = 1 - swingTime / 0.28
            let angle: Float = t < 0.35 ? 2.6 * (t / 0.35) : 2.6 - 2.0 * min(1, (t - 0.35) / 0.3)
            armR.orientation = simd_quatf(angle: angle, axis: SIMD3(1, 0, 0))
        } else if aiming {
            armR.orientation = simd_quatf(angle: .pi / 2 + look, axis: SIMD3(1, 0, 0))
        } else {
            armR.orientation = simd_quatf(angle: flying ? 0.35 : swing * 0.8, axis: SIMD3(1, 0, 0))
                * simd_quatf(angle: flying ? 0.25 : 0, axis: SIMD3(0, 0, 1))
        }
        blaster.isEnabled = heldStyle != nil
        head.orientation = simd_quatf(angle: max(min(pitch, 0.7), -0.6), axis: SIMD3(1, 0, 0))

        // A little bounce in the step, and a lean forward when flying fast.
        let bounce: Float = flying ? sin(phase * 1.3) * 0.04 : abs(sin(phase)) * 0.05 * min(stride, 1)
        body.position.y = Crew.joint(.body).y / Crew.pixels + bounce
        legL.position.y = Crew.joint(.legL).y / Crew.pixels + bounce
        legR.position.y = Crew.joint(.legR).y / Crew.pixels + bounce
        body.orientation = simd_quatf(angle: flying ? -min(speed / 30, 0.35) : 0, axis: SIMD3(1, 0, 0))

        flames.isEnabled = flying
        if flying {
            flameClock += dt
            for (i, flame) in flames.children.enumerated() {
                let flicker = 0.8 + 0.35 * abs(sin(flameClock * 31 + Float(i) * 1.7))
                flame.scale = SIMD3(1, flicker, 1)
            }
        }
    }

    /// The tip of the blaster, in the world, for the laser beam.
    var muzzle: SIMD3<Float> {
        blaster.convert(position: SIMD3(0, 0.01, -0.3), to: nil)
    }

    private static func box(_ size: SIMD3<Float>, at center: SIMD3<Float>, _ c: SIMD3<Float>, opacity: Float) -> ModelEntity {
        var material = UnlitMaterial(color: PlatformColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1))
        if opacity < 1 { material.blending = .transparent(opacity: .init(floatLiteral: opacity)) }
        let entity = ModelEntity(mesh: .generateBox(width: size.x, height: size.y, depth: size.z), materials: [material])
        entity.position = center
        return entity
    }
}
