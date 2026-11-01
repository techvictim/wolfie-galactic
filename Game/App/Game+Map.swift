import CoreGraphics
import Foundation
import simd

/// The map: a picture of the land around you seen from above, with you, your friends, the landing
/// pad, the nearest city or base and parked vehicles. Next to it, everyone and where they are,
/// with Go buttons to zoom to a friend (even on another planet) or a landmark.
extension Game {
    /// Blocks per map pixel, and pixels across.
    static let mapStep = 4
    static let mapPixels = 128

    /// What's drawn on the map, besides the land.
    struct MapMarker: Identifiable, Equatable {
        enum Kind: Equatable { case you, friend(color: Int), pad, settlement, vehicle }
        let id: String
        let kind: Kind
        let label: String
        /// Position on the map, 0...1 across and down.
        let x: Double
        let y: Double
        /// For your arrow: which way you face, in radians clockwise from up (north is -z).
        let heading: Double
    }

    /// The landmarks you can zoom to on this planet.
    enum Landmark: String {
        case pad, settlement
    }

    func openMap() {
        guard screen == .playing || screen == .paused else { return }
        if driving != nil && place == .surface {
            // Fine to look at the map from a vehicle.
        }
        menuReturn = screen == .paused ? .paused : .playing
        screen = .map
        menuIndex = 0
        hideLaser()
        #if os(macOS)
        input.releasePointer()
        #endif
        paintMap()
    }

    func closeMap() {
        screen = menuReturn == .paused ? .paused : .playing
        menuIndex = 0
        #if os(macOS)
        if screen == .playing { input.capturePointer() }
        #endif
    }

    /// Where you are on the ground (or where you'll come back to, in space).
    private var mapCenter: SIMD2<Int> {
        if place == .space { return world.padCenter }
        return SIMD2(Int(floor(player.position.x)), Int(floor(player.position.z)))
    }

    /// Paint the land around you in the background.
    func paintMap() {
        let center = mapCenter
        let generator = world.generator
        let colors = (0..<BlockRegistry.maxBlocks).map { BlockRegistry.shared.rgb(UInt8($0)) }
        let step = Game.mapStep
        let size = Game.mapPixels
        let origin = SIMD2<Int>(center.x - size / 2 * step, center.y - size / 2 * step)
        mapOrigin = origin
        mapPlanet = planet.id
        mapImage = nil
        Task.detached(priority: .userInitiated) {
            let image = MapPainter.paint(generator: generator, origin: origin, step: step, size: size, colors: colors)
            await MainActor.run { [weak self] in
                guard let self, self.mapPlanet == generator.planet.id else { return }
                self.mapImage = image
            }
        }
    }

    /// Everything to draw on top of the land.
    var mapMarkers: [MapMarker] {
        let span = Double(Game.mapStep * Game.mapPixels)
        func spot(_ x: Float, _ z: Float) -> (Double, Double)? {
            let u = (Double(x) - Double(mapOrigin.x)) / span
            let v = (Double(z) - Double(mapOrigin.y)) / span
            guard u >= 0, u <= 1, v >= 0, v <= 1 else { return nil }
            return (u, v)
        }
        var markers: [MapMarker] = []
        let pad = world.padCenter
        if let p = spot(Float(pad.x), Float(pad.y)) {
            markers.append(MapMarker(id: "pad", kind: .pad, label: "Landing pad", x: p.0, y: p.1, heading: 0))
        }
        if let site = nearestSettlement, let p = spot(Float(site.center.x), Float(site.center.y)) {
            markers.append(MapMarker(id: "settlement", kind: .settlement, label: settlementName(site), x: p.0, y: p.1, heading: 0))
        }
        for (kind, v) in vehicles where driving != kind {
            if let p = spot(v.position.x, v.position.z) {
                markers.append(MapMarker(id: "vehicle-\(kind.rawValue)", kind: .vehicle, label: kind.name, x: p.0, y: p.1, heading: 0))
            }
        }
        for friend in friendSpots where friend.planet == planet.id && !friend.inSpace {
            if let p = spot(friend.position.x, friend.position.z) {
                markers.append(MapMarker(id: "friend-\(friend.id)", kind: .friend(color: friend.color), label: friend.name, x: p.0, y: p.1, heading: 0))
            }
        }
        if place == .surface, let p = spot(player.position.x, player.position.z) {
            markers.append(MapMarker(id: "you", kind: .you, label: "You", x: p.0, y: p.1, heading: Double(-player.yaw)))
        }
        return markers
    }

    // MARK: Places

    /// The closest city, base or mine to you on this planet.
    var nearestSettlement: Settlement? {
        let cell = TerrainGenerator.settlementCell
        let c = mapCenter
        let cx = floorDiv(c.x, cell), cz = floorDiv(c.y, cell)
        var best: (Settlement, Float)?
        for dz in -2...2 {
            for dx in -2...2 {
                guard let site = world.generator.settlement(cellX: cx + dx, cellZ: cz + dz) else { continue }
                let d = simd_distance(SIMD2<Float>(Float(site.center.x), Float(site.center.y)), SIMD2<Float>(Float(c.x), Float(c.y)))
                if best == nil || d < best!.1 { best = (site, d) }
            }
        }
        return best?.0
    }

    func settlementName(_ site: Settlement) -> String {
        switch site.kind {
        case .city: return "Wolfie City"
        case .base: return "Moon Base"
        case .mine: return "Crystal Mine"
        }
    }

