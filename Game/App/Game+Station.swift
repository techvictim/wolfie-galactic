import Foundation
import RealityKit
import simd

/// Wolfie Station: fly into it from space, land in the hangar, swap ships, fly back out.
extension Game {
    /// Where the station sits in space around Wolfie World.
    static var stationCenter: SIMD3<Float> { SpaceScene.stationCenter }

    var stationPlanet: Planet? {
        PlanetCatalog.shared.stationID.flatMap { PlanetCatalog.shared.planet(id: $0) }
    }

    // MARK: Ships parked and visiting

    /// The ships parked in the hangar, ready to fly.
    func placeStationVehicles(_ add: (VehicleKind, SIMD2<Int>, Float, String) -> Void) {
        for (name, x, z, yaw) in StationPlan.parking {
            guard let kind = VehicleKind(rawValue: name) else { continue }
            add(kind, SIMD2(x, z), yaw, "\(name)-station")
        }
    }

    /// Ships coming and going: landing on the outside pads, and flying through the hangar.
    func setupStationTraffic() {
        traffic.clear()
        guard planet.isStation else { return }
        let deck = Float(StationPlan.deck)
        typealias W = ShipTraffic.Waypoint
        let kinds: [VehicleKind] = [.hauler, .comet, .zoomer, .starship]
        for (i, pad) in StationPlan.trafficPads.enumerated() {
            let p = SIMD3<Float>(Float(pad.x) + 0.5, deck, Float(pad.y) + 0.5)
            let side: Float = pad.x > 0 ? 1 : -1
            let far = SIMD3<Float>(side * 320, deck + 50, -260 + Float(i) * 120)
            let away = SIMD3<Float>(side * 260, deck + 70, 300)
            traffic.add(kinds[i], path: [
                W(at: far, time: 0),
                W(at: p + SIMD3(side * 30, 22, 0), time: 11),
                W(at: p + SIMD3(0, 14, 0), time: 3),
                W(at: p, time: 3.5, wait: 9),
                W(at: p + SIMD3(0, 16, 0), time: 3),
                W(at: away, time: 11),
            ], start: Float(i) * 17)
        }
        // Straight through the hangar, end to end, high above the parked ships.
        let y = deck + 14
        traffic.add(kinds[2], path: [
            W(at: SIMD3(0, y + 30, 360), time: 0),
            W(at: SIMD3(0, y, 60), time: 10),
            W(at: SIMD3(0, y, -60), time: 6),
            W(at: SIMD3(0, y + 40, -360), time: 10),
        ], start: 5)
        // One circling the station, waiting its turn.
        var circle: [W] = []
        for k in 0...12 {
            let a = Float(k) / 12 * 2 * .pi
            circle.append(W(at: SIMD3(cos(a) * 150, deck + 30 + sin(a * 2) * 6, sin(a) * 150), time: k == 0 ? 0 : 3))
        }
        traffic.add(kinds[3], path: circle)
    }

    /// Ships in space flying in and out of the station's hangar door.
    func setupSpaceTraffic() {
        spaceTraffic.clear()
        let mouth = SpaceScene.hangarMouth, d = SpaceScene.hangarDirection, side = SpaceScene.hangarSide
        typealias W = ShipTraffic.Waypoint
        for (i, kind) in [VehicleKind.hauler, .comet, .zoomer].enumerated() {
            let lane = side * (Float(i) - 1) * 5
            let far = mouth + d * 420 + side * (Float(i) - 1) * 260 + SIMD3(0, Float(i) * 60 - 50, 0)
            let away = mouth + d * 420 - side * (Float(i) - 1) * 300 + SIMD3(0, 70 - Float(i) * 50, 0)
            spaceTraffic.add(kind, path: [
                W(at: far, time: 0),
                W(at: mouth + d * 60 + lane, time: 14),
                W(at: mouth - d * 14 + lane, time: 5, wait: 5),
                W(at: mouth + d * 60 + lane, time: 5),
                W(at: away, time: 14),
            ], start: Float(i) * 15)
        }
    }

    // MARK: Every frame on the station

