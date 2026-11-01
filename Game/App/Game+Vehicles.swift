import Foundation
import RealityKit
import simd

/// Where the laser comes from and where it points.
struct LaserAim {
    let origin: SIMD3<Float>
    let direction: SIMD3<Float>
    /// Where the beam starts on screen: your blaster, or the vehicle's.
    let muzzle: SIMD3<Float>
}

/// Getting in, driving the rover, flying the starship, and getting out again.
extension Game {
    // MARK: Parking

    /// Put this planet's vehicles where they were left, or where they start out.
    func placeVehicles() {
        driving = nil
        Sound.shared.stopLoop(channel: "engine")
        vehicles.removeAll()

        func add(_ kind: VehicleKind, at base: SIMD2<Int>, dx: Int = 0, dz: Int = 0, yaw: Float) {
            guard vehicles[kind.rawValue] == nil else { return }
            var v = Vehicle(kind: kind, position: SIMD3<Float>(Float(base.x + dx) + 0.5, 0, Float(base.y + dz) + 0.5), yaw: yaw)
            settle(&v)
            vehicles[v.id] = v
        }
        add(.starship, at: world.padCenter, yaw: .pi)
        if planet.id == PlanetCatalog.shared.homeID {
            let spawn = world.spawnPoint()
            add(.rover, at: SIMD2(Int(floor(spawn.x)), Int(floor(spawn.z))), dx: 5, dz: -3, yaw: -.pi / 2)
        }
        // Vehicles this planet starts with (planets.json "vehicles").
        for spot in planet.vehicles ?? [] {
            guard let kind = VehicleKind(rawValue: spot.kind) else { continue }
            let base: SIMD2<Int>
            switch spot.near {
            case "settlement": base = TerrainGenerator.firstSettlement
            case "start": base = TerrainGenerator.spawn
            default: base = world.padCenter
            }
            add(kind, at: base, dx: spot.dx, dz: spot.dz, yaw: spot.yaw ?? 0)
        }

        // Where you've parked them, and any you've placed or flown here.
        if session != .joined, let spots = UserDefaults.standard.dictionary(forKey: spotKey) as? [String: [Double]] {
            for (id, spot) in spots {
                guard let kind = Vehicle.kind(ofID: id), spot.count == 4 else { continue }
                var v = Vehicle(kind: kind, position: SIMD3<Float>(Float(spot[0]), Float(spot[1]), Float(spot[2])), yaw: Float(spot[3]), id: id)
                settle(&v)
                vehicles[id] = v
            }
        }
        showVehicles()
        // In a game with friends: where they've left (or are driving) each vehicle.
        applyVehicleNotes()
    }

    /// Parked vehicles sit on the ground.
    func settle(_ vehicle: inout Vehicle) {
        vehicle.position.y = Float(world.surfaceY(x: Int(floor(vehicle.position.x)), z: Int(floor(vehicle.position.z))))
        vehicle.pitch = 0
        vehicle.roll = 0
        vehicle.speed = 0
        vehicle.climb = 0
    }

    var spotKey: String { "vehicles-\(planet.id)" }

    /// Remember where you parked, per planet. Not in a friend's world.
    func rememberSpots() {
        guard session != .joined else { return }
        // A planet's own starship always comes back to its pad, so nobody gets stranded.
        var spots: [String: [Double]] = [:]
        for (id, v) in vehicles {
            spots[id] = [Double(v.position.x), Double(v.position.y), Double(v.position.z), Double(v.yaw)]
        }
        UserDefaults.standard.set(spots, forKey: spotKey)
    }

    func forgetSpots() {
        UserDefaults.standard.removeObject(forKey: spotKey)
    }

    /// Move the models to where the vehicles are.
    func showVehicles() {
        for (id, model) in vehicleModels where vehicles[id] == nil {
            model.removeFromParent()
            vehicleModels[id] = nil
        }
        for (id, v) in vehicles {
            if vehicleModels[id] == nil, let model = DetailModels.entity(named: v.kind.modelName) {
                root.addChild(model)
                vehicleModels[id] = model
            }
            guard let model = vehicleModels[id] else { continue }
            // In space, the ship you fly is drawn by the space scene.
            model.isEnabled = place == .surface
            model.position = v.position
            model.orientation = v.orientation
        }
    }

    // MARK: On foot

    /// The vehicle you could get into right now, if any.
    func vehicleInReach() -> String? {
        var best: (String, Float)?
        for (id, v) in vehicles {
            let d = simd_distance(SIMD2<Float>(player.position.x, player.position.z), SIMD2<Float>(v.position.x, v.position.z))
            let dy = abs(player.position.y - v.position.y)
            if d < v.kind.boardingDistance && dy < 4 && (best == nil || d < best!.1) {
                best = (id, d)
            }
        }
        return best?.0
    }