    /// "120 blocks north-east", from where you are.
    func directions(to point: SIMD2<Float>) -> String {
        let here = SIMD2<Float>(Float(mapCenter.x), Float(mapCenter.y))
        let d = point - here
        let distance = Int(simd_length(d).rounded())
        if distance < 8 { return "right here" }
        // North is -z (the way you face at the start).
        let angle = atan2(d.x, -d.y)
        let names = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
        let index = Int(((angle / (2 * .pi) * 8).rounded() + 8).truncatingRemainder(dividingBy: 8))
        return "\(distance) blocks \(names[max(0, min(7, index))])"
    }

    /// Where a friend is, in words.
    func whereabouts(_ friend: FriendSpot) -> String {
        guard let id = friend.planet, let p = PlanetCatalog.shared.planet(id: id) else { return "On the way…" }
        if friend.inSpace { return "In space near \(p.name)" }
        if id == planet.id && place == .surface {
            return directions(to: SIMD2(friend.position.x, friend.position.z))
        }
        return "On \(p.name)"
    }

    // MARK: Zooming there

    /// Zoom to a friend: next to them on this planet, or off to their planet.
    func fastTravel(to id: Int) {
        guard let friend = friendSpots.first(where: { $0.id == id }),
              let planetID = friend.planet, let destination = PlanetCatalog.shared.planet(id: planetID) else {
            show("Can't find them right now")
            return
        }
        leaveVehicleAndSpace()
        let beside = friend.position + SIMD3<Float>(2.5, 0, 2.5)
        if friend.inSpace {
            // You can't stand in space; meet them at their planet's landing pad.
            zoom(to: destination, at: nil, saying: "\(friend.name) is in space. Zooming to \(destination.name)'s landing pad…")
        } else {
            zoom(to: destination, at: beside, saying: "Zooming to \(friend.name)…")
        }
    }

    func fastTravel(to landmark: Landmark) {
        leaveVehicleAndSpace()
        switch landmark {
        case .pad:
            zoom(to: planet, at: world.arrivalPoint(), saying: "Zooming to the landing pad…")
        case .settlement:
            guard let site = nearestSettlement else { return }
            // Arrive at the edge, looking in.
            let spot = SIMD3<Float>(Float(site.center.x) + 0.5, 0, Float(site.center.y + site.radius + 4) + 0.5)
            zoom(to: planet, at: spot, saying: "Zooming to \(settlementName(site))…")
        }
    }

    private func leaveVehicleAndSpace() {
        screen = .playing
        if place == .space { leaveSpaceQuietly() }
        if driving != nil { getOut() }
    }

    /// The zoom itself: a quick whoosh on the same planet, or the full trip to another one.
    private func zoom(to destination: Planet, at spot: SIMD3<Float>?, saying text: String) {
        Sound.shared.play("hyperspace", volume: 0.6)
        travelText = text
        if destination.id == planet.id {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard let self else { return }
                self.stand(at: spot ?? self.world.arrivalPoint())
                self.waitForGround()
            }
            return
        }
        save()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard let self else { return }
            let next = await self.fetchWorld(for: destination)
            self.land(on: destination, world: next)
            if let spot { self.stand(at: spot) }
            self.waitForGround()
        }
    }

    /// Put you at a spot: on the ground there, or flying if it's high up (a friend in the air).
    private func stand(at spot: SIMD3<Float>) {
        let ground = Float(world.surfaceY(x: Int(floor(spot.x)), z: Int(floor(spot.z))))
        let high = spot.y - ground > 3
        player = Player(position: SIMD3<Float>(spot.x, high ? spot.y : ground, spot.z))
        player.flying = high
        flying = high
        syncCamera()
        lastSentPose = nil
    }
}

/// Paints a top-down picture of the land: each pixel is the top block's colour, lighter on high
/// ground and shaded on slopes facing away from the light, with buildings drawn in.
enum MapPainter {
    static func paint(generator: TerrainGenerator, origin: SIMD2<Int>, step: Int, size: Int, colors: [SIMD3<Float>]) -> CGImage? {
        var heights = [Int](repeating: 0, count: size * size)
        var blocks = [UInt8](repeating: 0, count: size * size)
        for j in 0..<size {
            for i in 0..<size {
                let x = origin.x + i * step + step / 2
                let z = origin.y + j * step + step / 2
                var h = generator.height(x, z)
                var id = generator.surfaceBlock(height: h)
                if let building = generator.farTop(x, z), building.height > h {
                    h = building.height
                    id = building.block
                }
                heights[j * size + i] = h
                blocks[j * size + i] = id
            }
        }
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for j in 0..<size {
            for i in 0..<size {
                let k = j * size + i
                let h = Float(heights[k])
                let left = Float(heights[j * size + max(0, i - 1)])
                let up = Float(heights[max(0, j - 1) * size + i])
                let slope = (h - left) * 0.05 + (h - up) * 0.05
                let light = min(1.25, max(0.55, 0.8 + (h - 20) / 90 + slope))
                let c = colors[Int(blocks[k]) % colors.count] * light
                pixels[k * 4] = UInt8(max(0, min(255, c.x * 255)))
                pixels[k * 4 + 1] = UInt8(max(0, min(255, c.y * 255)))
                pixels[k * 4 + 2] = UInt8(max(0, min(255, c.z * 255)))
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}
