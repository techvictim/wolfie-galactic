import Foundation
import simd

/// The critter you're looking at.
struct AimedCritter {
    let id: Int
    let kind: CritterKind
    let distance: Float
    let point: SIMD3<Float>
    let isFriend: Bool
}

/// Critters, hearts and the Danger setting.
extension Game {
    static let maxHearts = 5

    var showHearts: Bool { GameSettings.shared.danger > 0 }

    private var danger: Int { min(max(GameSettings.shared.danger, 0), 2) }

    /// Grumpy critters around at once: none, a couple, or a handful.
    private var grumpyLimit: Int { [0, 2, 5][danger] }

    /// Laser zaps it takes to send a Grumbler home.
    private var zapsToPoof: Int { [1, 3, 5][danger] }

    // MARK: Looking at critters

    /// The critter in front of you, if it's nearer than the nearest block.
    func aimCritter(from aim: LaserAim) -> AimedCritter? {
        let reach = heldWeapon.map { min($0.range, 80) } ?? ((laserSelected || driving != nil) ? Player.laserRange : Player.reach)
        let direction = aim.direction
        guard let hit = critters.target(origin: aim.origin, direction: direction, maxDistance: reach) else { return nil }
        if let block = raycast(world: world, origin: aim.origin, direction: direction, maxDistance: reach) {
            let center = SIMD3<Float>(Float(block.block.x) + 0.5, Float(block.block.y) + 0.5, Float(block.block.z) + 0.5)
            if simd_distance(aim.origin, center) - 0.5 < hit.distance { return nil }
        }
        return AimedCritter(id: hit.id, kind: hit.kind, distance: hit.distance, point: hit.point, isFriend: critters.isFriend(hit.id))
    }

    func updatePetPrompt(_ aimed: AimedCritter?) {
        var prompt: String?
        if let aimed, !laserSelected, !aimed.kind.isGrumpy {
            prompt = aimed.isFriend ? "Pet your \(aimed.kind.name)" : "Make friends with the \(aimed.kind.name)"
        }
        if prompt != petPrompt { petPrompt = prompt }
    }

    /// The place button (left trigger, right click) gives a pat.
    func petIfPressed(_ aimed: AimedCritter, pressed: Bool) {
        guard pressed && !lastPlaceHeld else { return }
        let kind = aimed.kind
        let isNew = critters.pet(aimed.id)
        if isNew {
            Sound.shared.play("befriend", volume: 0.8)
            if foundCritters.contains(kind.id) {
                show("The \(kind.name) is following you")
            } else {
                addToBook(kind)
            }
        } else {
            Sound.shared.play(kind.sound, at: aimed.point, listener: player.eye, facing: player.yaw, volume: 1, pitch: 1.1)
            Voices.shared.say("laugh", chance: 0.25, cooldown: 10)
        }
    }

    func zapCritter(_ aimed: AimedCritter) {
        guard let result = critters.zap(aimed.id, from: player.eye, hitsToPoof: zapsToPoof) else { return }
        switch result {
        case .startled(let kind):
            Sound.shared.play("startle", volume: 0.6)
            if !aimed.isFriend { show("The \(kind.name) got a fright! Lasers are for blocks.") }
        case .zapped:
            Sound.shared.play("zap-critter", volume: 0.7)
        case .poofed(let kind, _):
            Sound.shared.play("poof", volume: 0.8)
            if !foundCritters.contains(kind.id) {
                addToBook(kind)
            } else {
                show("Poof! The \(kind.name) went home")
            }
            // Sending one home gives you a heart back.
            if showHearts && hearts < Game.maxHearts {
                hearts += 1
                Sound.shared.play("heart", volume: 0.6)
            }
        }
    }

    private func addToBook(_ kind: CritterKind) {
        foundCritters.insert(kind.id)
        UserDefaults.standard.set(Array(foundCritters).sorted(), forKey: "critterBook")
        let verb = kind.isGrumpy ? "You sent a" : "New friend: a"
        show("\(verb) \(kind.name)! It's in your Critter Book")
        Speaker.shared.say("\(kind.name)!")
    }

    // MARK: Every frame

    func updateCritters(dt: Float, fallSpeed: Float, wasOnGround: Bool) {
        critterClock += dt
        let events = critters.update(dt: dt, player: player, world: world, gravity: planet.gravity, grumpyLimit: grumpyLimit, clock: critterClock)
        for event in events {
            switch event {
            case let .bump(from):
                getBumped(from: from)
            case let .sound(name, point, pitch):
                Sound.shared.play(name, at: point, listener: player.eye, facing: player.yaw, volume: 0.8, pitch: pitch)
            }
        }

        guard showHearts else {
            if hearts != Game.maxHearts { hearts = Game.maxHearts }
            return
        }

        // Tough: big falls hurt.
        if danger >= 2 && !wasOnGround && player.onGround && fallSpeed < -19 && critterClock - jumpPadClock > 4 {
            hurt(fallSpeed < -27 ? 2 : 1)
        }

        // Hearts come back after a while without getting hurt.
        safeTime += dt
        if hearts < Game.maxHearts && safeTime > (danger >= 2 ? 8 : 4) {
            regenTimer += dt
            if regenTimer > (danger >= 2 ? 14 : 6) {
                regenTimer = 0
                hearts += 1
                Sound.shared.play("heart", volume: 0.4)
            }
        } else {
            regenTimer = 0
        }
    }

    private func getBumped(from point: SIMD3<Float>) {
        // Safe inside a vehicle.
        guard safeTime > 0.9, driving == nil else { return }
        var away = player.position - point
        away.y = 0
        let length = simd_length(away)
        away = length > 0.01 ? away / length : SIMD3<Float>(0, 0, 1)
        player.knock(away * 9 + SIMD3<Float>(0, 5, 0))
        hurt(1)
    }

    private func hurt(_ amount: Int) {
        guard showHearts, travelText == nil else { return }
        safeTime = 0
        regenTimer = 0
        hearts = max(0, hearts - amount)
        Sound.shared.play("hurt", volume: 0.8)
        Voices.shared.say("hurt", chance: 0.6, cooldown: 7, volume: 0.5)
        hurtFlash = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            self?.hurtFlash = false
        }
        if hearts == 0 { knockedOut() }
    }

    /// Out of hearts: a silly "bonk", then you wake up by the starship with full hearts.
    private func knockedOut() {
        Sound.shared.play("knocked-out", volume: 0.8)
        travelText = "Bonk! Back to the starship…"
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard let self else { return }
            self.player = Player(position: self.world.arrivalPoint())
            self.critters.clearGrumpy(near: self.player.position, radius: 30)
            self.hearts = Game.maxHearts
            self.safeTime = 0
            self.travelText = nil
        }
    }

    func dangerChanged() {
        if GameSettings.shared.danger == 0 { critters.removeGrumpy() }
        hearts = Game.maxHearts
    }
}