    func board(_ id: String) {
        guard let v = vehicles[id] else { return }
        let kind = v.kind
        driving = id
        hideLaser()
        highlight.isEnabled = false
        player.flying = false
        flying = false
        chaseYaw = 0
        chasePitch = kind.isShip ? -0.18 : -0.22
        chaseEye = nil
        player.position = v.position
        shareVehicle(v, on: planet.id, driver: myID)
        Sound.shared.play("vehicle-in", volume: 0.8)
        Sound.shared.startLoop(kind.engineSound, channel: "engine", volume: 0.15, pitch: 0.8)
        if kind.isShip && kind != .starship { show("Flying the \(kind.name)") }
    }

    func getOut() {
        guard let id = driving, var v = vehicles[id] else { return }
        let kind = v.kind
        driving = nil
        applySky(darkness: 0)
        hideLaser()
        Sound.shared.stopLoop(channel: "engine")
        Sound.shared.play("vehicle-out", volume: 0.8)

        // Step out on the left side, facing the same way.
        let side: Float = kind.isShip ? -(kind.gunSpread + 3.5) : -2.6
        var spot = v.point(SIMD3<Float>(side, 0, 0))
        let ground = Float(world.surfaceY(x: Int(floor(spot.x)), z: Int(floor(spot.z))))
        let high = v.position.y - ground > 3
        spot.y = high ? v.position.y : ground
        player = Player(position: spot)
        player.yaw = v.yaw
        player.pitch = -0.15
        // Out of a starship up in the sky: you keep flying instead of falling.
        player.flying = high
        flying = high

        if kind.isShip && !v.onGround {
            // An empty starship gently lands where it is.
            settle(&v)
        }
        v.speed = 0
        v.climb = 0
        vehicles[id] = v
        showVehicles()
        rememberSpots()
        shareVehicle(v, on: planet.id, driver: nil)
        syncCamera()
    }

    // MARK: Driving and flying

    func updateDriving(_ frame: InputFrame, dt: Float) {
        guard let id = driving, var v = vehicles[id] else { return }
        let kind = v.kind

        if frame.openMap {
            getOut()
            return
        }
        // Keeps the engine running, including after a pause.
        Sound.shared.startLoop(kind.engineSound, channel: "engine", volume: 0.15, pitch: 0.8)

        let settings = GameSettings.shared
        let lookY = frame.look.y * (settings.invertLook ? -1 : 1)

        switch kind {
        case .rover, .buggy, .hoverbike:
            // Right stick (or mouse) swings the camera around; it drifts back behind you when let go.
            chaseYaw += frame.look.x * settings.lookMultiplier
            chasePitch = min(max(chasePitch + lookY * settings.lookMultiplier, -1.0), 0.45)
            if frame.look.x == 0 && simd_length(frame.move) > 0.2 {
                chaseYaw -= chaseYaw * min(1, dt * 1.5)
            }
            let bumped = v.drive(dt: dt, throttle: frame.move.y, steer: frame.move.x, hop: frame.jumpPressed, world: world, gravity: planet.gravity)
            if bumped { Sound.shared.play("bump", volume: 0.7) }
            if frame.action { Sound.shared.play("horn", volume: 0.9) }
            if frame.jumpPressed && v.climb > 0 { Sound.shared.playVaried("jump", volume: 0.5) }
            let revs = abs(v.speed) / kind.topSpeed
            Sound.shared.setLoop(channel: "engine", volume: 0.12 + revs * 0.25, pitch: 0.75 + revs * 0.9)
        case .starship, .comet, .hauler, .zoomer:
            // Steer with the look stick (or mouse) like looking around; the move stick (or W/S)
            // sets the speed, and sideways on it turns too.
            let turn = frame.look.x * settings.lookMultiplier - frame.move.x * 1.4 * dt
            v.fly(dt: dt, turn: turn, tip: lookY * settings.lookMultiplier, throttle: frame.move.y,
                  up: frame.jump, down: frame.descend, world: world)
            let thrust = min(1, abs(v.speed) / kind.topSpeed + abs(v.climb) / kind.climbRate * 0.5)
            Sound.shared.setLoop(channel: "engine", volume: 0.14 + thrust * 0.3, pitch: 0.7 + thrust * 0.7)
            if frame.action {
                vehicles[id] = v
                rememberSpots()
                openStarMap()
                return
            }
        }
        vehicles[id] = v
        showVehicles()

        // You ride along: critters, friends and the land around you follow the vehicle.
        player.position = v.position
        player.yaw = v.yaw

        let aim = kind.isShip ? moveShipCamera(v, dt: dt) : moveChaseCamera(v, dt: dt)
        fireBolts(firing: frame.breakHeld, dt: dt, vehicle: v, aim: aim)
        if kind.isShip { checkAltitude(v) }
    }

