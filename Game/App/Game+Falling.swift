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
            // A little nudge sideways, away from you, so it spills over as it goes.
            var away = center - player.position
            away.y = 0
            let push = simd_length(away) > 0.1 ? simd_normalize(away) * 1.5 : SIMD3<Float>(0, 0, 0)
            Sound.shared.play("creak", at: center, listener: player.eye, facing: player.yaw, volume: min(0.45, 0.12 + Float(blocks.count) / 500))
            let leftover = falling.drop(blocks, material: textureMaterial, push: push)
            if !leftover.isEmpty {
                // Too much falling at once: the rest just drops straight down.
                landed(FallingBlocks.Landing(point: center, blocks: leftover.map { (SIMD3<Float>($0.0) + 0.5, $0.1) }, radius: 1), quiet: true)
            }
        }
        rubbleSoundTimer -= dt
        for landing in falling.update(dt: dt, world: world, gravity: planet.gravity) {
            landed(landing, quiet: false)
        }
    }

    private func landed(_ landing: FallingBlocks.Landing, quiet: Bool) {
        let p = landing.point
        // A little puff of dust that clears quickly.
        effects.dustPuff(at: p + SIMD3(0, 0.4, 0), color: BlockRegistry.shared.rgb(landing.blocks.first?.id ?? 3))
        if !quiet && rubbleSoundTimer <= 0 {
            rubbleSoundTimer = 0.07
            Sound.shared.play("rubble", at: p, listener: player.eye, facing: player.yaw, volume: 0.35, pitch: Float.random(in: 0.8...1.3))
        }
        blastCats(at: p, radius: landing.radius + 0.8)
        // A push out of the way, never a hurt.
        var away = player.position - p
        away.y = 0
        let d = simd_length(away)
        if driving == nil && d < landing.radius + 0.8 {
            player.knock((d > 0.1 ? away / d : SIMD3(1, 0, 0)) * 5 + SIMD3(0, 3, 0))
        }
        // The blocks land in a jumble, stacking up where they fell.
        guard session != .joined else { return }
        for (position, original) in landing.blocks {
            let x = Int(floor(position.x)), z = Int(floor(position.z))
            let y = world.surfaceY(x: x, z: z)
            let cell = SIMD3<Int>(x, y, z)
            guard y > 0, y < World.height - 1, !player.occupies(cell) else { continue }
            var id = original
            if id == SB.glitchBlock { id = SB.white }
            if id == SB.glitchGlow { id = SB.nightGlass }
            changeBlock(cell, id)
        }
    }
}
