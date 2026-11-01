import Foundation
import simd

/// Blocks with nothing holding them up fall, tumble and crumble into rubble where they land.
/// Every device works this out for itself from the same block changes, so friends see the same
/// pieces fall; the rubble piles are placed by the host (or you, playing alone) and shared.
extension Game {
    func updateFalling(dt: Float) {
        if !world.removed.isEmpty {
            falling.note(world.removed)
            world.removed.removeAll(keepingCapacity: true)
        }
        for blocks in falling.findLoose(in: world) {
            let center = blocks.reduce(SIMD3<Float>(repeating: 0)) { $0 + SIMD3<Float>($1.0) } / Float(blocks.count) + 0.5
            // A little nudge sideways, away from you, so it tips over as it goes.
            var away = center - player.position
            away.y = 0
            let push = simd_length(away) > 0.1 ? simd_normalize(away) * 1.5 : SIMD3<Float>(0, 0, 0)
            if falling.drop(blocks, material: textureMaterial, push: push) {
                Sound.shared.play("creak", at: center, listener: player.eye, facing: player.yaw, volume: min(0.6, 0.15 + Float(blocks.count) / 400))
            } else {
                // Too much falling at once: it just crumbles where it is.
                landed(FallingBlocks.Landing(point: center, blocks: blocks.map(\.1), radius: 1))
            }
        }
        for landing in falling.update(dt: dt, world: world, gravity: planet.gravity) {
            landed(landing)
        }
    }

    private func landed(_ landing: FallingBlocks.Landing) {
        let p = landing.point
        var colors: [SIMD3<Float>] = []
        for id in landing.blocks.prefix(30) {
            let c = BlockRegistry.shared.rgb(id)
            if !colors.contains(c) { colors.append(c) }
            if colors.count >= 3 { break }
        }
        let size = min(3.5, 0.8 + landing.radius * 0.45)
        effects.explosion(at: p + SIMD3(0, 0.6, 0), radius: size * 0.6, colors: colors)
        let distance = simd_distance(p, camera.position)
        Sound.shared.playVaried("rubble", volume: min(0.55, (0.2 + Float(landing.blocks.count) / 300) * min(1, 18 / max(distance, 1))), spread: 0.1)
        if distance < 25 { armory.shake = max(armory.shake, min(0.25, Float(landing.blocks.count) / 2000)) }
        blastCats(at: p, radius: landing.radius + 1.5)
        _ = critters.blast(at: p, radius: landing.radius + 1.5)
        // A push out of the way, never a hurt.
        var away = player.position - p
        away.y = 0
        let d = simd_length(away)
        if driving == nil && d < landing.radius + 2 {
            player.knock((d > 0.1 ? away / d : SIMD3(1, 0, 0)) * 7 + SIMD3(0, 4, 0))
        }
        // A rubble pile, spiralling out from where it hit.
        guard session != .joined else { return }
        let rubble = Array(landing.blocks.shuffled().prefix(min(160, max(1, landing.blocks.count / 2))))
        let cx = Int(floor(p.x)), cz = Int(floor(p.z))
        var placed = 0
        var ring = 0
        while placed < rubble.count && ring < 12 {
            for dz in -ring...ring {
                for dx in -ring...ring where max(abs(dx), abs(dz)) == ring && placed < rubble.count {
                    let x = cx + dx, z = cz + dz
                    let y = world.surfaceY(x: x, z: z)
                    let cell = SIMD3<Int>(x, y, z)
                    guard y > 0, y < World.height - 1, !player.occupies(cell) else { continue }
                    // Pile higher in the middle.
                    if y > Int(floor(p.y)) + max(0, 3 - ring) { continue }
                    var id = rubble[placed]
                    if id == SB.glitchBlock { id = SB.white }
                    if id == SB.glitchGlow { id = SB.nightGlass }
                    changeBlock(cell, id)
                    placed += 1
                }
            }
            ring += 1
        }
    }
}
