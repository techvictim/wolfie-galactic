import Foundation
import Network
import simd

/// A friend's name, where it goes on screen.
struct NameTag: Identifiable, Equatable {
    let id: Int
    let name: String
    let color: Int
    let x: CGFloat
    let y: CGFloat
}

/// Where a friend is, for the map.
struct FriendSpot: Identifiable, Equatable {
    let id: Int
    let name: String
    let color: Int
    let planet: String?
    let inSpace: Bool
    let position: SIMD3<Float>
    let vehicle: String?
}

/// Playing together on the same Wi-Fi.
///
/// The host keeps the real copy of every planet anyone is on. Everyone else goes wherever they
/// like: when a friend heads to a planet, they ask the host for it, and every block change is
/// sent with the planet it happened on. Vehicles exist once per planet, so when someone drives
/// off in the rover, it's gone from its parking spot for everyone.
extension Game {
    private var myCard: PlayerCard {
        let settings = GameSettings.shared
        return PlayerCard(id: myID, name: settings.playerNameText, color: settings.playerColor, crew: settings.crew)
    }

    /// Your character says hi to a friend, once the name has been read out.
    func sayHiSoon() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            Voices.shared.say("hi", cooldown: 10)
        }
    }

    /// Where you are: the planet you're on, or the one you're orbiting in space.
    var hereID: String { place == .space ? space.planetID : planet.id }

    private var myPose: Pose {
        let ship = place == .space ? spaceShip : nil
        let p = ship?.position ?? player.position
        return Pose(
            x: p.x, y: p.y, z: p.z,
            yaw: ship?.yaw ?? player.yaw, pitch: player.pitch, flying: player.flying,
            laser: laserEnd.map { [$0.x, $0.y, $0.z] },
            vehicle: (ship?.kind ?? drivingKind)?.rawValue,
            space: place == .space ? true : nil,
            planet: hereID
        )
    }

    /// One line for the HUD about who's here.
    var togetherSummary: String? {
        switch session {
        case .solo:
            return nil
        case .hosting:
            if players.isEmpty { return "Hosting · waiting for friends" }
            return "Hosting · " + players.map(\.name).joined(separator: ", ")
        case .joined:
            let others = players.filter { $0.id != Net.hostID }.map(\.name)
            return others.isEmpty ? "In \(hostName)'s game" : "In \(hostName)'s game · " + others.joined(separator: ", ")
        }
    }

    /// Everyone else and where they are.
    var friendSpots: [FriendSpot] {
        players.compactMap { card in
            let pose = avatars.pose(of: card.id)
            return FriendSpot(
                id: card.id, name: card.name, color: card.color,
                planet: pose?.planet, inSpace: pose?.space ?? false,
                position: pose?.position ?? .zero, vehicle: pose?.vehicle
            )
        }
    }

    // MARK: Every frame

    func updateTogether(dt: Float) {
        guard session != .solo else {
            if !nameTags.isEmpty { nameTags = [] }
            return
        }
        // Only friends on the same planet as you (and not off in space) appear in the world.
        avatars.visiblePlanet = place == .surface ? planet.id : nil
        avatars.update(dt: dt, clock: Float(Date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)))

        // Send where we are about 15 times a second, but only if something changed.
        poseTimer -= dt
        if poseTimer <= 0 && travelText == nil {
            poseTimer = Net.poseInterval
            let pose = myPose
            if pose != lastSentPose {
                lastSentPose = pose
                send(.pose(id: myID, pose: pose))
            }
        }

        let tags = (screen == .playing && travelText == nil && place == .surface) ? currentNameTags() : []
        if tags != nameTags { nameTags = tags }
    }

    /// Project each friend's head onto the screen.
    private func currentNameTags() -> [NameTag] {
        guard viewSize.width > 0, viewSize.height > 0 else { return [] }
        let inverse = camera.orientation.inverse
        let eye = camera.position
        let tanHalf = tan(Float(camera.camera.fieldOfViewInDegrees) * .pi / 360)
        let aspect = Float(viewSize.width / viewSize.height)
        var tags: [NameTag] = []
        for (card, point) in avatars.tagPoints() {
            let local = inverse.act(point - eye)
            let depth = -local.z
            guard depth > 0.3, depth < 90 else { continue }
            let nx = local.x / (depth * tanHalf * aspect)
            let ny = local.y / (depth * tanHalf)
            guard abs(nx) < 1.1, abs(ny) < 1.1 else { continue }
            // Whole points, so the tags don't shimmer while standing still.
            let x = CGFloat(((nx + 1) / 2 * Float(viewSize.width)).rounded())
            let y = CGFloat(((1 - ny) / 2 * Float(viewSize.height)).rounded())
            tags.append(NameTag(id: card.id, name: card.name, color: card.color, x: x, y: y))
        }
        return tags
    }

    // MARK: Changing blocks and vehicles

    /// Change a block here and tell everyone else.
    func changeBlock(_ p: SIMD3<Int>, _ id: UInt8) {
        world.set(p, id)
        send(.block(planet: planet.id, x: p.x, y: p.y, z: p.z, id: id))
    }

    /// Tell everyone about a blast, so their worlds lose the same blocks.
    func shareBlast(at p: SIMD3<Float>, radius: Float) {
        send(.blast(planet: planet.id, x: p.x, y: p.y, z: p.z, radius: radius))
    }

    /// Tell everyone a nest was cured or caught the Glitch again.
    func shareNest(_ id: String, cured: Bool) {
        send(.nest(planet: planet.id, id: id, cured: cured))
    }

    /// A friend's blast: show it if it's here, and take the blocks away.
    private func friendBlast(planet planetID: String, at p: SIMD3<Float>, radius: Float) {
        if planetID == planet.id {
            if place == .surface {
                explode(at: p, radius: radius, nuke: radius >= 12, fromFriend: true)
            } else {
                Game.carve(world, at: p, radius: radius)
            }
        } else if session == .hosting, let other = hostWorld(planetID) {
            Game.carve(other, at: p, radius: radius)
        }
    }

    /// Tell everyone a vehicle moved, was taken, parked, or flew off.
    func shareVehicle(_ v: Vehicle, on planetID: String, driver: Int?, gone: Bool = false) {
        guard session != .solo else { return }
        let note = VehicleNote(planet: planetID, id: v.id, kind: v.kind.rawValue, x: v.position.x, y: v.position.y, z: v.position.z,
                               yaw: v.yaw, driver: driver, gone: gone)
        remember(note)
        send(.vehicle(note))
    }

    private func remember(_ note: VehicleNote) {
        vehicleNotes[note.planet, default: [:]][note.id] = note
    }

    /// Put this planet's vehicles where everyone else has left them.
    func applyVehicleNotes() {
        guard session != .solo, let notes = vehicleNotes[planet.id] else { return }
        for note in notes.values { apply(note) }
    }

    private func apply(_ note: VehicleNote) {
        guard note.planet == planet.id, place == .surface, let kind = VehicleKind(rawValue: note.kind) else { return }
        if driving == note.id && note.driver != myID { return }   // you're in it here; yours wins
        if note.gone || (note.driver != nil && note.driver != myID) {
            // Driven by a friend (they show it) or flown away: not parked here.
            vehicles[note.id] = nil
        } else {
            var v = vehicles[note.id] ?? Vehicle(kind: kind, position: .zero, yaw: 0, id: note.id)
            v.position = SIMD3<Float>(note.x, note.y, note.z)
            v.yaw = note.yaw
            v.speed = 0
            vehicles[note.id] = v
        }
        showVehicles()
    }

    /// The host tells friends; a friend tells the host, who passes it on.
    private func send(_ message: NetMessage) {
        switch session {
        case .solo: break
        case .hosting: host?.broadcast(message)
        case .joined: link?.send(message)
        }
    }

    // MARK: Getting a planet

    /// A planet's world: from the host when playing in a friend's game, otherwise saved or new.
    func fetchWorld(for destination: Planet) async -> World {
        guard session == .joined, let link else {
            if let w = otherWorlds.removeValue(forKey: destination.id) { return w }
            return Game.makeWorld(for: destination).world
        }
        link.send(.askPlanet(planet: destination.id))
        let started = Date()
        while Date().timeIntervalSince(started) < 10 {
            if let edits = arrivedPlanets.removeValue(forKey: destination.id) {
                return World(planet: destination, edits: edits)
            }
            if session != .joined { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return World(planet: destination)
    }

    /// The host's copy of a planet nobody (or only friends) are standing on right now.
    private func hostWorld(_ id: String) -> World? {
        if id == planet.id { return world }
        if let w = otherWorlds[id] { return w }
        guard let p = PlanetCatalog.shared.planet(id: id) else { return nil }
        let w = Game.makeWorld(for: p).world
        otherWorlds[id] = w
        return w
    }

    /// The host saves friends' building on other planets too.
    func saveOtherWorlds() {
        guard session == .hosting else { return }
        for (id, w) in otherWorlds {
            let existing = WorldStore.load(planet: id)
            let spawn = w.spawnPoint()
            guard let edits = try? w.compressedEdits() else { continue }
            let file = SaveFile(
                version: SaveFile.currentVersion, planet: id, seed: w.seed, height: World.height, edits: edits,
                player: existing?.player ?? [spawn.x, spawn.y, spawn.z, 0, -0.2, 0],
                hotbarIndex: existing?.hotbarIndex ?? 0
            )
            try? WorldStore.save(file, planet: id)
        }
    }

    // MARK: Looking for games

    func startLooking() {
        browser.onChange = { [weak self] games in
            self?.foundGames = games
        }
        browser.start()
    }

    func stopLooking() {
        browser.stop()
        foundGames = []
    }

    // MARK: Hosting

    func hostGame() {
        stopLooking()
        let name = GameSettings.shared.playerNameText
        let host = NetHost()
        host.onMessage = { [weak self] id, message in self?.hostReceived(message, from: id) }
        host.onDisconnect = { [weak self] id in self?.friendLeft(id) }
        host.onFailed = { [weak self] in
            self?.endSession()
            self?.show("Hosting stopped. Is Wi-Fi on?")
        }
        do {
            try host.start(name: "\(name)'s game")
        } catch {
            show("Couldn't host: \(error.localizedDescription)")
            return
        }
        self.host = host
        myID = Net.hostID
        hostName = name
        session = .hosting
        players = []
        vehicleNotes = [:]
        avatars.removeAll()
        lastSentPose = nil
        activate(.play)
        show("Friends on this Wi-Fi can join \(name)'s game")
        Speaker.shared.say("Friends can join now")
    }

    private func notes(for id: String) -> [VehicleNote] {
        Array((vehicleNotes[id] ?? [:]).values)
    }

    private func hostReceived(_ message: NetMessage, from id: Int) {
        guard session == .hosting, let host else { return }
        switch message {
        case let .hello(version, name, color, crew):
            guard version == Net.version else {
                host.send(.refused(reason: "Update Wolfie Galactic on both devices to play together"), to: id)
                return
            }
            let card = PlayerCard(id: id, name: name, color: color, crew: crew)
            let edits = (try? world.compressedEdits()) ?? [:]
            host.send(.welcome(you: id, planet: planet.id, edits: edits, vehicles: notes(for: planet.id), players: [myCard] + avatars.cards), to: id)
            host.broadcast(.joined(card), except: id)
            // Where everyone is right now, so the friend sees them straight away.
            host.send(.pose(id: myID, pose: myPose), to: id)
            for other in avatars.cards {
                if let pose = avatars.pose(of: other.id) { host.send(.pose(id: other.id, pose: pose), to: id) }
            }
            avatars.add(card)
            players = avatars.cards
            show("\(name) joined")
            Speaker.shared.say("\(name) joined")
            Sound.shared.play("friend-joined")
            sayHiSoon()
        case let .pose(_, pose):
            avatars.setPose(id, pose)
            host.broadcast(.pose(id: id, pose: pose), except: id)
        case let .block(planetID, x, y, z, block):
            hostWorld(planetID)?.set(SIMD3(x, y, z), block)
            host.broadcast(.block(planet: planetID, x: x, y: y, z: z, id: block), except: id)
        case let .blast(planetID, x, y, z, radius):
            friendBlast(planet: planetID, at: SIMD3(x, y, z), radius: radius)
            host.broadcast(.blast(planet: planetID, x: x, y: y, z: z, radius: radius), except: id)
        case let .nest(planetID, nestID, cured):
            if let w = hostWorld(planetID) { friendNest(nestID, cured: cured, planet: planetID, world: w) }
            host.broadcast(.nest(planet: planetID, id: nestID, cured: cured), except: id)
        case let .askPlanet(planetID):
            let edits = (try? hostWorld(planetID)?.compressedEdits()) ?? [:]
            host.send(.planetData(planet: planetID, edits: edits, vehicles: notes(for: planetID)), to: id)
        case let .vehicle(note):
            remember(note)
            apply(note)
            host.broadcast(.vehicle(note), except: id)
        default:
            break
        }
    }

    private func friendLeft(_ id: Int) {
        guard let card = avatars.card(id) else { return }
        avatars.remove(id)
        players = avatars.cards
        host?.broadcast(.left(id: id))
        // Anything they were driving is parked where they left it.
        for (planetID, notes) in vehicleNotes {
            for (kind, var note) in notes where note.driver == id {
                note.driver = nil
                vehicleNotes[planetID]?[kind] = note
                apply(note)
                host?.broadcast(.vehicle(note))
            }
        }
        show("\(card.name) left")
    }

    // MARK: Joining

    func join(named name: String) {
        guard let game = foundGames.first(where: { $0.name == name }) else { return }
        save()   // your own world, before borrowing a friend's
        stopLooking()
        joinAttempt += 1
        let attempt = joinAttempt

        let link = PeerLink(connection: NWConnection(to: game.endpoint, using: PeerLink.parameters()))
        let settings = GameSettings.shared
        link.onReady = { [weak link] in
            link?.send(.hello(version: Net.version, name: settings.playerNameText, color: settings.playerColor, crew: settings.crew))
        }
        link.onMessage = { [weak self] message in self?.clientReceived(message) }
        link.onClose = { [weak self] in self?.lostHost(name: name) }
        self.link = link
        hostName = name.replacingOccurrences(of: "'s game", with: "")
        travelText = "Joining \(name)…"
        link.start()

        // Give up if there's no answer.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard let self, self.joinAttempt == attempt, self.session != .joined, self.link != nil else { return }
            self.link?.onClose = nil
            self.link?.close()
            self.link = nil
            self.travelText = nil
            self.startLooking()
            self.show("Couldn't reach \(name)")
        }
    }

    private func clientReceived(_ message: NetMessage) {
        switch message {
        case let .welcome(you, planetID, edits, notes, cards):
            guard let destination = PlanetCatalog.shared.planet(id: planetID) else {
                link?.close()
                return
            }
            myID = you
            session = .joined
            vehicleNotes = [:]
            for note in notes { remember(note) }
            avatars.removeAll()
            for card in cards where card.id != you { avatars.add(card) }
            players = avatars.cards
            if let hostCard = cards.first(where: { $0.id == Net.hostID }) { hostName = hostCard.name }
            leaveSpaceQuietly()
            land(on: destination, world: World(planet: destination, edits: edits))
            screen = .playing
            menuIndex = 0
            waitForGround()
            #if os(macOS)
            input.capturePointer()
            #endif
            Speaker.shared.say("Joined \(hostName)'s game")
        case let .refused(reason):
            link?.onClose = nil
            link?.close()
            link = nil
            travelText = nil
            startLooking()
            show(reason)
        case let .joined(card):
            guard card.id != myID else { return }
            avatars.add(card)
            players = avatars.cards
            show("\(card.name) joined")
            Sound.shared.play("friend-joined")
            sayHiSoon()
        case let .left(id):
            if let card = avatars.card(id) { show("\(card.name) left") }
            avatars.remove(id)
            players = avatars.cards
        case let .pose(id, pose):
            if id != myID { avatars.setPose(id, pose) }
        case let .block(planetID, x, y, z, block):
            // Changes on other planets arrive with that planet when you go there.
            if planetID == planet.id { world.set(SIMD3(x, y, z), block) }
        case let .blast(planetID, x, y, z, radius):
            friendBlast(planet: planetID, at: SIMD3(x, y, z), radius: radius)
        case let .nest(planetID, nestID, cured):
            if planetID == planet.id { friendNest(nestID, cured: cured, planet: planetID, world: world) }
        case let .planetData(planetID, edits, notes):
            for note in notes { remember(note) }
            arrivedPlanets[planetID] = edits
        case let .vehicle(note):
            remember(note)
            apply(note)
        case .hello, .askPlanet:
            break
        }
    }

    /// Hide the "Landing…" message once the ground around you has loaded.
    func waitForGround() {
        Task { @MainActor [weak self] in
            var waited = 0
            while let self, !self.renderer.isReady(around: self.player.position), waited < 80 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waited += 1
            }
            self?.travelText = nil
        }
    }

    private func lostHost(name: String) {
        let wasJoined = session == .joined
        link = nil
        guard wasJoined else {
            // Never got in.
            travelText = nil
            startLooking()
            show("Couldn't join \(name)")
            return
        }
        leaveShared()
        menuReturn = .title
        screen = .friends
        menuIndex = 0
        startLooking()
        show("\(hostName)'s game ended")
        Speaker.shared.say("\(hostName)'s game ended")
    }

    // MARK: Ending

    /// Stop hosting or leave a friend's game, and go back to your own world.
    func endSession() {
        switch session {
        case .solo:
            link?.onClose = nil
            link?.close()
            link = nil
        case .hosting:
            saveOtherWorlds()
            host?.stop()
            host = nil
            session = .solo
            otherWorlds = [:]
            vehicleNotes = [:]
            avatars.removeAll()
            players = []
            nameTags = []
        case .joined:
            link?.onClose = nil
            link?.close()
            link = nil
            leaveShared()
        }
        joinAttempt += 1
    }

    /// Back from a friend's world to your own saved one.
    private func leaveShared() {
        leaveSpaceQuietly()
        session = .solo
        avatars.removeAll()
        players = []
        nameTags = []
        vehicleNotes = [:]
        arrivedPlanets = [:]
        myID = Net.hostID
        let catalog = PlanetCatalog.shared
        let home = WorldStore.lastPlanet.flatMap { catalog.planet(id: $0) } ?? catalog.home
        let loaded = Game.makeWorld(for: home)
        planet = home
        world = loaded.world
        player = loaded.player
        applyPlanet()
        travelText = nil
    }
}
