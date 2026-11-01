import Foundation
import RealityKit
import simd

/// The Red Glitch, from Wolfie Military: Gizmo's helper program glitched and took over buildings
/// on every planet. Glitch Nests glow red and make robo-cats. Wreck most of a nest and it's cured;
/// the builder bots then put it back clean. Now and then the Glitch spreads back, and Nova calls
/// it in on the radio.
///
/// Story rules: nobody is ever inside a building, wrecking is curing, everything comes back
/// clean, and robo-cats are silly machines that fall asleep when knocked out.
extension Game {
    /// Wreck this much of a nest to cure it.
    static let cureShare: Float = 0.6

    private var catRules: RoboCats.Rules {
        GameSettings.shared.danger >= 2
            ? RoboCats.Rules(aimTime: 1.1, hitChance: 0.55, hitsToSleep: 2, speed: 4.2)
            : RoboCats.Rules(aimTime: 1.7, hitChance: 0.4, hitsToSleep: 1, speed: 3.4)
    }

    /// Robo-cats out at once, and inside each nest.
    private var catsOut: Int { [0, 3, 6][min(max(GameSettings.shared.danger, 0), 2)] }
    private var catsPerNest: Int { [0, 2, 4][min(max(GameSettings.shared.danger, 0), 2)] }

    private func key(_ nest: GlitchNest, _ planetID: String? = nil) -> String {
        "\(planetID ?? planet.id)/\(nest.id)"
    }

    func isCured(_ nest: GlitchNest) -> Bool {
        glitch.isCured(nest.id, on: planet.id)
    }

    // MARK: Finding nests

    /// Every nest in settlements around a spot.
    func nests(around point: SIMD2<Float>, radius: Float, generator: TerrainGenerator? = nil, planet target: Planet? = nil) -> [(site: Settlement, nest: GlitchNest)] {
        let gen = generator ?? world.generator
        let p = target ?? planet
        let cell = TerrainGenerator.settlementCell
        let reach = Int(ceil(radius / Float(cell))) + 1
        let cx = floorDiv(Int(point.x), cell), cz = floorDiv(Int(point.y), cell)
        var found: [(site: Settlement, nest: GlitchNest)] = []
        for dz in -reach...reach {
            for dx in -reach...reach {
                guard let site = gen.settlement(cellX: cx + dx, cellZ: cz + dz) else { continue }
                for nest in Settlements.nests(site, planet: p) where simd_distance(nest.groundCenter, point) <= radius {
                    found.append((site: site, nest: nest))
                }
            }
        }
        return found
    }

    /// Find a nest by its id on a planet.
    private func findNest(_ id: String, generator: TerrainGenerator, planet p: Planet) -> GlitchNest? {
        let parts = id.split(separator: ",").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let cell = TerrainGenerator.settlementCell
        guard let site = generator.settlement(cellX: floorDiv(parts[0], cell), cellZ: floorDiv(parts[1], cell)) else { return nil }
        let all = Settlements.nests(site, planet: p)
        return all.indices.contains(parts[2]) ? all[parts[2]] : nil
    }

    /// How many nests are left in a settlement.
    func nestsLeft(in site: Settlement) -> Int {
        Settlements.nests(site, planet: planet).filter { !isCured($0) }.count
    }

    // MARK: Counting

    private func glitchCount(_ nest: GlitchNest, in w: World) -> Int {
        var n = 0
        for y in nest.min.y..<nest.max.y {
            for z in nest.min.z..<nest.max.z {
                for x in nest.min.x..<nest.max.x where GlitchNest.isGlitch(w.block(x, y, z)) {
                    n += 1
                }
            }
        }
        return n
    }

    private func glitchTotal(_ nest: GlitchNest) -> Int {
        let k = key(nest)
        if let total = glitch.totals[k] { return total }
        var n = 0
        for y in nest.min.y..<nest.max.y {
            for z in nest.min.z..<nest.max.z {
                for x in nest.min.x..<nest.max.x {
                    if let b = nest.clean(x, y, z), GlitchNest.isGlitch(GlitchNest.glitched(b)) { n += 1 }
                }
            }
        }
        glitch.totals[k] = max(1, n)
        return max(1, n)
    }

