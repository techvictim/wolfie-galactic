import Foundation
import RealityKit
import simd

/// Drones you fly yourself, from weapons.json type "drone":
///  - the Bomber Drone ("bomber"): fly it around and drop bombs with R2; ○ flies you back
///  - the Boom Drone ("kamikaze"): it zooms where you point it and blows up on contact
/// While one is up, your character waits where they are and the controls fly the drone.
@MainActor
final class PilotDrone {
    let def: WeaponDef
    let entity: Entity
    let light: ModelEntity?
    var position: SIMD3<Float>
    var yaw: Float
    var pitch: Float
    var battery: Float
    var bombs: Int
    var bombCooldown: Float = 0
    var lastTrigger = true
    var tilt = SIMD2<Float>(repeating: 0)
    var clock: Float = 0
    var dropping: [(entity: Entity, position: SIMD3<Float>, velocity: SIMD3<Float>)] = []

    var kamikaze: Bool { def.style == "kamikaze" }

    init(def: WeaponDef, at position: SIMD3<Float>, yaw: Float, pitch: Float) {
        self.def = def
        let model = Shots.model("drone", size: def.style == "kamikaze" ? 2.6 : 3.2)
        entity = model.entity
        light = model.light
        if def.style == "kamikaze" {
            // A red warhead on the nose, and hazard stripes.
            entity.addChild(Shots.box(SIMD3(0.14, 0.1, 0.16), SIMD3(0, -0.02, -0.3), SIMD3(0.9, 0.15, 0.12)))
            entity.addChild(Shots.box(SIMD3(0.42, 0.04, 0.42), SIMD3(0, 0.08, 0), SIMD3(1, 0.78, 0.1)))
        } else {
            // A bomb hanging underneath.
            entity.addChild(Shots.box(SIMD3(0.1, 0.1, 0.22), SIMD3(0, -0.13, 0), SIMD3(0.3, 0.33, 0.28)))
        }
        self.position = position
        self.yaw = yaw
        self.pitch = pitch
        battery = def.duration > 0 ? def.duration : 45
        bombs = max(1, def.count)
    }

    var look: SIMD3<Float> {
        SIMD3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
    }
    var orientation: simd_quatf {
        simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0))
    }
}

extension Game {
    // MARK: Taking off

    func launchDrone(_ def: WeaponDef, aim: LaserAim) {
        guard pilotDrone == nil else { return }
        let start = aim.muzzle + aim.direction * 1.5 + SIMD3(0, 0.8, 0)
        let drone = PilotDrone(def: def, at: start, yaw: player.yaw, pitch: def.style == "kamikaze" ? max(-0.6, min(0.3, player.pitch)) : 0)
        drone.entity.position = start
        armory.root.addChild(drone.entity)
        pilotDrone = drone
        holsterWeapon()
        Sound.shared.play("vehicle-in", volume: 0.5, pitch: 1.4)
        Sound.shared.startLoop("ship-engine", channel: "drone", volume: 0.05, pitch: drone.kamikaze ? 2.2 : 1.8)
        if drone.kamikaze {
            show("Boom Drone! Steer it into something. ○ to blow it up now")
            droneStatus = "Boom Drone · steer with the right stick · ○ boom"
        } else {
            show("Bomber Drone! Left stick and jump/○ to fly, R2 drops a bomb, ○ flies you back")
            droneStatus = "Bomber Drone · R2 bomb · ○ back"
        }
    }

    // MARK: Flying