    func updateStation(dt: Float) {
        guard planet.isStation else { return }
        traffic.update(dt: dt)
        // Fell off the edge (with a jetpack, say)? Back on the deck.
        if driving == nil, player.position.y < 4 {
            player = Player(position: world.arrivalPoint())
            show("Whoa! Back on the deck")
        }
    }

    /// Fly far enough from the station and you're back out in space.
    func leftStation(_ v: Vehicle) -> Bool {
        guard planet.isStation else { return false }
        let out = simd_length(SIMD2(v.position.x, v.position.z))
        return out > 190 || v.position.y > Float(StationPlan.deck) + 75 || v.position.y < 4
    }

    /// In space near Wolfie World: fly in through the hangar door to land inside. The rest of
    /// the station is solid.
    func checkStationEntry(_ v: inout Vehicle) -> Bool {
        guard space.planetID == PlanetCatalog.shared.homeID, let station = stationPlanet, !spaceTransition else { return false }
        let d = simd_distance(v.position, Game.stationCenter)
        if d < 260 && !stationHinted {
            stationHinted = true
            show("Wolfie Station! Fly in through the glowing hangar door, between the lights")
        }
        if d > 400 { stationHinted = false }
        guard d < 140 else { return false }
        let rel = v.position - SpaceScene.hangarMouth
        let along = simd_dot(rel, SpaceScene.hangarDirection)
        let across = abs(simd_dot(rel, SpaceScene.hangarSide))
        let up = abs(rel.y)
        if along < 3 && along > -20 && across < SpaceScene.mouthHalfWidth - 1 && up < SpaceScene.mouthHalfHeight - 1 {
            enteringStation = true
            fadeEntry = true
            v.speed = min(v.speed, v.kind.topSpeed * 0.3)
            enterAtmosphere(v, to: station)
            return true
        }
        bumpStation(&v)
        return false
    }

    /// Keep ships out of the station's ring, hub and hangar walls.
    private func bumpStation(_ v: inout Vehicle) {
        let c = Game.stationCenter
        let margin: Float = 3
        var p = v.position
        var hit = false
        // The big ring (a flat doughnut, 34 out, about 5 thick).
        let rel = p - c
        let flat = SIMD2(rel.x, rel.z)
        let out = simd_length(flat)
        if out > 0.01 {
            let q = out - 34
            let tube = SIMD2(q, rel.y)
            let t = simd_length(tube)
            if t < 4.8 + margin, t > 0.001 {
                let push = tube / t * (4.8 + margin)
                let newOut = 34 + push.x
                let dir = flat / out
                p = c + SIMD3(dir.x * newOut, push.y, dir.y * newOut)
                hit = true
            }
        }
        // The hub in the middle.
        let r2 = p - c
        let hubOut = simd_length(SIMD2(r2.x, r2.z))
        if hubOut < 11 + margin, abs(r2.y) < 14 + margin, hubOut > 0.01 {
            let dir = SIMD2(r2.x, r2.z) / hubOut
            p = c + SIMD3(dir.x * (11 + margin), r2.y, dir.y * (11 + margin))
            hit = true
        }
        // The hangar: a long box out from the ring to the door.
        let h = p - c
        let along = simd_dot(h, SpaceScene.hangarDirection)
        let across = simd_dot(h, SpaceScene.hangarSide)
        let up = h.y - 1
        let hw = SpaceScene.mouthHalfWidth + margin, hh = SpaceScene.mouthHalfHeight + margin
        if along > 36 - margin, along < 60, abs(across) < hw, abs(up) < hh {
            // Out the nearest side (the door end is handled by flying in).
            let gaps = [(hw - abs(across), 0), (hh - abs(up), 1), (along - (36 - margin), 2)]
            let nearest = gaps.min { $0.0 < $1.0 }!
            switch nearest.1 {
            case 0: p += SpaceScene.hangarSide * (across >= 0 ? nearest.0 : -nearest.0)
            case 1: p.y += up >= 0 ? nearest.0 : -nearest.0
            default: p -= SpaceScene.hangarDirection * nearest.0
            }
            hit = true
        }
        if hit {
            v.position = p
            if abs(v.speed) > v.kind.topSpeed * 0.2 {
                Sound.shared.play("bump", volume: 0.6)
                armory.shake = max(armory.shake, 0.3)
            }
            v.speed *= 0.4
        }
    }
}