    // MARK: Every frame

    func updateGlitch(dt: Float) {
        let here = SIMD2<Float>(player.position.x, player.position.z)

        // Which nests are around.
        glitch.refreshTimer -= dt
        if glitch.refreshTimer <= 0 || simd_distance(here, glitch.nearbyFrom) > 40 {
            glitch.refreshTimer = 2
            glitch.nearbyFrom = here
            glitch.nearby = nests(around: here, radius: 170)
        }

        // Has a nest been wrecked enough to cure it?
        glitch.checkTimer -= dt
        if glitch.checkTimer <= 0 {
            glitch.checkTimer = 0.5
            if world.revision != glitch.lastRevision {
                glitch.lastRevision = world.revision
                for (site, nest) in glitch.nearby where simd_distance(nest.groundCenter, here) < 110 && !glitch.rebuilding.contains(nest.id) {
                    let total = glitchTotal(nest)
                    let left = glitchCount(nest, in: world)
                    let first = !glitch.seen.contains(key(nest))
                    glitch.seen.insert(key(nest))
                    if isCured(nest) {
                        // Cured but the blocks came back (the world wasn't saved): clean it up quietly.
                        if Float(left) > Float(total) * 0.5 { rebuild(nest, quick: true) }
                    } else if Float(left) <= Float(total) * (1 - Game.cureShare) {
                        if first {
                            // Already mostly clean when you got here: built before the Glitch came
                            // (an older save) or wrecked earlier. It counts as cured, no fuss.
                            glitch.setCured(nest.id, on: planet.id, true)
                            cleanUp(nest)
                        } else {
                            cure(nest, in: site)
                        }
                    }
                }
            }
        }

        updateRoboCats(dt: dt, here: here)
        updateNestEffects(dt: dt, here: here)

        // The Glitch fights back. Only the host (or you, playing alone) spreads it.
        if session != .joined {
            glitch.spreadTimer -= dt
            if glitch.spreadTimer <= 0 {
                glitch.spreadTimer = Float.random(in: 150...210)
                spreadGlitch(here: here)
            }
        }
    }

    /// The red glow on Glitch blocks pulses slowly, on every planet.
    func updateGlitchGlow(dt: Float) {
        glitch.glowClock += dt
        glitch.glowTimer -= dt
        guard glitch.glowTimer <= 0, let texture = blockTexture else { return }
        glitch.glowTimer = 0.1
        let pulse = 0.5 + 0.5 * sin(glitch.glowClock * 2.4)
        var colors = (0..<BlockRegistry.maxBlocks).map { BlockRegistry.shared.rgb(UInt8($0)) }
        let dark = BlockRegistry.shared.rgb(SB.glitchBlock)
        let glow = BlockRegistry.shared.rgb(SB.glitchGlow)
        colors[Int(SB.glitchBlock)] = simd_mix(dark, dark * 1.7, SIMD3(repeating: pulse * 0.6))
        colors[Int(SB.glitchGlow)] = simd_mix(glow * 0.75, SIMD3(1, 0.62, 0.62), SIMD3(repeating: pulse))
        PaletteTexture.update(texture, colors: colors)
        // Up close, Glitch blocks are see-through and breathe in and out.
        glitch.glassTimer -= 0.1
        if glitch.glassTimer <= 0, let atlas = blockAtlas {
            glitch.glassTimer = 0.2
            renderer.setGlass(BlockTextures.glassMaterial(atlas, opacity: 0.35 + 0.25 * pulse))
        }
    }

    // MARK: Curing