    /// While a drone is up, this runs instead of walking, and the camera rides along with it.
    func updateDrone(_ frame: InputFrame, dt: Float) {
        guard let drone = pilotDrone else { return }
        drone.clock += dt
        drone.battery -= dt
        let settings = GameSettings.shared
        let lookY = frame.look.y * (settings.invertLook ? -1 : 1)
        drone.yaw += frame.look.x * settings.lookMultiplier
        drone.pitch = min(max(drone.pitch + lookY * settings.lookMultiplier, -1.3), 1.0)

        var velocity: SIMD3<Float>
        if drone.kamikaze {
            // Always zooming forward, faster and faster; the right stick steers.
            let speed = min(34, 16 + drone.clock * 6)
            velocity = drone.look * speed
            if frame.dismount || drone.battery <= 0 {
                detonateDrone(at: drone.position)
                return
            }
        } else {
            // Like flying in creative: the left stick moves, jump goes up, descend goes down.
            let forward = SIMD3<Float>(-sin(drone.yaw), 0, -cos(drone.yaw))
            let right = SIMD3<Float>(cos(drone.yaw), 0, -sin(drone.yaw))
            let speed: Float = sprinting ? 22 : 14
            velocity = (forward * frame.move.y + right * frame.move.x) * speed
            if frame.jump { velocity.y += 9 }
            if frame.descend { velocity.y -= 9 }
            drone.tilt += (frame.move - drone.tilt) * min(1, dt * 6)
            if frame.dismount || drone.battery <= 0 {
                if drone.battery <= 0 { show("Bomber Drone battery's empty. Back to you!") }
                endDrone()
                return
            }
            // R2: drop a bomb.
            drone.bombCooldown -= dt
            let pressed = frame.breakHeld && !drone.lastTrigger
            drone.lastTrigger = frame.breakHeld
            if pressed {
                if drone.bombs > 0 && drone.bombCooldown <= 0 {
                    drone.bombs -= 1
                    drone.bombCooldown = 0.4
                    let bomb = Shots.model("bomb", size: 0.6).entity
                    bomb.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
                    bomb.position = drone.position - SIMD3(0, 0.6, 0)
                    armory.root.addChild(bomb)
                    drone.dropping.append((bomb, bomb.position, velocity * 0.8))
                    Sound.shared.play("throw", volume: 0.4, pitch: 0.8)
                    droneStatus = "Bomber Drone · \(drone.bombs) bomb\(drone.bombs == 1 ? "" : "s") left · ○ back"
                } else if drone.bombs == 0 {
                    show("Out of bombs! ○ to fly back")
                }
            }
        }

        // Move, without going through blocks (a Boom Drone blows up instead).
        let next = drone.position + velocity * dt
        let solid = world.isSolidForPhysics(Int(floor(next.x)), Int(floor(next.y)), Int(floor(next.z)))
        if drone.kamikaze {
            let ahead = next + drone.look * 0.6
            let blocked = solid || world.isSolidForPhysics(Int(floor(ahead.x)), Int(floor(ahead.y)), Int(floor(ahead.z)))
            let cat = roboCats.target(origin: drone.position, direction: drone.look, maxDistance: 2)
            if blocked || cat != nil || critters.nearestDistance(to: next) < 1.3 || next.y < 1 {
                detonateDrone(at: next)
                return
            }
            drone.position = next
        } else if !solid && next.y < Float(World.height) + 30 {
            drone.position = next
        } else {
            // Try sliding along: up/down and across separately.
            var p = drone.position
            for axis in 0..<3 {
                var q = p
                q[axis] += velocity[axis] * dt
                if !world.isSolidForPhysics(Int(floor(q.x)), Int(floor(q.y)), Int(floor(q.z))) { p = q }
            }
            drone.position = p
        }
        // Too far from you: the signal fades and it comes back.
        if !drone.kamikaze && simd_distance(drone.position, player.position) > 160 {
            show("Too far! The drone flew back to you")
            endDrone()
            return
        }

        // Its look: tipped into the way it's going, little bob, blinking light.
        let bob = sin(drone.clock * 3) * 0.05
        drone.entity.position = drone.position + SIMD3(0, bob, 0)
        let tip = simd_quatf(angle: -drone.tilt.y * 0.3, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: -drone.tilt.x * 0.3, axis: SIMD3(0, 0, 1))
        drone.entity.orientation = simd_quatf(angle: drone.yaw, axis: SIMD3(0, 1, 0))
            * (drone.kamikaze ? simd_quatf(angle: drone.pitch, axis: SIMD3(1, 0, 0)) : tip)
        drone.light?.isEnabled = Int(drone.clock * 4) % 2 == 0
        let busy = drone.kamikaze ? 1 : min(1, simd_length(velocity) / 14)
        Sound.shared.setLoop(channel: "drone", volume: 0.04 + busy * 0.05, pitch: (drone.kamikaze ? 2 : 1.6) + busy * 0.5)
        if drone.kamikaze {
            droneStatus = "Boom Drone · \(max(0, Int(drone.battery.rounded(.up))))s · ○ boom"
        }

        updateDroneBombs(drone, dt: dt)
        droneCamera(drone)
    }

    private func updateDroneBombs(_ drone: PilotDrone, dt: Float) {
        for i in drone.dropping.indices.reversed() {
            var bomb = drone.dropping[i]
            bomb.velocity.y -= 20 * dt
            bomb.velocity.x *= max(0, 1 - dt * 0.5)
            bomb.velocity.z *= max(0, 1 - dt * 0.5)
            bomb.position += bomb.velocity * dt
            bomb.entity.position = bomb.position
            let p = bomb.position
            let hitCat = roboCats.target(origin: p, direction: SIMD3(0, -1, 0), maxDistance: 1.2) != nil
            if hitCat || p.y < 1 || world.isSolidForPhysics(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z))) {
                bomb.entity.removeFromParent()
                drone.dropping.remove(at: i)
                _ = explode(at: p + SIMD3(0, 0.5, 0), radius: drone.def.radius)
                continue
            }
            drone.dropping[i] = bomb
        }
    }

    /// Behind and above the Bomber Drone; right on the nose of the Boom Drone.
    private func droneCamera(_ drone: PilotDrone) {
        camera.orientation = drone.orientation
        let eye: SIMD3<Float>
        if drone.kamikaze {
            eye = drone.position + drone.look * 0.4 + SIMD3(0, 0.15, 0)
        } else {
            let behind = drone.look * -5 + SIMD3(0, 1.6, 0)
            var reach: Float = 1
            var t: Float = 0.1
            while t <= 1 {
                let p = drone.position + behind * t
                if world.isSolidForPhysics(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z))) {
                    reach = max(0.05, t - 0.1)
                    break
                }
                t += 0.1
            }
            eye = drone.position + behind * reach
        }
        camera.position = eye
        aimOrigin = eye
        followCamera(eye)
    }

    // MARK: Landing and blowing up

    private func detonateDrone(at p: SIMD3<Float>) {
        guard let drone = pilotDrone else { return }
        _ = explode(at: p, radius: drone.def.radius)
        endDrone(quiet: true)
    }

    /// Back to your own eyes. Bombs still falling still go off.
    func endDrone(quiet: Bool = false) {
        guard let drone = pilotDrone else { return }
        pilotDrone = nil
        droneStatus = nil
        drone.entity.removeFromParent()
        for bomb in drone.dropping {
            bomb.entity.removeFromParent()
            _ = explode(at: bomb.position, radius: drone.def.radius)
        }
        Sound.shared.stopLoop(channel: "drone")
        if !quiet { Sound.shared.play("vehicle-out", volume: 0.5, pitch: 1.4) }
        armory.lastTrigger = true
        armory.cooldown = drone.def.cooldown
        syncCamera()
    }
}