    /// Vehicles shoot glowing bolts that fly to whatever is under the crosshair.
    func fireBolts(firing: Bool, dt: Float, vehicle v: Vehicle, aim: LaserAim) {
        boltCooldown -= dt
        guard firing, boltCooldown <= 0 else { return }
        boltCooldown = v.kind.isShip ? 0.13 : 0.2
        let range: Float = 70
        let critter = place == .surface ? aimCritter(from: aim) : nil
        var end = aim.origin + aim.direction * range
        var block: SIMD3<Int>?
        if let critter {
            end = critter.point
        } else if place == .surface, let hit = raycast(world: world, origin: aim.origin, direction: aim.direction, maxDistance: range) {
            block = hit.block
            end = SIMD3<Float>(Float(hit.block.x) + 0.5, Float(hit.block.y) + 0.5, Float(hit.block.z) + 0.5)
        }
        // The starship has two blasters and takes turns with them.
        var muzzle = v.kind.muzzle
        if v.kind.isShip {
            boltSide = -boltSide
            muzzle.x = v.kind.gunSpread * boltSide
            muzzle.y -= v.kind == .starship ? 0.5 : 0
        }
        Sound.shared.playVaried("bolt", volume: 0.5, spread: 0.1)
        effects.fireBolt(from: v.point(muzzle), to: end, color: Game.laserColor) { [weak self] in
            guard let self else { return }
            if let critter {
                self.zapCritter(critter)
            } else if let block, block.y > 0, self.world.block(block) != B.air {
                self.blastBlock(block)
            } else {
                self.effects.spark(at: end)
            }
        }
    }

    /// Break a block with a fiery burst.
    func blastBlock(_ block: SIMD3<Int>, loud: Bool = true) {
        let id = world.block(block)
        guard id != B.air else { return }
        changeBlock(block, B.air)
        let center = SIMD3<Float>(Float(block.x) + 0.5, Float(block.y) + 0.5, Float(block.z) + 0.5)
        dropPickup(id, at: center)
        effects.blockBurst(at: center, blockColor: BlockRegistry.shared.rgb(id))
        let distance = simd_distance(center, camera.position)
        Sound.shared.playVaried("explode", volume: (loud ? 0.7 : 0.35) * max(0.25, min(1, 14 / max(distance, 1))), spread: 0.12)
    }

    /// Starship camera: right behind the ship, looking where its nose points.
    func moveShipCamera(_ v: Vehicle, dt: Float) -> LaserAim {
        let kind = v.kind
        let nose = v.heading
        let base = v.position + SIMD3<Float>(0, kind.lookHeight, 0)
        var eye = base - nose * kind.cameraDistance + SIMD3<Float>(0, kind.cameraHeight * 0.45, 0)
        if place == .surface {
            let ground = Float(world.surfaceY(x: Int(floor(eye.x)), z: Int(floor(eye.z))))
            if eye.y < ground + 1 { eye.y = ground + 1 }
        }
        let smoothed = chaseEye.map { $0 + (eye - $0) * min(1, dt * 10) } ?? eye
        chaseEye = smoothed

        let lookAt = base + nose * 40
        let direction = simd_normalize(lookAt - smoothed)
        camera.position = smoothed
        let turn = simd_quatf(angle: atan2(-direction.x, -direction.z), axis: SIMD3<Float>(0, 1, 0))
        let tip = simd_quatf(angle: asin(max(-1, min(1, direction.y))), axis: SIMD3<Float>(1, 0, 0))
        camera.orientation = turn * tip
        followCamera(smoothed)
        let start = smoothed + direction * simd_distance(smoothed, base)
        return LaserAim(origin: start, direction: direction, muzzle: v.point(kind.muzzle))
    }

    /// Rover camera: follows behind and above, and the right stick swings it around.
    private func moveChaseCamera(_ v: Vehicle, dt: Float) -> LaserAim {
        let kind = v.kind
        let yaw = v.yaw + chaseYaw
        let pitch = chasePitch
        let look = SIMD3<Float>(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
        let target = v.position + SIMD3<Float>(0, kind.lookHeight, 0)
        var eye = target - look * kind.cameraDistance + SIMD3<Float>(0, kind.cameraHeight - kind.lookHeight, 0) * 0.5

        // Don't go inside hills: lift the camera above the ground under it.
        let ground = Float(world.surfaceY(x: Int(floor(eye.x)), z: Int(floor(eye.z))))
        if eye.y < ground + 1 { eye.y = ground + 1 }

        // Glide rather than snap, so bumps don't shake the picture.
        let smoothed = chaseEye.map { $0 + (eye - $0) * min(1, dt * 8) } ?? eye
        chaseEye = smoothed

        let direction = simd_normalize(target + SIMD3<Float>(0, 0.6, 0) - smoothed)
        let cameraYaw = atan2(-direction.x, -direction.z)
        let cameraPitch = asin(max(-1, min(1, direction.y)))
        camera.position = smoothed
        camera.orientation = simd_quatf(angle: cameraYaw, axis: SIMD3<Float>(0, 1, 0)) * simd_quatf(angle: cameraPitch, axis: SIMD3<Float>(1, 0, 0))
        followCamera(smoothed)

        // Aim from just past the vehicle, along the camera's view.
        let start = smoothed + direction * simd_distance(smoothed, target)
        return LaserAim(origin: start, direction: direction, muzzle: v.point(kind.muzzle))
    }
}