    private func cure(_ nest: GlitchNest, in site: Settlement) {
        glitch.setCured(nest.id, on: planet.id, true)
        glitch.totalCured += 1
        shareNest(nest.id, cured: true)
        effects.sparkles(at: nest.center, spread: SIMD3<Float>(nest.max &- nest.min) * 0.5)
        Sound.shared.play("cure", volume: 0.9)
        Voices.shared.say("cure", cooldown: 0, interrupt: true)
        show(nest.heart ? "You cured Wolfie Tower, the Glitch's heart!" : "Glitch Nest cured! The builder bots will make it clean again")
        if showHearts && hearts < Game.maxHearts {
            hearts += 1
            Sound.shared.play("heart", volume: 0.6)
        }
        armory.later(2) { [weak self] in self?.rebuild(nest, quick: false) }
        // Every nest in the settlement cured: Glitch-free!
        if nestsLeft(in: site) == 0 {
            let name = settlementName(site)
            armory.later(4.5) { [weak self] in
                self?.show("\(name) is Glitch-free!")
                Voices.shared.say("free", cooldown: 0, interrupt: true)
                Sound.shared.play("craft", volume: 0.8)
            }
        }
    }

    /// The builder bots put a cured nest back, clean, from the ground up.
    func rebuild(_ nest: GlitchNest, quick: Bool, in w: World? = nil) {
        let target = w ?? world
        func layer(_ y: Int) -> [SIMD3<Int>] {
            var placed: [SIMD3<Int>] = []
            for z in nest.min.z..<nest.max.z {
                for x in nest.min.x..<nest.max.x {
                    guard let want = nest.clean(x, y, z) else { continue }
                    let now = target.block(x, y, z)
                    if want == B.air {
                        if GlitchNest.isGlitch(now) { target.set(SIMD3(x, y, z), B.air) }
                    } else if now != want && (now == B.air || GlitchNest.isGlitch(now)) {
                        target.set(SIMD3(x, y, z), want)
                        placed.append(SIMD3(x, y, z))
                    }
                }
            }
            return placed
        }
        if quick || w != nil {
            for y in nest.min.y..<nest.max.y { _ = layer(y) }
            return
        }
        glitch.rebuilding.insert(nest.id)
        let height = nest.max.y - nest.min.y
        let step = min(0.08, 3.5 / Float(max(1, height)))
        for (i, y) in (nest.min.y..<nest.max.y).enumerated() {
            armory.later(Float(i) * step) { [weak self] in
                guard let self else { return }
                let placed = layer(y)
                for p in placed.shuffled().prefix(2) {
                    self.effects.spark(at: SIMD3<Float>(p) + 0.5)
                }
                if i % 3 == 0 && !placed.isEmpty {
                    Sound.shared.play("build-tick", at: SIMD3<Float>(nest.groundCenter.x, Float(y), nest.groundCenter.y),
                                      listener: self.player.eye, facing: self.player.yaw, volume: 0.6, pitch: 0.8 + Float(i) / Float(max(1, height)))
                }
            }
        }
        armory.later(Float(height) * step + 0.2) { [weak self] in
            guard let self else { return }
            self.glitch.rebuilding.remove(nest.id)
            self.show("Good as new!")
            self.save()
        }
    }

    /// Turn any leftover Glitch blocks in a cured nest back to clean ones, without filling gaps.
    private func cleanUp(_ nest: GlitchNest) {
        for y in nest.min.y..<nest.max.y {
            for z in nest.min.z..<nest.max.z {
                for x in nest.min.x..<nest.max.x where GlitchNest.isGlitch(world.block(x, y, z)) {
                    world.set(SIMD3(x, y, z), nest.clean(x, y, z) ?? B.air)
                }
            }
        }
    }

    // MARK: Spreading

    private func spreadGlitch(here: SIMD2<Float>) {
        let candidates = glitch.nearby.filter { isCured($0.nest) && !glitch.rebuilding.contains($0.nest.id) && simd_distance($0.nest.groundCenter, here) > 70 }
        guard let pick = candidates.randomElement() else { return }
        reglitch(pick.nest)
        shareNest(pick.nest.id, cured: false)
        Sound.shared.play("glitch-alarm", volume: 0.6)
        armory.later(0.8) { [weak self] in
            Voices.shared.say("nest", as: "nova", cooldown: 0, interrupt: true)
            self?.show("Nova: a new Glitch Nest just popped up! Check your map")
        }
    }

