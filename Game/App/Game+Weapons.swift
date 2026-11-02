import Foundation
import RealityKit
import simd

/// The Wolfie Military arsenal: hand tools, guns, launchers, explosives, air strikes and the
/// Black Hole. Everything is set up in Resources/weapons.json.
///
/// The Red Glitch rules still hold: blasts only break blocks. Your own explosions never hurt you,
/// friendly critters just get a fright and run, and grumpy ones poof home.
extension Game {
    var heldWeapon: WeaponDef? { heldItem.weapon }

    // MARK: Pulling the trigger

    /// On foot with a weapon in hand.
    func updateWeapon(_ def: WeaponDef, frame: InputFrame, dt: Float, aim: LaserAim, critter: AimedCritter?) {
        highlight.isEnabled = false
        ghost.isEnabled = false
        let pressed = frame.breakHeld && !armory.lastTrigger
        let placePressed = frame.placeHeld && !armory.lastPlace
        armory.lastTrigger = frame.breakHeld
        armory.lastPlace = frame.placeHeld

        // The Sniper's scope.
        setZoom(def.zoom > 1 && frame.placeHeld ? def.zoom : 1)

        // Remote charges all go off together.
        if def.remote && placePressed { detonateRemotes() }

        if def.type == .flame {
            updateFlamer(def, firing: frame.breakHeld, dt: dt, aim: aim, critter: critter)
            return
        }
        let wants = def.hold ? frame.breakHeld : pressed
        if wants && armory.cooldown <= 0 {
            armory.cooldown = def.cooldown
            fire(def, aim: aim, critter: critter)
        }
    }

    /// Put the weapon away: stop the flamer, drop the scope.
    func holsterWeapon() {
        if armory.flaming {
            armory.flaming = false
            Sound.shared.stopLoop()
        }
        setZoom(1)
        armory.lastTrigger = false
    }

    private func setZoom(_ zoom: Float) {
        let zoomed = zoom > 1
        guard zoomed != armory.zoomed else { return }
        armory.zoomed = zoomed
        scoped = zoomed
        camera.camera.fieldOfViewInDegrees = zoomed ? 70 / zoom : 70
        Sound.shared.play("hotbar", volume: 0.5, pitch: zoomed ? 0.8 : 1.1)
    }

    private func fire(_ def: WeaponDef, aim: LaserAim, critter: AimedCritter?) {
        switch def.type {
        case .melee: swingTool(def, aim: aim, critter: critter)
        case .gun: shoot(def, aim: aim, critter: critter)
        case .projectile, .sticky, .mine: launch(def, aim: aim)
        case .strike: callStrike(def, aim: aim)
        case .blackhole: openBlackHole(def, aim: aim)
        case .flame: break
        }
    }

    // MARK: Hand tools

    private func swingTool(_ def: WeaponDef, aim: LaserAim, critter: AimedCritter?) {
        me.swing()
        if let cat = catInLine(aim, range: def.range) {
            hitCat(cat.id, from: aim.origin, direct: def.radius > 1)
            Sound.shared.playVaried(def.sound, volume: 0.8)
            return
        }
        if let critter, critter.distance <= def.range {
            zapCritter(critter)
            Sound.shared.playVaried(def.sound, volume: 0.8)
            return
        }
        guard let hit = raycast(world: world, origin: aim.origin, direction: aim.direction, maxDistance: def.range), hit.block.y > 0 else {
            Sound.shared.play("startle", volume: 0.3, pitch: 0.6)
            return
        }
        let center = SIMD3<Float>(hit.block) + 0.5
        if def.radius < 1 {
            let id = world.block(hit.block)
            changeBlock(hit.block, B.air)
            dropPickup(id, at: center)
            effects.blockBurst(at: center, blockColor: BlockRegistry.shared.rgb(id))
        } else {
            smash(at: center, radius: def.radius, effect: false)
            effects.explosion(at: center, radius: 0.7, colors: [])
        }
        Sound.shared.playVaried(def.sound, volume: 0.55)
        armory.shake = max(armory.shake, def.radius > 1 ? 0.12 : 0.05)
    }

