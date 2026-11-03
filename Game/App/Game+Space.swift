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
        if planet.isStation {
            // Already in space: fly out of the station and you're on your way.
            if leftStation(v), !spaceTransition { enterSpace(from: v) }
            return
        }
        let darkness = min(max((v.position.y - Game.skyFadeStart) / (Game.spaceHeight - Game.skyFadeStart), 0), 1)
        applySky(darkness: darkness)
        guard v.position.y >= Game.spaceHeight, !spaceTransition else { return }
        enterSpace(from: v)
    }

    private func enterSpace(from v: Vehicle) {
        spaceTransition = true
        // The ship leaves the planet with you.
        vehicles[v.id] = nil
        shareVehicle(v, on: planet.id, driver: myID, gone: true)
        rememberSpots()
        // While you're away, your saved spot is by the landing pad.
        player = Player(position: world.arrivalPoint())
        save()

        place = .space
        // The station orbits Wolfie World: leaving it puts you in space beside it.
        let fromStation = planet.isStation
        space.setPlanet(fromStation ? PlanetCatalog.shared.homeID : planet.id)
        setSurfaceVisible(false)
        spaceTraffic.root.isEnabled = space.planetID == PlanetCatalog.shared.homeID

        var ship: Vehicle
        if fromStation {
            // Out through the hangar door, heading away from the station.
            let d = SpaceScene.hangarDirection
            ship = Vehicle(kind: v.kind, position: SpaceScene.hangarMouth + d * 25, yaw: atan2(-d.x, -d.z), id: v.id)
            ship.pitch = 0
            ship.speed = v.kind.topSpeed * 0.5
        } else {
            // Come out above the planet, climbing away from it.
            let r = space.planetRadius
            // Still heading the same way: whatever you flew toward in the sky is out there ahead.
            ship = Vehicle(kind: v.kind, position: SIMD3<Float>(0, r + 30, r * 0.35), yaw: v.yaw, id: v.id)
            ship.pitch = min(max(v.pitch, 0.15), 1.0)
            ship.speed = v.kind.topSpeed
        }
        spaceShip = ship
        chaseEye = nil
        stationHinted = fromStation
        Sound.shared.play("launch", volume: 0.6)
        if fromStation {
            show("Back in space! Wolfie World is below you")
        } else {
            show("You're in space! Look back at \(planet.name)")
            Speaker.shared.say("Space!")
        }
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
        traffic.root.isEnabled = visible
        // Clouds belong in a planet's air, not out in space.
        clouds.isEnabled = visible
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

        // A reminder that there's no air out here. (Other ships wait inside Wolfie Station.)
        if dockPrompt != nil { dockPrompt = nil }
        if frame.openMap || frame.usePressed {
            show("No getting out in space: there's no air! Land in Wolfie Station to swap ships")
        }
        // Pointing at another planet: □ jumps straight there. Otherwise □ opens the star map.
        let target = targetedPlanet(v)
        if hyperTarget != target?.id { hyperTarget = target?.id }
        if frame.action && entryTime < 0 {
            if let target {
                startHyperspace(to: target)
            } else {
                spaceShip = v
                openStarMap()
            }
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

        spaceTraffic.root.isEnabled = space.planetID == PlanetCatalog.shared.homeID
        spaceTraffic.update(dt: dt)
        space.updateStationLights(dt: dt)
        _ = checkStationEntry(&v)

        let thrust = min(1, abs(v.speed) / (v.kind.topSpeed * 2))
        Sound.shared.startLoop("ship-engine", channel: "engine", volume: 0.15, pitch: 0.8)
        Sound.shared.setLoop(channel: "engine", volume: 0.14 + thrust * 0.3, pitch: 0.7 + thrust * 0.7)

        spaceShip = v
        space.showShip(v)
        let aim = moveShipCamera(v, dt: dt)
        space.far.position = camera.position
        fireBolts(firing: frame.breakHeld, dt: dt, vehicle: v, aim: aim)

        // Fly into the planet's air to come down through it. The ship never touches the
        // planet model itself; the clouds take over first.
        if distance < space.atmosphereRadius && !spaceTransition,
           let destination = PlanetCatalog.shared.planet(id: space.planetID) {
            enterAtmosphere(v, to: destination)
        }
        if entryTime >= 0 && !enteringStation {
            let floor = space.planetRadius * 1.08
            if distance < floor, distance > 0.01 { v.position = v.position / distance * floor }
            spaceShip = v
            space.showShip(v)
            armory.shake = max(armory.shake, 0.25 * entryVeil + 0.1)
            shakeCamera()
        }
    }

    // MARK: The spaceport

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
                let r = space.planetRadius
            v = Vehicle(kind: v.kind, position: SIMD3<Float>(0, r * 0.4, r * 3.2), yaw: 0, id: v.id)
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

    /// The planet you're pointing at, for a quick hyperspace jump.
    private func targetedPlanet(_ v: Vehicle) -> Planet? {
        let forward = simd_normalize(v.heading)
        var best: (Planet, Float)?
        for p in PlanetCatalog.shared.planets where p.id != space.planetID {
            guard let d = SpaceScene.direction(of: p.id) else { continue }
            let dot = simd_dot(forward, d)
            if dot > 0.96, dot > (best?.1 ?? 0) { best = (p, dot) }
        }
        return best?.0
    }

    /// Down through the atmosphere: the ship glows hot and shakes, clouds rush in until they fill
    /// the view, then clear to show the planet's sky, still dark up high, brightening as you dive.
    func enterAtmosphere(_ v: Vehicle, to destination: Planet) {
        spaceTransition = true
        entryTime = 0
        hyperTarget = nil
        if enteringStation {
            // Into the hangar: no fire and clouds, just a quick fade.
            Sound.shared.play("vehicle-in", volume: 0.7)
        } else {
            entryGlow = true
            Sound.shared.play("entry", volume: 0.9)
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            // In a friend's game, the host sends the planet; it's quick on home Wi-Fi.
            let next = destination.id == self.planet.id ? nil : await self.fetchWorld(for: destination)
            // Wait until the clouds cover everything.
            while self.entryVeil < 0.99 && self.entryTime >= 0 {
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
            let ship = self.spaceShip ?? v
            self.arrive(on: destination, in: ship, world: next)
            self.entryTime = -2
        }
    }

    /// The clouds of an atmosphere entry, every frame.
    func updateEntry(dt: Float) {
        if entryTime >= 0 {
            entryTime += dt
            let veil = enteringStation ? min(1, entryTime / 0.45) : min(1, max(0, (entryTime - 0.6) / 1.1))
            if abs(veil - entryVeil) > 0.01 { entryVeil = veil }
        } else if entryTime <= -2 {
            let veil = max(0, entryVeil - dt / (fadeEntry ? 0.6 : 1.8))
            entryVeil = veil
            if veil < 0.6 && entryGlow { entryGlow = false }
            if veil <= 0 {
                entryTime = -1
                spaceTransition = false
                fadeEntry = false
            }
        }
    }

    private func arrive(on destination: Planet, in arriving: Vehicle, world next: World? = nil) {
        let kind = arriving.kind
        let newPlanet = destination.id != planet.id
        place = .surface
        spaceShip = nil
        hyperTarget = nil
        enteringStation = false
        if newPlanet {
            // Load the planet (this also puts its own starship on its pad).
            land(on: destination, world: next)
        }
        setSurfaceVisible(true)

        // Come out of the clouds high up, where the sky is still dark, diving toward the pad.
        let pad = world.padCenter
        var ship = Vehicle(kind: kind, position: SIMD3<Float>(Float(pad.x), Game.spaceHeight - 10, Float(pad.y) + 150), yaw: 0, id: arriving.id)
        ship.pitch = -0.38
        ship.speed = kind.topSpeed * 0.8
        if destination.isStation {
            // Just inside the hangar's open end, hovering, ready to land.
            ship.position = SIMD3<Float>(0, Float(StationPlan.deck) + 7, Float(StationPlan.hangarHalfDepth) - 3)
            ship.pitch = 0
            ship.speed = 0
        }
        ship.onGround = false
        // If the planet's own starship was waiting on the pad, yours (with the same id) takes its place.
        vehicles[ship.id] = ship
        driving = ship.id
        chaseEye = nil
        player.position = ship.position
        showVehicles()
        applySky(darkness: min(1, max(0, (ship.position.y - Game.skyFadeStart) / (Game.spaceHeight - Game.skyFadeStart))))
        if session != .joined { WorldStore.lastPlanet = destination.id }
        shareVehicle(ship, on: destination.id, driver: myID)
        show(destination.isStation ? "Welcome to Wolfie Station! Land in the hangar, or take another ship" : "Welcome to \(destination.name)!")
    }

    /// Back to the ground without the show, e.g. when going to the title screen from space.
    func leaveSpaceQuietly() {
        guard place == .space else { return }
        let arriving = spaceShip ?? Vehicle(kind: .starship, position: .zero, yaw: 0)
        hyperspaceTime = -1
        space.warp.isEnabled = false
        warpGlow = 0
        if let destination = PlanetCatalog.shared.planet(id: space.planetID) {
            arrive(on: destination, in: arriving)
        }
        // Parked on the pad.
        if var ship = vehicles[arriving.id] {
            let pad = world.padCenter
            ship.position = SIMD3<Float>(Float(pad.x) + 0.5, 0, Float(pad.y) + 0.5)
            settle(&ship)
            vehicles[arriving.id] = ship
        }
        driving = nil
        player = Player(position: world.arrivalPoint())
        Sound.shared.stopLoop(channel: "engine")
        showVehicles()
        rememberSpots()
    }
}
