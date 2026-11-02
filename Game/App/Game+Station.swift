import Foundation
import RealityKit
import simd

/// Wolfie Station: fly into it from space, land in the hangar, swap ships, fly back out.
extension Game {
    /// Where the station sits in space around Wolfie World, and how close counts as flying in.
    static var stationCenter: SIMD3<Float> { SpaceScene.spaceportPosition + SIMD3(0, 18, 0) }
    static let stationEntryDistance: Float = 28

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

    /// Ships in space looping in and out of the station.
    func setupSpaceTraffic() {
        spaceTraffic.clear()
        let c = Game.stationCenter
        typealias W = ShipTraffic.Waypoint
        for (i, kind) in [VehicleKind.hauler, .comet, .zoomer].enumerated() {
            let a = Float(i) * 2.1 + 0.4
            let out = c + SIMD3(cos(a) * 500, 60 + Float(i) * 40, sin(a) * 500)
            let back = c + SIMD3(cos(a + 1.2) * 520, -40 + Float(i) * 30, sin(a + 1.2) * 520)
            spaceTraffic.add(kind, path: [
                W(at: out, time: 0),
                W(at: c + SIMD3(cos(a) * 30, 10, sin(a) * 30), time: 16, wait: 4),
                W(at: back, time: 16),
            ], start: Float(i) * 12)
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

    /// In space near Wolfie World: fly into the station to land in it.
    func checkStationEntry(_ v: Vehicle) -> Bool {
        guard space.planetID == PlanetCatalog.shared.homeID, let station = stationPlanet, !spaceTransition else { return false }
        let d = simd_distance(v.position, Game.stationCenter)
        if d < 140 && !stationHinted {
            stationHinted = true
            show("Fly into Wolfie Station to land in its hangar")
        }
        if d > 220 { stationHinted = false }
        guard d < Game.stationEntryDistance else { return false }
        enteringStation = true
        enterAtmosphere(v, to: station)
        return true
    }
}