    private func updateFlamer(_ def: WeaponDef, firing: Bool, dt: Float, aim: LaserAim, critter: AimedCritter?) {
        guard firing else {
            if armory.flaming {
                armory.flaming = false
                Sound.shared.stopLoop()
            }
            return
        }
        if !armory.flaming {
            armory.flaming = true
            Sound.shared.startLoop("flame-loop", volume: 0.22)
        }
        armory.flameSpray -= dt
        if armory.flameSpray <= 0 {
            armory.flameSpray = 0.03
            effects.flameJet(from: aim.muzzle, direction: aim.direction, range: def.range)
        }
        armory.flameTimer -= dt
        guard armory.flameTimer <= 0 else { return }
        armory.flameTimer = def.cooldown
        if let cat = catInLine(aim, range: def.range) {
            hitCat(cat.id, from: aim.origin)
            return
        }
        if let critter, critter.distance <= def.range, critter.kind.isGrumpy {
            zapCritter(critter)
            return
        }
        // Blocks catch fire and crumble, and the fire creeps to their neighbours.
        guard let hit = raycast(world: world, origin: aim.origin, direction: aim.direction, maxDistance: def.range), hit.block.y > 0 else { return }
        var burning = [hit.block]
        let around = [SIMD3<Int>(0, 1, 0), SIMD3(1, 0, 0), SIMD3(-1, 0, 0), SIMD3(0, 0, 1), SIMD3(0, 0, -1), SIMD3(0, -1, 0)]
        for offset in around.shuffled().prefix(Int.random(in: 0...2)) {
            let p = hit.block &+ offset
            if p.y > 0 && world.block(p) != B.air { burning.append(p) }
        }
        for (i, p) in burning.enumerated() {
            let id = world.block(p)
            changeBlock(p, B.air)
            if i == 0 {
                dropPickup(id, at: SIMD3<Float>(p) + 0.5)
                effects.blockBurst(at: SIMD3<Float>(p) + 0.5, blockColor: SIMD3(0.2, 0.18, 0.16))
            }
        }
        noteBlockBlasted()
    }

    // MARK: Guns

