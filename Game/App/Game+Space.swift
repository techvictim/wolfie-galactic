import Foundation
import RealityKit
import simd

/// Space: fly a ship up out of the sky, look back at the planet, visit the spaceport and swap
/// ships, jump through hyperspace to another planet, and fly down through its atmosphere.
extension Game {
    enum Place { case surface, space }

    /// Above this height the sky starts turning into space.
    static let skyFadeStart: Float = 100
    /// Fly a ship this high and you leave the atmosphere.
    static let spaceHeight: Float = Vehicle.shipCeiling - 2
    /// How far from the planet's centre you can fly before turning back.
    private static let spaceLimit: Float = 1400

    // MARK: Leaving

    /// While flying on a planet: the sky darkens as you climb, then you're in space.
    func checkAltitude(_ v: Vehicle) {
        let darkness = min(max((v.position.y - Game.skyFadeStart) / (Game.spaceHeight - Game.skyFadeStart), 0), 1)
        applySky(darkness: darkness)
        guard v.position.y >= Game.spaceHeight, !spaceTransition else { return }
        enterSpace(from: v)
    }

    private func enterSpace(from v: Vehicle) {
        spaceTransition = true
        // The ship leaves the planet with you.
        vehicles[v.kind] = nil
        shareVehicle(v, on: planet.id, driver: myID, gone: true)
        rememberSpots()
        // While you're away, your saved spot is by the landing pad.
        player = Player(position: world.arrivalPoint())
        save()

        place = .space
        space.setPlanet(planet.id)
        space.showDocks(docks)
        setSurfaceVisible(false)

        // Come out above the planet, climbing away from it.
        let r = space.planetRadius
        var ship = Vehicle(kind: v.kind, position: SIMD3<Float>(0, r + 30, r * 0.35), yaw: v.yaw)
        ship.pitch = 0.45
        ship.speed = v.kind.topSpeed
        spaceShip = ship
        chaseEye = nil
        Sound.shared.play("launch", volume: 0.6)
        show("You're in space! Look back at \(planet.name)")
        Speaker.shared.say("Space!")
        spaceTransition = false
    }

    /// Show or hide everything that belongs on the ground.
    func setSurfaceVisible(_ visible: Bool) {
        renderer.root.isEnabled = visible
        critters.root.isEnabled = visible
        avatars.root.isEnabled = visible
        if !visible {
            hideLaser()
            highlight.isEnabled = false
        }
        space.root.isEnabled = !visible
        space.far.isEnabled = !visible
        showVehicles()
        applySky(darkness: visible ? 0 : 1)
    }

    // MARK: Flying in space

    func updateSpace(_ frame: InputFrame, dt: Float) {
        guard var v = spaceShip else { return }
        let settings = GameSettings.shared

        if hyperspaceTime >= 0 {
            updateHyperspace(dt: dt, ship: &v)
            spaceShip = v
            space.showShip(v)
            _ = moveShipCamera(v, dt: dt)
            space.far.position = camera.position
            return
        }

        // Y: swap ships at the spaceport, or a reminder that there's no air out here.
        let dock = nearbyDock(v)
        if dockPrompt != dock.map({ docks[$0] ?? .starship }) {
            dockPrompt = dock.map { docks[$0] ?? .starship }
        }
        if frame.openMap {
            if let dock, let other = docks[dock] {
                swapShip(&v, dock: dock, for: other)
            } else {
                show("No getting out in space: there's no air!")
            }
        }
        if frame.action {
            spaceShip = v
            openStarMap()
            return
        }

        let lookY = frame.look.y * (settings.invertLook ? -1 : 1)
        let turn = frame.look.x * settings.lookMultiplier - frame.move.x * 1.4 * dt
        v.flySpace(dt: dt, turn: turn, tip: lookY * settings.lookMultiplier, throttle: frame.move.y, up: frame.jump, down: frame.descend)

        // Not too far: space is big, but the planets are this way.
        let distance = simd_length(v.position)
        if distance > Game.spaceLimit {
            v.position = v.position / distance * Game.spaceLimit
            if messageTimer <= 0 { show("Too far! Turn back toward the planets") }
        }

        let thrust = min(1, abs(v.speed) / (v.kind.topSpeed * 2))
        Sound.shared.startLoop("ship-engine", channel: "engine", volume: 0.15, pitch: 0.8)
        Sound.shared.setLoop(channel: "engine", volume: 0.14 + thrust * 0.3, pitch: 0.7 + thrust * 0.7)

        spaceShip = v
        space.showShip(v)
        let aim = moveShipCamera(v, dt: dt)
        space.far.position = camera.position
        fireBolts(firing: frame.breakHeld, dt: dt, vehicle: v, aim: aim)

        // Fly into the planet to land on it.
        if distance < space.planetRadius + 6 && !spaceTransition {
            enterAtmosphere(v)
        }
    }

    // MARK: The spaceport

    private func nearbyDock(_ v: Vehicle) -> Int? {
        guard space.planetID == PlanetCatalog.shared.homeID else { return nil }
        var best: (Int, Float)?
        for i in 0..<SpaceScene.padCount where docks[i] != nil {
            let d = simd_distance(v.position, SpaceScene.padPosition(i))
            if d < 26 && (best == nil || d < best!.1) { best = (i, d) }
        }
        return best?.0
    }

