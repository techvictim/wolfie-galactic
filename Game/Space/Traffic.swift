import Foundation
import RealityKit
import simd

/// Ships coming and going: each one follows a loop of waypoints (fly in, come down on a pad,
/// wait, lift off, fly away), turning to face the way it's going. Just for show.
@MainActor
final class ShipTraffic {
    let root = Entity()

    struct Waypoint {
        let at: SIMD3<Float>
        /// Seconds to get here from the one before.
        let time: Float
        /// Stay put here this long (sitting on a pad).
        var wait: Float = 0
    }

    private struct Ship {
        let entity: Entity
        var vehicle: Vehicle
        let path: [Waypoint]
        let period: Float
        var clock: Float
        var lastPosition: SIMD3<Float>
    }

    private var ships: [Ship] = []

    func clear() {
        for child in Array(root.children) { child.removeFromParent() }
        ships.removeAll()
    }

    func add(_ kind: VehicleKind, path: [Waypoint], start: Float = 0, scale: Float = 1) {
        guard path.count >= 2, let model = DetailModels.entity(named: kind.modelName) else { return }
        let holder = Entity()
        model.scale *= scale
        holder.addChild(model)
        root.addChild(holder)
        let period = path.reduce(0) { $0 + $1.time + $1.wait }
        let v = Vehicle(kind: kind, position: path[0].at, yaw: 0)
        var ship = Ship(entity: holder, vehicle: v, path: path, period: period, clock: start.truncatingRemainder(dividingBy: period), lastPosition: path[0].at)
        place(&ship, dt: 0)
        ships.append(ship)
    }

    func update(dt: Float) {
        for i in ships.indices { place(&ships[i], dt: dt) }
    }

    private func place(_ ship: inout Ship, dt: Float) {
        ship.clock = (ship.clock + dt).truncatingRemainder(dividingBy: ship.period)
        var t = ship.clock
        var position = ship.path[0].at
        var parked = false
        var wrapped = false
        let n = ship.path.count
        for k in 0..<n {
            let from = ship.path[k == 0 ? n - 1 : k - 1].at
            let wp = ship.path[k]
            if t < wp.time {
                // Ease in and out between waypoints.
                let u = t / max(wp.time, 0.001)
                let e = u * u * (3 - 2 * u)
                position = from + (wp.at - from) * e
                wrapped = k == 0
                break
            }
            t -= wp.time
            if t < wp.wait {
                position = wp.at
                parked = true
                break
            }
            t -= wp.wait
        }
        // The jump from the last waypoint back to the first happens out of sight.
        ship.entity.isEnabled = !wrapped
        let move = position - ship.lastPosition
        ship.lastPosition = position
        ship.vehicle.position = position
        let flat = SIMD2(move.x, move.z)
        if !parked, simd_length(flat) > 0.0005 {
            let want = atan2(-move.x, -move.z)
            var diff = (want - ship.vehicle.yaw).remainder(dividingBy: 2 * .pi)
            if diff > .pi { diff -= 2 * .pi }
            ship.vehicle.yaw += diff * min(1, dt * 3)
            let pitch = atan2(move.y, simd_length(flat))
            ship.vehicle.pitch += (max(-0.5, min(0.5, pitch)) - ship.vehicle.pitch) * min(1, dt * 3)
        } else {
            ship.vehicle.pitch *= max(0, 1 - dt * 3)
        }
        ship.entity.position = position
        ship.entity.orientation = ship.vehicle.orientation
    }
}