    private func shoot(_ def: WeaponDef, aim: LaserAim, critter: AimedCritter?) {
        // Fast guns are quieter, so a long burst doesn't get tiring.
        Sound.shared.playVaried(def.sound, volume: def.cooldown < 0.15 ? 0.28 : 0.45, spread: 0.06)
        armory.shake = max(armory.shake, def.pierce >= 8 ? 0.1 : 0.03)
        for pellet in 0..<max(1, def.pellets) {
            var direction = aim.direction
            if def.spread > 0 {
                let jitter = SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)) * def.spread
                direction = simd_normalize(direction + jitter)
            }
            // Bullets go through blocks one after another, up to the weapon's pierce.
            var broken: [(SIMD3<Int>, UInt8)] = []
            var end = aim.origin + direction * def.range
            var hitCritter: AimedCritter?
            var hitCatID: Int?
            if let cat = catInLine(LaserAim(origin: aim.origin, direction: direction, muzzle: aim.muzzle), range: def.range) {
                hitCatID = cat.id
                end = cat.point
            } else if pellet == 0, let critter, critter.distance < def.range {
                hitCritter = critter
                end = critter.point
            } else {
                for _ in 0..<max(1, def.pierce) {
                    guard let hit = raycast(world: world, origin: aim.origin, direction: direction, maxDistance: def.range), hit.block.y > 0 else { break }
                    let id = world.block(hit.block)
                    broken.append((hit.block, id))
                    changeBlock(hit.block, B.air)
                    end = SIMD3<Float>(hit.block) + 0.5
                }
            }
            let tracer = def.color
            let first = broken.first
            let last = broken.last
            let count = broken.count
            effects.fireBolt(from: aim.muzzle, to: end, color: tracer, speed: 240) { [weak self] in
                guard let self else { return }
                if let hitCatID {
                    self.hitCat(hitCatID, from: aim.origin, direct: def.pierce >= 8)
                } else if let hitCritter {
                    self.zapCritter(hitCritter)
                } else if let first {
                    let center = SIMD3<Float>(first.0) + 0.5
                    self.dropPickup(first.1, at: center)
                    self.effects.blockBurst(at: center, blockColor: BlockRegistry.shared.rgb(first.1))
                    if let last, count > 1 {
                        self.effects.blockBurst(at: SIMD3<Float>(last.0) + 0.5, blockColor: BlockRegistry.shared.rgb(last.1))
                    }
                    for _ in 0..<count { self.noteBlockBlasted() }
                } else {
                    self.effects.spark(at: end)
                }
            }
        }
    }

    // MARK: Launchers and explosives

    private func launch(_ def: WeaponDef, aim: LaserAim) {
        guard armory.shots.count < Armory.maxShots else { return }
        Sound.shared.playVaried(def.sound, volume: def.cooldown < 0.4 ? 0.32 : 0.45, spread: 0.08)
        var direction = aim.direction
        if def.lob > 0 { direction = simd_normalize(direction + SIMD3(0, def.lob, 0)) }
        let start = aim.muzzle + direction * 0.4
        var shot = makeShot(look: def.look, size: def.size, at: start, velocity: direction * def.speed, radius: def.radius)
        shot.gravity = def.gravity
        shot.fuse = def.type == .mine || def.remote ? 0 : def.fuse
        shot.bounce = def.bounce
        shot.pierceLeft = def.pierce
        shot.drillLeft = def.drill
        shot.sticky = def.type == .sticky || def.type == .mine
        shot.remote = def.remote
        shot.mine = def.type == .mine
        shot.bomblets = def.count > 1 && def.type == .projectile ? def.count : 0
        shot.trail = def.look == "rocket" ? 2 : 0
        armory.shots.append(shot)
        if def.look == "rocket" || def.look == "ball" { armory.shake = max(armory.shake, 0.05) }
    }

    private func makeShot(look: String, size: Float, at start: SIMD3<Float>, velocity: SIMD3<Float>, radius: Float) -> Armory.Shot {
        let model = Shots.model(look, size: size)
        model.entity.position = start
        armory.root.addChild(model.entity)
        return Armory.Shot(entity: model.entity, light: model.light, look: look, position: start, velocity: velocity, gravity: 0, radius: radius)
    }

    private func detonateRemotes() {
        var delay: Float = 0
        var any = false
        for i in armory.shots.indices where armory.shots[i].remote && armory.shots[i].stuck {
            armory.shots[i].fuse = 0.05 + delay
            delay += 0.09
            any = true
        }
        if any {
            Sound.shared.play("beep", volume: 0.7, pitch: 1.3)
        } else {
            show("Throw some Remote charges first")
        }
    }

    // MARK: Every frame

    /// Move everything in flight, count down fuses, run air strikes and the black hole.
    func updateArmory(dt: Float) {
        armory.clock += dt
        armory.cooldown -= dt
        armory.shake = max(0, armory.shake - dt * 1.8)

        // Things scheduled for now.
        if !armory.pending.isEmpty {
            let now = armory.clock
            let due = armory.pending.filter { $0.time <= now }
            armory.pending.removeAll { $0.time <= now }
            for item in due { item.run() }
        }

        updateShots(dt: dt)
        updateFlyers(dt: dt)
        updateHole(dt: dt)
        armory.clouds.removeAll { cloud in
            if cloud.update(dt: dt) { return false }
            cloud.root.removeFromParent()
            return true
        }
        if armory.holeWaiting && armory.clock >= armory.holeReadyAt {
            armory.holeWaiting = false
            show("Black hole ready!")
            Sound.shared.play("heart", volume: 0.5)
        }
    }

    /// Big booms wobble the camera a little.
    func shakeCamera() {
        guard armory.shake > 0.001 else { return }
        let s = armory.shake
        camera.position += SIMD3<Float>(Float.random(in: -s...s), Float.random(in: -s...s), Float.random(in: -s...s))
    }

    private func updateShots(dt: Float) {
        var blow: [Int] = []
        for i in armory.shots.indices {
            var s = armory.shots[i]
            s.age += dt
            if s.fuse > 0 {
                s.fuse -= dt
                if s.fuse <= 0 { s.fuse = 0.0001; blow.append(i) }
                // Blink faster as the fuse runs down.
                if let light = s.light {
                    light.isEnabled = sin(s.age * (s.fuse < 1 ? 40 : 14)) > 0
                    if light.isEnabled && Int(s.age * 2) != Int((s.age - dt) * 2) && s.sticky {
                        Sound.shared.play("beep", at: s.position, listener: player.eye, facing: player.yaw, volume: 0.35, pitch: s.fuse < 1 ? 1.5 : 1.1)
                    }
                }
            }
            if s.stuck {
                if s.mine {
                    s.armed += dt
                    s.light?.isEnabled = sin(s.age * 3) > 0.6
                    if s.armed > 1, mineTriggered(at: s.position) {
                        Sound.shared.play("beep", at: s.position, listener: player.eye, facing: player.yaw, volume: 0.6, pitch: 1.8)
                        s.fuse = 0.2
                        s.mine = false
                    }
                } else if s.remote {
                    s.light?.isEnabled = sin(s.age * 4) > 0.3
                }
                armory.shots[i] = s
                continue
            }
            if blow.contains(i) {
                armory.shots[i] = s
                continue
            }
            if s.homing, let target = s.target {
                let want = simd_normalize(target - s.position) * simd_length(s.velocity)
                s.velocity += (want - s.velocity) * min(1, dt * 2.5)
            }
            s.velocity.y -= s.gravity * dt
            let move = s.velocity * dt
            let distance = simd_length(move)
            let steps = max(1, Int(ceil(distance / 0.3)))
            var stop = false
            for _ in 0..<steps {
                let previous = s.position
                s.position += move / Float(steps)
                if let target = s.target {
                    // Air strikes ignore everything until they're nearly there.
                    if simd_distance(s.position, target) > 3 && s.position.y > target.y - 1 { continue }
                    if s.homing && simd_distance(s.position, target) < 1.2 { blow.append(i); stop = true; break }
                }
                let cell = SIMD3<Int>(Int(floor(s.position.x)), Int(floor(s.position.y)), Int(floor(s.position.z)))
                if s.position.y < 0 { blow.append(i); stop = true; break }
                // Straight into a robo-cat.
                if !s.drilling && roboCats.nearestDistance(to: s.position) < 0.8 {
                    if s.bounce || s.sticky { s.velocity *= -0.3; s.position = previous; break }
                    blow.append(i); stop = true; break
                }
                if s.drilling {
                    let id = world.block(cell)
                    if id != B.air && cell.y > 0 {
                        changeBlock(cell, B.air)
                        s.drillLeft -= 1
                        if Int.random(in: 0..<3) == 0 { effects.spark(at: s.position) }
                        if s.drillLeft <= 0 { blow.append(i); stop = true; break }
                    }
                    continue
                }
                guard world.isSolidForPhysics(cell.x, cell.y, cell.z) else { continue }
                if s.drillLeft > 0 {
                    s.drilling = true
                    s.velocity = simd_normalize(s.velocity) * 12
                    s.trail = 0
                    Sound.shared.play("hammer", at: s.position, listener: player.eye, facing: player.yaw, volume: 0.7, pitch: 0.6)
                    continue
                }
                if s.pierceLeft > 0, cell.y > 0 {
                    let id = world.block(cell)
                    changeBlock(cell, B.air)
                    effects.blockBurst(at: SIMD3<Float>(cell) + 0.5, blockColor: BlockRegistry.shared.rgb(id))
                    noteBlockBlasted()
                    s.pierceLeft -= 1
                    s.velocity *= 0.92
                    if s.pierceLeft == 0 { blow.append(i); stop = true; break }
                    continue
                }
                if s.bounce {
                    let was = SIMD3<Int>(Int(floor(previous.x)), Int(floor(previous.y)), Int(floor(previous.z)))
                    if was.x != cell.x { s.velocity.x *= -0.45 }
                    if was.y != cell.y { s.velocity.y *= -0.4; s.velocity.x *= 0.7; s.velocity.z *= 0.7 }
                    if was.z != cell.z { s.velocity.z *= -0.45 }
                    s.position = previous
                    if simd_length(s.velocity) > 2.5 {
                        Sound.shared.play("bounce", at: s.position, listener: player.eye, facing: player.yaw, volume: 0.5, pitch: Float.random(in: 0.9...1.2))
                    }
                    break
                }
                if s.sticky {
                    s.position = previous
                    s.stuck = true
                    s.velocity = .zero
                    Sound.shared.play("stick", at: s.position, listener: player.eye, facing: player.yaw, volume: 0.6)
                    if s.remote && armory.shots.filter({ $0.remote && $0.stuck }).isEmpty {
                        show("Stuck on! Press \(keyboardMode ? "right-click" : Btn.use) to set them off")
                    }
                    break
                }
                s.position = previous
                blow.append(i)
                stop = true
                break
            }
            if !stop && s.age > 14 { blow.append(i) }
            // Rockets point where they fly; grenades tumble.
            s.entity.position = s.position
            if s.look == "grenade" || s.look == "charge" {
                if !s.stuck { s.entity.orientation = simd_quatf(angle: s.age * 9, axis: SIMD3(1, 0.3, 0)) }
            } else if s.look != "mine", simd_length(s.velocity) > 0.5 {
                s.entity.orientation = simd_quatf(from: SIMD3<Float>(0, 0, -1), to: simd_normalize(s.velocity))
            }
            if s.trail > 0 {
                s.trailTimer -= dt
                if s.trailTimer <= 0 {
                    s.trailTimer = 0.035
                    effects.trail(at: s.position - simd_normalize(s.velocity + SIMD3(0, 0.0001, 0)) * 0.5, fire: s.trail == 2)
                }
            }
            if !s.whistled, s.target != nil, s.velocity.y < -5, let target = s.target, simd_distance(s.position, target) < 60 {
                s.whistled = true
                Sound.shared.play("whistle", at: s.position, listener: player.eye, facing: player.yaw, volume: 0.6, pitch: Float.random(in: 0.9...1.1))
            }
            armory.shots[i] = s
        }
        // Blow up the ones that are done, last first so the indices stay right.
        for i in Set(blow).sorted(by: >) where armory.shots.indices.contains(i) {
            let s = armory.shots.remove(at: i)
            s.entity.removeFromParent()
            if s.bomblets > 0 {
                burst(s)
            } else if s.position.y >= 0 {
                explode(at: s.position, radius: s.radius, nuke: s.nuke)
            }
        }
    }

    /// The Cluster bomb pops into little bombs that scatter and blow where they land.
    private func burst(_ s: Armory.Shot) {
        Sound.shared.play("bounce", at: s.position, listener: player.eye, facing: player.yaw, volume: 0.8, pitch: 0.7)
        effects.explosion(at: s.position, radius: 0.6, colors: [])
        for k in 0..<s.bomblets {
            let a = Float(k) / Float(s.bomblets) * 2 * .pi + Float.random(in: -0.3...0.3)
            let v = SIMD3<Float>(cos(a) * Float.random(in: 4...7), Float.random(in: 4...8), sin(a) * Float.random(in: 4...7))
            var bomb = makeShot(look: "grenade", size: 0.6, at: s.position, velocity: v, radius: s.radius)
            bomb.gravity = 20
            bomb.fuse = Float.random(in: 0.9...1.6)
            bomb.bounce = true
            armory.shots.append(bomb)
        }
    }

    private func mineTriggered(at p: SIMD3<Float>) -> Bool {
        if critters.nearestDistance(to: p) < 2 || roboCats.nearestDistance(to: p) < 2.2 { return true }
        for v in vehicles.values where simd_distance(v.position, p) < 3.2 { return true }
        return false
    }

    // MARK: Explosions

    /// Blow a hole in the world. Your own blasts never hurt you; they just push you a bit.
    @discardableResult
    func explode(at p: SIMD3<Float>, radius r: Float, nuke: Bool = false, fromFriend: Bool = false) -> Int {
        let removed = Game.carve(world, at: p, radius: r)
        if !fromFriend { shareBlast(at: p, radius: r) }
        var colors: [SIMD3<Float>] = []
        for (_, id) in removed.prefix(40) {
            let c = BlockRegistry.shared.rgb(id)
            if !colors.contains(c) { colors.append(c) }
            if colors.count >= 4 { break }
        }
        effects.explosion(at: p, radius: min(r, 6), colors: colors)
        if r >= 5 {
            // Big ones get a ring of extra fireballs.
            for k in 0..<5 {
                let a = Float(k) / 5 * 2 * .pi
                effects.explosion(at: p + SIMD3(cos(a), 0.3, sin(a)) * r * 0.55, radius: min(r * 0.5, 4), colors: colors)
            }
        }
        let distance = simd_distance(p, camera.position)
        let loud = max(0.12, min(0.7, (10 + r * 5) / max(distance, 1)))
        let sound = nuke ? "nuke" : (r >= 6 ? "boom-huge" : (r >= 3.4 ? "boom-big" : "explode"))
        Sound.shared.playVaried(sound, volume: loud, spread: 0.08)
        armory.shake = max(armory.shake, min(0.9, r * 0.05 * max(0.2, 1 - distance / (r * 12))))
        if nuke {
            let cloud = MushroomCloud(at: SIMD3(p.x, Float(world.surfaceY(x: Int(p.x), z: Int(p.z))), p.z))
            armory.root.addChild(cloud.root)
            armory.clouds.append(cloud)
        }
        blastCats(at: p, radius: r * 1.6 + 1)
        guard !fromFriend else { return removed.count }

        // A few bits to pick up.
        for (cell, id) in removed.shuffled().prefix(min(6, removed.count)) {
            dropPickup(id, at: SIMD3<Float>(cell) + 0.5)
        }
        // Critters: grumpy ones poof home, friendly ones just run.
        for result in critters.blast(at: p, radius: r * 1.6 + 1) {
            if case .poofed(let kind, _) = result, !foundCritters.contains(kind.id) {
                foundCritters.insert(kind.id)
                UserDefaults.standard.set(Array(foundCritters).sorted(), forKey: "critterBook")
                show("You sent a \(kind.name) home! It's in your Critter Book")
            }
        }
        // Mines and charges nearby go off too.
        for i in armory.shots.indices where armory.shots[i].stuck && simd_distance(armory.shots[i].position, p) < r + 1.5 {
            if armory.shots[i].fuse <= 0 || armory.shots[i].fuse > 0.25 { armory.shots[i].fuse = Float.random(in: 0.12...0.3) }
            armory.shots[i].mine = false
            armory.shots[i].remote = false
        }
        // A push, never a hurt.
        let away = player.position + SIMD3(0, 0.9, 0) - p
        let d = simd_length(away)
        if driving == nil && d < r * 2.2 && d > 0.01 {
            let strength = (1 - d / (r * 2.2)) * min(14, 4 + r)
            player.knock(simd_normalize(away) * strength + SIMD3(0, strength * 0.5, 0))
        }
        return removed.count
    }

    /// Hammers and sledges: break a small ball of blocks.
    private func smash(at p: SIMD3<Float>, radius r: Float, effect: Bool) {
        let removed = Game.carve(world, at: p, radius: r)
        shareBlast(at: p, radius: r)
        if let first = removed.first { dropPickup(first.1, at: SIMD3<Float>(first.0) + 0.5) }
        for _ in removed.prefix(4) { noteBlockBlasted() }
    }

    /// The ball of blocks a blast takes out, with a slightly rough edge. The same blast always
    /// takes out the same blocks, so friends' worlds match.
    @discardableResult
    static func carve(_ world: World, at p: SIMD3<Float>, radius r: Float) -> [(SIMD3<Int>, UInt8)] {
        var removed: [(SIMD3<Int>, UInt8)] = []
        let reach = Int(ceil(r))
        let c = SIMD3<Int>(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)))
        for dy in -reach...reach {
            let y = c.y + dy
            guard y > 0, y < World.height else { continue }
            for dz in -reach...reach {
                for dx in -reach...reach {
                    let cell = SIMD3<Int>(c.x + dx, y, c.z + dz)
                    let center = SIMD3<Float>(cell) + 0.5
                    let d = simd_distance(center, p)
                    guard d <= r else { continue }
                    if d > r - 1, Game.roughness(cell) > (r - d) { continue }
                    let id = world.block(cell)
                    guard id != B.air else { continue }
                    world.set(cell, B.air)
                    removed.append((cell, id))
                }
            }
        }
        return removed
    }

    /// 0...1, the same for a cell every time.
    private static func roughness(_ p: SIMD3<Int>) -> Float {
        var h = UInt32(truncatingIfNeeded: p.x &* 73856093) ^ UInt32(truncatingIfNeeded: p.y &* 19349663) ^ UInt32(truncatingIfNeeded: p.z &* 83492791)
        h ^= h >> 13
        h = h &* 0x5bd1e995
        h ^= h >> 15
        return Float(h % 1000) / 1000
    }

    // MARK: Air strikes

    private func strikeTarget(_ aim: LaserAim) -> SIMD3<Float> {
        if let hit = raycast(world: world, origin: aim.origin, direction: aim.direction, maxDistance: 260) {
            return SIMD3<Float>(hit.previous) + 0.5
        }
        var p = aim.origin + aim.direction * 80
        p.y = Float(world.surfaceY(x: Int(floor(p.x)), z: Int(floor(p.z))))
        return p
    }

    private func groundBelow(_ p: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(p.x, Float(world.surfaceY(x: Int(floor(p.x)), z: Int(floor(p.z)))) + 0.5, p.z)
    }

    private func callStrike(_ def: WeaponDef, aim: LaserAim) {
        let target = strikeTarget(aim)
        var flat = SIMD3<Float>(aim.direction.x, 0, aim.direction.z)
        flat = simd_length(flat) > 0.01 ? simd_normalize(flat) : SIMD3(0, 0, -1)
        let side = SIMD3<Float>(-flat.z, 0, flat.x)
        Sound.shared.play("radio", volume: 0.7)
        effects.spark(at: target + SIMD3(0, 0.5, 0))
        let n = max(1, def.count)

        func scatter() -> SIMD3<Float> {
            let a = Float.random(in: 0...(2 * .pi))
            let d = sqrt(Float.random(in: 0...1)) * def.spread
            return groundBelow(target + SIMD3(cos(a) * d, 0, sin(a) * d))
        }
        func drop(_ look: String, size: Float, from start: SIMD3<Float>, to end: SIMD3<Float>, speed: Float, trail: Int = 0, nuke: Bool = false, radius: Float? = nil) {
            guard armory.shots.count < Armory.maxShots else { return }
            var shot = makeShot(look: look, size: size, at: start, velocity: simd_normalize(end - start) * speed, radius: radius ?? def.radius)
            shot.target = end
            shot.trail = trail
            shot.nuke = nuke
            armory.shots.append(shot)
        }

        switch def.style {
        case "artillery":
            show("Artillery incoming!")
            let from = -flat * 0.7 + SIMD3(0, 1, 0)
            for i in 0..<n {
                armory.later(1.2 + Float(i) * 0.3) {
                    let end = scatter()
                    drop("shell", size: 1.2, from: end + simd_normalize(from) * 110, to: end, speed: 75)
                    if i % 2 == 0 { Sound.shared.play("cannon", volume: 0.25, pitch: 0.6) }
                }
            }
        case "missiles":
            show("Missiles away!")
            for i in 0..<n {
                armory.later(0.6 + Float(i) * 0.22) {
                    let end = scatter()
                    let from = SIMD3<Float>(Float.random(in: -0.3...0.3), 1, Float.random(in: -0.3...0.3)) - flat * 0.3
                    drop("rocket", size: 1.8, from: end + simd_normalize(from) * 90, to: end, speed: 60, trail: 2)
                }
            }
        case "meteors":
            show("Meteor shower!")
            let sky = simd_normalize(side * Float.random(in: -1...1) + SIMD3(0, 1.4, 0) - flat * 0.4)
            for i in 0..<n {
                armory.later(0.4 + Float(i) * 0.35) {
                    let end = scatter()
                    drop("meteor", size: Float.random(in: 0.8...1.4), from: end + sky * 120, to: end, speed: 48, trail: 2)
                }
            }
        case "mega":
            show("Mega bomb!")
            armory.later(1) { drop("bomb", size: 1.8, from: target + SIMD3(0, 120, 0), to: target, speed: 55) }
        case "nuke":
            show("Nuke incoming! Get back!")
            armory.later(1.5) { drop("bomb", size: 2.6, from: target + SIMD3(0, 160, 0), to: target, speed: 50, nuke: true) }
        case "cruise":
            show("Cruise missile on the way!")
            let start = target - flat * 140 + SIMD3(0, 14, 0)
            drop("rocket", size: 3, from: start, to: target, speed: 70, trail: 2)
            Sound.shared.play("jet", volume: 0.5, pitch: 1.3)
        case "drones":
            show("Drones away!")
            for i in 0..<n {
                armory.later(Float(i) * 0.25) { [weak self] in
                    guard let self else { return }
                    let end = scatter()
                    let up = SIMD3<Float>(Float.random(in: -1...1), 1.2, Float.random(in: -1...1))
                    var shot = self.makeShot(look: "drone", size: 1, at: self.player.eye + SIMD3(0, 0.5, 0), velocity: simd_normalize(up) * 20, radius: def.radius)
                    shot.target = end
                    shot.homing = true
                    self.armory.shots.append(shot)
                    Sound.shared.play("drone", volume: 0.5, pitch: Float.random(in: 0.9...1.2))
                }
            }
        case "jets", "bomber":
            let bomber = def.style == "bomber"
            show(bomber ? "Here comes the bomber!" : "Jets inbound!")
            let kind: VehicleKind = bomber ? .hauler : .zoomer
            let height: Float = bomber ? 46 : 34
            let speed: Float = bomber ? 42 : 75
            let start = target - flat * 160 + SIMD3(0, height, 0)
            let end = target + flat * 160 + SIMD3(0, height, 0)
            flyOver(kind: kind, from: start, to: end, speed: speed)
            Sound.shared.play(bomber ? "bomber" : "jet", volume: 0.7)
            let spacing = def.spread / Float(max(1, n - 1))
            for i in 0..<n {
                let along = (Float(i) - Float(n - 1) / 2) * spacing
                let ground = groundBelow(target + flat * along + side * Float.random(in: -1.5...1.5))
                // Released as the ship passes overhead.
                let when = (160 + along) / speed - 0.6
                armory.later(max(0, when)) {
                    drop("bomb", size: 0.7, from: ground + SIMD3(0, height - 2, 0) - flat * 4, to: ground, speed: 45)
                }
            }
        case "gunship":
            show("Gunship on station!")
            circle(kind: .comet, around: target, radius: 26, height: 30, seconds: 9)
            Sound.shared.play("gunship", volume: 0.6)
            for i in 0..<n {
                armory.later(1.5 + Float(i) * (7 / Float(n))) { [weak self] in
                    guard let self, let ship = self.armory.flyers.last(where: { $0.circle != nil }) else { return }
                    let end = scatter()
                    self.effects.fireBolt(from: ship.entity.position, to: end, color: SIMD3(1, 0.6, 0.2), speed: 160) { [weak self] in
                        self?.explode(at: end, radius: def.radius)
                    }
                    Sound.shared.play("bolt", at: ship.entity.position, listener: self.player.eye, facing: self.player.yaw, volume: 0.6, pitch: 0.7)
                }
            }
        default:
            break
        }
    }

    private func flyOver(kind: VehicleKind, from start: SIMD3<Float>, to end: SIMD3<Float>, speed: Float) {
        guard let model = DetailModels.entity(named: kind.modelName) else { return }
        armory.root.addChild(model)
        armory.flyers.append(Armory.Flyer(entity: model, turn: kind.modelTurn, start: start, end: end,
                                          duration: simd_distance(start, end) / speed))
    }

    private func circle(kind: VehicleKind, around center: SIMD3<Float>, radius: Float, height: Float, seconds: Float) {
        guard let model = DetailModels.entity(named: kind.modelName) else { return }
        armory.root.addChild(model)
        armory.flyers.append(Armory.Flyer(entity: model, turn: kind.modelTurn, start: SIMD3(radius, height, 0), end: .zero,
                                          duration: seconds, circle: center))
    }

    private func updateFlyers(dt: Float) {
        for i in armory.flyers.indices.reversed() {
            armory.flyers[i].age += dt
            let f = armory.flyers[i]
            let t = f.age / f.duration
            if t >= 1 {
                f.entity.removeFromParent()
                armory.flyers.remove(at: i)
                continue
            }
            if let center = f.circle {
                // Fly in, circle, fly off.
                let a = f.age * 0.7
                let r = f.start.x + max(0, f.age - (f.duration - 1.5)) * 60
                let p = center + SIMD3(cos(a) * r, f.start.y, sin(a) * r)
                let heading = SIMD3<Float>(-sin(a), 0, cos(a))
                f.entity.position = p
                f.entity.orientation = simd_quatf(angle: atan2(-heading.x, -heading.z), axis: SIMD3(0, 1, 0))
                    * simd_quatf(angle: 0.35, axis: SIMD3(0, 0, 1)) * f.turn
            } else {
                let p = f.start + (f.end - f.start) * t
                let heading = simd_normalize(f.end - f.start)
                f.entity.position = p
                f.entity.orientation = simd_quatf(angle: atan2(-heading.x, -heading.z), axis: SIMD3(0, 1, 0)) * f.turn
            }
        }
    }

    // MARK: Black hole

    private func openBlackHole(_ def: WeaponDef, aim: LaserAim) {
        if armory.hole != nil { return }
        if armory.clock < armory.holeReadyAt {
            show("Black hole recharging: \(Int(ceil(armory.holeReadyAt - armory.clock))) s")
            return
        }
        var at: SIMD3<Float>
        if let hit = raycast(world: world, origin: aim.origin, direction: aim.direction, maxDistance: 70) {
            at = SIMD3<Float>(hit.previous) + 0.5
        } else {
            at = aim.origin + aim.direction * 30
        }
        // Never closer than 12 m.
        if simd_distance(at, player.position) < 12 { at = aim.origin + aim.direction * 12 }
        effects.fireBolt(from: aim.muzzle, to: at, color: SIMD3(0.7, 0.4, 1), speed: 90) { [weak self] in
            self?.startHole(at: at, def: def)
        }
        Sound.shared.play("blackhole-open", volume: 0.5, pitch: 1.6)
        armory.holeReadyAt = armory.clock + 999   // until it closes
    }

    private func startHole(at center: SIMD3<Float>, def: WeaponDef) {
        let r = def.radius
        var cells: [SIMD3<Int>] = []
        let reach = Int(ceil(r))
        let c = SIMD3<Int>(Int(floor(center.x)), Int(floor(center.y)), Int(floor(center.z)))
        for dy in -reach...reach {
            for dz in -reach...reach {
                for dx in -reach...reach {
                    let cell = c &+ SIMD3(dx, dy, dz)
                    guard cell.y > 0, simd_distance(SIMD3<Float>(cell) + 0.5, center) <= r, world.block(cell) != B.air else { continue }
                    cells.append(cell)
                }
            }
        }
        // Torn loose from the inside out.
        cells.sort { simd_distance_squared(SIMD3<Float>($0) + 0.5, center) < simd_distance_squared(SIMD3<Float>($1) + 0.5, center) }
        let visual = BlackHoleVisual(at: center)
        armory.root.addChild(visual.root)
        armory.hole = Armory.Hole(visual: visual, center: center, cells: cells, duration: def.duration, radius: r)
        Sound.shared.play("blackhole-open", volume: 0.8)
        Sound.shared.startLoop("blackhole-loop", channel: "engine", volume: 0.5)
        armory.holeRecharge = def.recharge
    }

    private func updateHole(dt: Float) {
        guard var hole = armory.hole else { return }
        hole.age += dt
        if !hole.visual.update(dt: dt) {
            hole.visual.root.removeFromParent()
            armory.hole = nil
            return
        }
        if !hole.closed {
            // Eat the world, a little at a time.
            let share = min(1, hole.age / (hole.duration * 0.85))
            let goal = Int(Float(hole.cells.count) * share)
            var shown = 0
            while hole.next < goal {
                let cell = hole.cells[hole.next]
                hole.next += 1
                let id = world.block(cell)
                guard id != B.air else { continue }
                world.set(cell, B.air)
                hole.eaten += 1
                if shown < 5 {
                    shown += 1
                    effects.suck(from: SIMD3<Float>(cell) + 0.5, to: hole.center, color: BlockRegistry.shared.rgb(id))
                }
            }
            // Critters fall in (grumpy ones go home; friendly ones run for it).
            hole.critterTimer -= dt
            if hole.critterTimer <= 0 {
                hole.critterTimer = 0.5
                hole.eaten += critters.blast(at: hole.center, radius: 20).count
                blastCats(at: hole.center, radius: 20)
            }
            // You only feel a gentle tug.
            let toward = hole.center - player.position
            let d = simd_length(toward)
            if driving == nil && d < 20 && d > 8 {
                player.velocity += simd_normalize(toward) * dt * 6
            }
            if hole.age >= hole.duration {
                hole.closed = true
                hole.visual.close()
                Sound.shared.stopLoop(channel: "engine")
                Sound.shared.play("blackhole-close", volume: 0.9)
                shareBlast(at: hole.center, radius: hole.radius)
                show("The black hole ate \(hole.eaten) things!")
                Voices.shared.say("laugh", cooldown: 0)
                armory.holeReadyAt = armory.clock + armory.holeRecharge
                armory.holeWaiting = true
            }
        }
        armory.hole = hole
    }
}