    /// A building catches the Glitch again.
    func reglitch(_ nest: GlitchNest, in w: World? = nil, planetID: String? = nil) {
        let target = w ?? world
        for y in nest.min.y..<nest.max.y {
            for z in nest.min.z..<nest.max.z {
                for x in nest.min.x..<nest.max.x {
                    guard let clean = nest.clean(x, y, z), clean != B.air, target.block(x, y, z) == clean else { continue }
                    let bad = GlitchNest.glitched(clean)
                    if bad != clean { target.set(SIMD3(x, y, z), bad) }
                }
            }
        }
        let p = planetID ?? planet.id
        glitch.setCured(nest.id, on: p, false)
        glitch.catsLeft["\(p)/\(nest.id)"] = nil
    }

    /// A friend cured or re-glitched a nest.
    func friendNest(_ id: String, cured: Bool, planet planetID: String, world w: World) {
        guard let p = PlanetCatalog.shared.planet(id: planetID), let nest = findNest(id, generator: w.generator, planet: p) else { return }
        if cured {
            guard !glitch.isCured(id, on: planetID) else { return }
            glitch.setCured(id, on: planetID, true)
            if w === world && place == .surface {
                effects.sparkles(at: nest.center, spread: SIMD3<Float>(nest.max &- nest.min) * 0.5)
                Sound.shared.play("cure", volume: 0.6)
                armory.later(2) { [weak self] in self?.rebuild(nest, quick: false) }
            } else {
                rebuild(nest, quick: true, in: w)
            }
        } else {
            reglitch(nest, in: w, planetID: planetID)
            if w === world && place == .surface {
                Sound.shared.play("glitch-alarm", volume: 0.5)
                show("Nova: a new Glitch Nest just popped up! Check your map")
            }
        }
    }

    // MARK: Robo-cats

    private func updateRoboCats(dt: Float, here: SIMD2<Float>) {
        if GameSettings.shared.danger == 0 {
            if roboCats.count > 0 { roboCats.clear() }
            return
        }
        // New cats trot out of nests near you.
        glitch.spawnTimer -= dt
        if glitch.spawnTimer <= 0 {
            glitch.spawnTimer = Float.random(in: 2.5...4.5)
            if roboCats.count < catsOut, travelText == nil {
                let close = glitch.nearby
                    .filter { !isCured($0.nest) && simd_distance($0.nest.groundCenter, here) < 55 }
                    .filter { (glitch.catsLeft[key($0.nest)] ?? catsPerNest) > 0 }
                    .sorted { simd_distance($0.nest.groundCenter, here) < simd_distance($1.nest.groundCenter, here) }
                if let pick = close.first {
                    let k = key(pick.nest)
                    glitch.catsLeft[k] = (glitch.catsLeft[k] ?? catsPerNest) - 1
                    roboCats.spawn(near: pick.nest, world: world)
                }
            }
        }

        let w = world
        let events = roboCats.update(dt: dt, player: player.position, world: w, rules: catRules) { from, to in
            Game.clearLine(w, from, to)
        }
        for event in events {
            switch event {
            case .charge(let at):
                Sound.shared.play("robocat-charge", at: at, listener: player.eye, facing: player.yaw, volume: 0.5)
            case let .shot(from, to, hit):
                Sound.shared.play("robocat-meow", at: from, listener: player.eye, facing: player.yaw, volume: 0.9, pitch: Float.random(in: 0.92...1.1))
                Sound.shared.play("robocat-laser", at: from, listener: player.eye, facing: player.yaw, volume: 0.6)
                effects.fireBolt(from: from, to: to, color: SIMD3(1, 0.2, 0.25), speed: 60) { [weak self] in
                    guard let self else { return }
                    if hit && self.driving == nil {
                        self.hurt(1)
                    } else {
                        self.effects.spark(at: to)
                    }
                }
            }
        }
        if roboCats.collectHeart(near: player.position) {
            if hearts < Game.maxHearts { hearts += 1 }
            Sound.shared.play("heart", volume: 0.7)
        }
    }