    /// Leave your ship on the pad and take the one that was there.
    private func swapShip(_ v: inout Vehicle, dock: Int, for kind: VehicleKind) {
        var newDocks = docks
        newDocks[dock] = v.kind
        docks = newDocks
        let angle = Float(dock) * 2 * .pi / 3
        var ship = Vehicle(kind: kind, position: SpaceScene.padPosition(dock) + SIMD3<Float>(0, 2, 0), yaw: atan2(-cos(angle), -sin(angle)))
        ship.pitch = 0.1
        v = ship
        space.showDocks(docks)
        chaseEye = nil
        Sound.shared.play("vehicle-in", volume: 0.8)
        show("You're flying the \(kind.name)!")
        Speaker.shared.say(kind.name)
    }

    /// Which ship waits on each spaceport pad. Remembered between games.
    var docks: [VehicleKind?] {
        get {
            let saved = UserDefaults.standard.stringArray(forKey: "spaceportDocks") ?? ["comet", "hauler", "zoomer"]
            return (0..<SpaceScene.padCount).map { i in i < saved.count ? VehicleKind(rawValue: saved[i]) : nil }
        }
        set {
            UserDefaults.standard.set(newValue.map { $0?.rawValue ?? "" }, forKey: "spaceportDocks")
        }
    }

    // MARK: Hyperspace

    /// Chosen on the star map while in space.
    func startHyperspace(to destination: Planet) {
        guard place == .space, hyperspaceTime < 0 else { return }
        if destination.id == space.planetID {
            show("You're already at \(destination.name). Fly down into it to land")
            return
        }
        hyperspaceTarget = destination
        hyperspaceTime = 0
        space.warp.isEnabled = true
        Sound.shared.play("hyperspace", volume: 0.9)
        Speaker.shared.say("Hyperspace to \(destination.name)")
    }

    private func updateHyperspace(dt: Float, ship v: inout Vehicle) {
        hyperspaceTime += dt
        let t = hyperspaceTime
        // Speed up, rush through, slow down.
        let strength = min(1, t / 0.6) * min(1, max(0, (3.2 - t) / 0.6))
        space.updateWarp(dt: dt, strength: max(0.05, strength))
        v.position += v.heading * 40 * strength * dt
        warpGlow = strength

        if t > 1.6, let target = hyperspaceTarget, space.planetID != target.id {
            // Arrive in front of the new planet, pointing at it.
            space.setPlanet(target.id)
            space.showDocks(docks)
            let r = space.planetRadius
            v = Vehicle(kind: v.kind, position: SIMD3<Float>(0, r * 0.4, r * 3.2), yaw: 0)
            v.pitch = -0.1
            v.speed = v.kind.topSpeed
            chaseEye = nil
        }
        if t > 3.2 {
            hyperspaceTime = -1
            warpGlow = 0
            space.warp.isEnabled = false
            if let target = hyperspaceTarget {
                show("Welcome to \(target.name)! Fly down into it to land")
            }
            hyperspaceTarget = nil
        }
    }

    // MARK: Landing

    /// Down through the clouds, glowing hot, and out over the landing pad.
    private func enterAtmosphere(_ v: Vehicle) {
        guard let destination = PlanetCatalog.shared.planet(id: space.planetID) else { return }
        spaceTransition = true
        entryGlow = true
        Sound.shared.play("entry", volume: 0.9)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            guard let self else { return }
            // In a friend's game, the host sends the planet; it's quick on home Wi-Fi.
            let next = destination.id == self.planet.id ? nil : await self.fetchWorld(for: destination)
            self.arrive(on: destination, in: v.kind, world: next)
            try? await Task.sleep(nanoseconds: 500_000_000)
            self.entryGlow = false
            self.spaceTransition = false
        }
    }

    private func arrive(on destination: Planet, in kind: VehicleKind, world next: World? = nil) {
        let newPlanet = destination.id != planet.id
        place = .surface
        spaceShip = nil
        if newPlanet {
            // Load the planet (this also puts its own starship on its pad).
            land(on: destination, world: next)
        }
        setSurfaceVisible(true)

        // Come in high over the landing pad, heading toward it.
        let pad = world.padCenter
        var ship = Vehicle(kind: kind, position: SIMD3<Float>(Float(pad.x), Game.skyFadeStart + 30, Float(pad.y) + 70), yaw: 0)
        ship.pitch = -0.25
        ship.speed = kind.topSpeed * 0.6
        ship.onGround = false
        if kind == .starship, vehicles[.starship] != nil, vehicles[.starship]!.position.y < ship.position.y - 20 {
            // The planet's own starship was waiting on the pad: yours takes its place.
            vehicles[.starship] = nil
        }
        vehicles[kind] = ship
        driving = kind
        chaseEye = nil
        player.position = ship.position
        showVehicles()
        applySky(darkness: min(1, max(0, (ship.position.y - Game.skyFadeStart) / (Game.spaceHeight - Game.skyFadeStart))))
        if session != .joined { WorldStore.lastPlanet = destination.id }
        shareVehicle(ship, on: destination.id, driver: myID)
        show("Welcome to \(destination.name)!")
    }

    /// Back to the ground without the show, e.g. when going to the title screen from space.
    func leaveSpaceQuietly() {
        guard place == .space else { return }
        let kind = spaceShip?.kind ?? .starship
        hyperspaceTime = -1
        space.warp.isEnabled = false
        warpGlow = 0
        if let destination = PlanetCatalog.shared.planet(id: space.planetID) {
            arrive(on: destination, in: kind)
        }
        // Parked on the pad.
        if var ship = vehicles[kind] {
            let pad = world.padCenter
            ship.position = SIMD3<Float>(Float(pad.x) + 0.5, 0, Float(pad.y) + 0.5)
            settle(&ship)
            vehicles[kind] = ship
        }
        driving = nil
        player = Player(position: world.arrivalPoint())
        Sound.shared.stopLoop(channel: "engine")
        showVehicles()
        rememberSpots()
    }
}