    /// Nothing solid between two points (robo-cats can't shoot through walls).
    static func clearLine(_ world: World, _ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool {
        let span = b - a
        let length = simd_length(span)
        guard length > 0.01 else { return true }
        let steps = Int(length / 0.4) + 1
        for i in 1..<steps {
            let p = a + span * (Float(i) / Float(steps))
            if world.isSolidForPhysics(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z))) { return false }
        }
        return true
    }

    /// A robo-cat got hit by something of yours.
    func hitCat(_ id: Int, from origin: SIMD3<Float>, direct: Bool = false) {
        let at = roboCats.position(of: id) ?? origin
        if roboCats.hit(id, from: origin, hitsToSleep: catRules.hitsToSleep, direct: direct) {
            catAsleep(at: at)
        } else {
            Sound.shared.play("robocat-hurt", at: at, listener: player.eye, facing: player.yaw, volume: 0.9, pitch: Float.random(in: 0.95...1.1))
        }
    }

    /// Blasts and black holes catch any cats nearby.
    func blastCats(at point: SIMD3<Float>, radius: Float) {
        let result = roboCats.blast(at: point, radius: radius, hitsToSleep: catRules.hitsToSleep)
        for spot in result.asleep { catAsleep(at: spot) }
        if result.hurt > 0 {
            Sound.shared.play("robocat-hurt", at: point, listener: player.eye, facing: player.yaw, volume: 0.8)
        }
    }

    private func catAsleep(at point: SIMD3<Float>) {
        Sound.shared.play("robocat-down", at: point, listener: player.eye, facing: player.yaw, volume: 1, pitch: Float.random(in: 0.95...1.05))
        effects.spark(at: point + SIMD3(0, 0.8, 0))
        glitch.catsKnockedOut += 1
        // "Glitch cleared!": a knocked-out robo-cat is a cured machine.
        Voices.shared.say("cure", chance: 0.35, cooldown: 30)
    }

    /// The nearest robo-cat in front of you, if it's closer than any block.
    func catInLine(_ aim: LaserAim, range: Float) -> (id: Int, distance: Float, point: SIMD3<Float>)? {
        guard let cat = roboCats.target(origin: aim.origin, direction: aim.direction, maxDistance: range) else { return nil }
        if let block = raycast(world: world, origin: aim.origin, direction: aim.direction, maxDistance: range) {
            let center = SIMD3<Float>(block.block) + 0.5
            if simd_distance(aim.origin, center) - 0.5 < cat.distance { return nil }
        }
        return cat
    }

    // MARK: Glow, hum and sparks

    private func updateNestEffects(dt: Float, here: SIMD2<Float>) {
        var nearest: Float = .infinity
        glitch.sparkTimer -= dt
        let spark = glitch.sparkTimer <= 0
        if spark { glitch.sparkTimer = 0.12 }
        for (_, nest) in glitch.nearby where !isCured(nest) {
            let d = simd_distance(nest.groundCenter, here)
            nearest = min(nearest, d)
            if spark && d < 60 && Int.random(in: 0..<3) == 0 {
                let size = SIMD3<Float>(nest.max &- nest.min)
                let p = SIMD3<Float>(nest.min) + SIMD3(Float.random(in: 0...1), Float.random(in: 0...1), Float.random(in: 0...1)) * size
                effects.glitchSpark(at: p)
            }
        }
        let hum = nearest < 26
        if hum != glitch.humming {
            glitch.humming = hum
            if hum {
                Sound.shared.startLoop("glitch-hum", channel: "glitch", volume: 0.35)
            } else {
                Sound.shared.stopLoop(channel: "glitch")
            }
        }
    }

    func stopGlitchHum() {
        if glitch.humming {
            glitch.humming = false
            Sound.shared.stopLoop(channel: "glitch")
        }
    }
}
