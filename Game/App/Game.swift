import CoreGraphics
import Foundation
import Observation
import RealityKit
import simd

/// Runs the game: owns the current planet's world, the player and the 3D scene,
/// and steps them every frame.
@MainActor
@Observable
final class Game {
    // What the HUD shows.
    /// What's in your hands: six slots of blocks, builds, vehicles or the laser.
    var hotbar: [Item]
    var hotbarIndex = 0
    /// Everything you've collected or made, by item key ("block:7" → 12).
    var backpack: [String: Int] = Game.loadBackpack()
    var backpackTab: ItemGroup = .blocks
    var backpackIndex = 0
    private(set) var message = ""
    /// Set only by the game itself (here and in Game+Together.swift).
    var planet: Planet
    /// The vehicle close enough to get into.
    var nearVehicle: String?
    /// The vehicle you're in, if any (see Game+Vehicles.swift).
    var driving: String?
    var screen: Screen = .title
    var menuIndex = 0
    /// True after the first press of "Start this planet over", waiting for a second press.
    private(set) var confirmingRestart = false
    /// Which button names to show: keyboard keys or controller buttons.
    private(set) var keyboardMode = false
    /// Mac: true while playing with the mouse not captured, to show "Click to look around".
    private(set) var pointerFree = false
    var starMapOpen: Bool { screen == .starMap }
    private(set) var starMapSelection = 0
    var travelText: String?
    /// Double-tap jump to fly.
    var flying = false

    // Playing together (see Game+Together.swift).
    enum Session { case solo, hosting, joined }
    var session: Session = .solo
    /// Games found on this Wi-Fi, for the Play together menu.
    var foundGames: [FoundGame] = []
    /// Everyone else in the game.
    var players: [PlayerCard] = []
    /// Friends' names, placed over their heads.
    var nameTags: [NameTag] = []
    @ObservationIgnored var viewSize: CGSize = .zero
    @ObservationIgnored let avatars = Avatars()
    @ObservationIgnored var host: NetHost?
    @ObservationIgnored var link: PeerLink?
    @ObservationIgnored let browser = NetBrowser()
    @ObservationIgnored var myID = Net.hostID
    @ObservationIgnored var hostName = ""
    @ObservationIgnored var poseTimer: Float = 0
    @ObservationIgnored var lastSentPose: Pose?
    /// Where your laser beam ends while you fire, so friends can see it.
    @ObservationIgnored var laserEnd: SIMD3<Float>?
    @ObservationIgnored var joinAttempt = 0

    var planets: [Planet] { PlanetCatalog.shared.planets }

    /// "Version 0.1 · build 142 · Oct 31 12:50 PM", to check you have the newest TestFlight build.
    static let versionText: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let date = info["WGBuildDate"] as? String ?? ""
        let commit = info["WGBuildCommit"] as? String ?? ""
        var parts = ["Version \(version)", "build \(build)"]
        if !date.isEmpty { parts.append(date) }
        if !commit.isEmpty && commit != "local" { parts.append(commit) }
        return parts.joined(separator: " · ")
    }()
    var laserSelected: Bool { hotbar[hotbarIndex] == .laser }

    // Simulation.
    @ObservationIgnored var world: World
    @ObservationIgnored var player: Player
    @ObservationIgnored let input = InputController()

    // Scene.
    @ObservationIgnored let root = Entity()
    @ObservationIgnored let camera = PerspectiveCamera()
    @ObservationIgnored private let sky: ModelEntity
    @ObservationIgnored private let skyBodies = Entity()
    @ObservationIgnored private let stars: ModelEntity
    @ObservationIgnored let highlight: ModelEntity
    @ObservationIgnored private let beam = Entity()
    @ObservationIgnored private let impact: ModelEntity
    /// One model per kind of vehicle on this planet, made when first needed.
    @ObservationIgnored var vehicleModels: [String: Entity] = [:]
    /// Vehicles on this planet, by id.
    @ObservationIgnored var vehicles: [String: Vehicle] = [:]
    /// The kind of vehicle you're in, or next to.
    var drivingKind: VehicleKind? { driving.flatMap { vehicles[$0]?.kind } }
    var nearVehicleKind: VehicleKind? { nearVehicle.flatMap { vehicles[$0]?.kind } }
    /// The chase camera's swing around the vehicle, and its tilt.
    @ObservationIgnored var chaseYaw: Float = 0
    @ObservationIgnored var chasePitch: Float = -0.2
    @ObservationIgnored var chaseEye: SIMD3<Float>?
    @ObservationIgnored let effects = Effects()
    @ObservationIgnored var boltCooldown: Float = 0
    // Items (see Game+Items.swift).
    @ObservationIgnored let pickups = Pickups()
    @ObservationIgnored let ghost: ModelEntity = {
        var m = UnlitMaterial(color: PlatformColor(red: 0.37, green: 0.94, blue: 1, alpha: 1))
        m.blending = .transparent(opacity: .init(floatLiteral: 0.22))
        m.faceCulling = .none
        let box = ModelEntity(mesh: .generateBox(size: 1), materials: [m])
        box.isEnabled = false
        return box
    }()
    @ObservationIgnored var machineCooldown: Float = 0
    @ObservationIgnored var crystalTimer: Float = 10
    @ObservationIgnored var jumpPadClock: Float = -100
    @ObservationIgnored var pickupTally: [UInt8: Int] = [:]
    @ObservationIgnored var pickupTimer: Float = 0
    @ObservationIgnored var boltSide: Float = 1
    /// The controls card, opened with the help button.
    var showHelp = false

    // The crew (see Game+Crew.swift).
    /// The highlighted character in the picker.
    var crewIndex = 0
    /// The story card showing.
    var storyIndex = 0
    @ObservationIgnored var storyReturn: Screen = .title
    /// You, seen from behind.
    @ObservationIgnored var me = CrewRig(GameSettings.shared.crew)
    /// Where aiming starts: your eyes, or (seen from behind) the camera's line of sight level with you.
    @ObservationIgnored var aimOrigin = SIMD3<Float>(repeating: 0)
    /// The camera got pushed in so close (by a wall) that you'd be in the way.
    @ObservationIgnored var cameraCrowded = false
    @ObservationIgnored var lastMePosition: SIMD3<Float>?
    @ObservationIgnored var recentBlasts: [Float] = []
    @ObservationIgnored var sprinting = false
    /// Weapons (see Game+Weapons.swift).
    @ObservationIgnored let armory = Armory()
    /// The Red Glitch (see Game+Glitch.swift).
    @ObservationIgnored let glitch = GlitchState()
    @ObservationIgnored let roboCats = RoboCats()

    // Space (see Game+Space.swift).
    var place: Place = .surface
    /// Glowing hot while coming down through an atmosphere.
    var entryGlow = false
    /// 0...1 while rushing through hyperspace.
    var warpGlow: Float = 0
    /// The ship you could swap to at the spaceport.
    var dockPrompt: VehicleKind?
    @ObservationIgnored let space = SpaceScene()
    @ObservationIgnored var spaceShip: Vehicle?
    @ObservationIgnored var spaceTransition = false
    @ObservationIgnored var hyperspaceTime: Float = -1
    @ObservationIgnored var hyperspaceTarget: Planet?
    @ObservationIgnored var skyDarkness: Float = -1

    // Everyone going their own way (see Game+Together.swift).
    /// The host's copies of planets it isn't on, which friends may be on.
    @ObservationIgnored var otherWorlds: [String: World] = [:]
    /// Where each vehicle is on each planet, and who's driving it.
    @ObservationIgnored var vehicleNotes: [String: [String: VehicleNote]] = [:]
    // The map (see Game+Map.swift).
    var mapImage: CGImage?
    @ObservationIgnored var mapOrigin = SIMD2<Int>(0, 0)
    @ObservationIgnored var mapPlanet = ""
    /// Planets the host has sent us, waiting to be landed on.
    @ObservationIgnored var arrivedPlanets: [String: [String: Data]] = [:]
    @ObservationIgnored var renderer: WorldRenderer!
    @ObservationIgnored private var hazeShells: [ModelEntity] = []
    @ObservationIgnored private var blockMaterial: UnlitMaterial?
    /// The block colours, shared by every chunk (the Glitch's glow pulses in it).
    @ObservationIgnored var blockTexture: TextureResource?
    @ObservationIgnored private var lastJumpTap: Float = -10
    @ObservationIgnored var updateSubscription: EventSubscription?

    // Timers.
    @ObservationIgnored private var breakCooldown: Float = 0
    @ObservationIgnored private var placeCooldown: Float = 0
    @ObservationIgnored private var laserCooldown: Float = 0
    @ObservationIgnored private var saveTimer: Float = 0
    @ObservationIgnored var messageTimer: Float = 0
    @ObservationIgnored private var clock: Float = 0
    @ObservationIgnored private var stepDistance: Float = 0
    @ObservationIgnored private var laserFiring = false

    // Critters and hearts (see Game+Critters.swift).
    @ObservationIgnored let critters = Critters()
    /// Hearts left, when Danger is on.
    var hearts = 5
    /// Briefly true after getting bumped, to flash the screen.
    var hurtFlash = false
    /// "Make friends with the Fluffalump", while looking at a critter close by.
    var petPrompt: String?
    /// Critters you've made friends with (or, for grumpy ones, sent home).
    var foundCritters: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "critterBook") ?? [])
    @ObservationIgnored var lastPlaceHeld = false
    @ObservationIgnored var safeTime: Float = 0
    @ObservationIgnored var regenTimer: Float = 0
    @ObservationIgnored var critterClock: Float = 0

    static let laserColor = SIMD3<Float>(1.0, 0.31, 0.85)
    /// The sky sits beyond the farthest land.
    static let skyRadius: Float = 2600

    init() {
        let catalog = PlanetCatalog.shared
        let start = WorldStore.lastPlanet.flatMap { catalog.planet(id: $0) } ?? catalog.home
        let loaded = Game.makeWorld(for: start)
        planet = start
        world = loaded.world
        player = loaded.player
        hotbar = Game.loadHotbar()
        hotbarIndex = min(max(loaded.hotbarIndex, 0), 5)

        var skyMaterial = UnlitMaterial(color: .white)
        skyMaterial.faceCulling = .none
        sky = ModelEntity(mesh: .generateSphere(radius: Game.skyRadius), materials: [skyMaterial])
        stars = Game.makeStars()

        var highlightMaterial = UnlitMaterial(color: .white)
        highlightMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.25))
        highlight = ModelEntity(mesh: .generateBox(size: 1.03), materials: [highlightMaterial])
        highlight.isEnabled = false

        impact = ModelEntity(mesh: .generateBox(size: 0.5), materials: [Game.glow(Game.laserColor, opacity: 0.8)])

        buildScene()
    }

    // MARK: Worlds

    /// Loads a planet's saved world, or makes a new one.
    static func makeWorld(for planet: Planet) -> (world: World, player: Player, hotbarIndex: Int) {
        if let save = WorldStore.load(planet: planet.id),
           let world = World(planet: planet, save: save),
           save.player.count >= 5 {
            var player = Player(position: SIMD3<Float>(save.player[0], save.player[1], save.player[2]))
            player.yaw = save.player[3]
            player.pitch = save.player[4]
            player.flying = save.player.count >= 6 && save.player[5] > 0.5
            return (world, player, save.hotbarIndex)
        }
        let world = World(planet: planet)
        return (world, Player(position: world.spawnPoint()), 0)
    }

    // MARK: Scene

    private func buildScene() {
        let colors = (0..<BlockRegistry.maxBlocks).map { BlockRegistry.shared.rgb(UInt8($0)) }
        if let texture = PaletteTexture.make(colors: colors) {
            blockMaterial = PaletteTexture.material(texture)
            blockTexture = texture
        }

        camera.camera.fieldOfViewInDegrees = 70
        camera.camera.near = 0.05
        camera.camera.far = Game.skyRadius + 400
        root.addChild(camera)
        root.addChild(sky)
        sky.addChild(stars)
        sky.addChild(skyBodies)
        root.addChild(highlight)
        root.addChild(me.root)
        me.root.isEnabled = false
        root.addChild(avatars.root)
        root.addChild(critters.root)
        root.addChild(effects.root)
        root.addChild(armory.root)
        root.addChild(roboCats.root)
        root.addChild(pickups.root)
        root.addChild(ghost)
        root.addChild(space.root)
        root.addChild(space.far)
        camera.addChild(space.warp)
        space.root.isEnabled = false
        space.far.isEnabled = false
        space.warp.isEnabled = false

        // Laser beam: a bright core inside a soft glow, stretched along its length each frame.
        let core = ModelEntity(mesh: .generateBox(width: 0.05, height: 0.05, depth: 1), materials: [Game.glow(SIMD3<Float>(1, 0.85, 0.97), opacity: 1)])
        let halo = ModelEntity(mesh: .generateBox(width: 0.16, height: 0.16, depth: 1), materials: [Game.glow(Game.laserColor, opacity: 0.45)])
        beam.addChild(core)
        beam.addChild(halo)
        beam.isEnabled = false
        impact.isEnabled = false
        root.addChild(beam)
        root.addChild(impact)

        renderer = WorldRenderer(world: world, material: blockMaterial)
        root.addChild(renderer.root)

        // Haze: three thin see-through shells in the sky colour, so far land fades into the sky.
        for (top, opacity) in [(Float(2), Float(0.22)), (Float(4), Float(0.3)), (Float(7), Float(0.72))] {
            let shell = ModelEntity()
            if let mesh = Game.hazeMesh(topDegrees: top) {
                shell.model = ModelComponent(mesh: mesh, materials: [Game.haze(SIMD3<Float>(1, 1, 1), opacity: opacity)])
            }
            hazeShells.append(shell)
            root.addChild(shell)
        }


        applyPlanet()
    }

    /// Everything that changes when you land somewhere new.
    func applyPlanet() {
        renderer.reset(world: world)
        critters.reset(planet: planet.id)
        effects.clear()
        armory.clear()
        roboCats.clear()
        glitch.forgetNearby()
        stopGlitchHum()
        pickups.clear()
        flying = player.flying

        skyDarkness = -1
        applySky(darkness: 0)
        applyViewDistance()

        for child in Array(skyBodies.children) { child.removeFromParent() }
        skyBodies.addChild(SkyDecor.build(for: planet, radius: Game.skyRadius))

        placeVehicles()
        syncCamera()
    }

    /// The planet's sky, darkening toward black space (darkness 1) as a ship climbs.
    func applySky(darkness raw: Float) {
        // Only change materials when the shade really changes.
        let darkness = (raw * 20).rounded() / 20
        guard darkness != skyDarkness else { return }
        skyDarkness = darkness
        let space = SIMD3<Float>(0.012, 0.008, 0.035)
        let sky3 = BlockRegistry.parseHex(planet.sky) * (1 - darkness) + space * darkness
        var skyMaterial = UnlitMaterial(color: Game.color(sky3))
        skyMaterial.faceCulling = .none
        sky.model?.materials = [skyMaterial]
        stars.isEnabled = planet.stars || darkness > 0.3
        skyBodies.isEnabled = darkness < 1
        let hazeOpacity: [Float] = [0.22, 0.3, 0.72]
        for (i, shell) in hazeShells.enumerated() {
            shell.isEnabled = darkness < 0.95
            shell.model?.materials = [Game.haze(sky3, opacity: hazeOpacity[i] * (1 - darkness))]
        }
    }

    /// Size the haze to the view distance setting.
    private func applyViewDistance() {
        let reach = Float(GameSettings.shared.farDistance)
        for (shell, share) in zip(hazeShells, [Float(0.45), 0.68, 0.9]) {
            shell.scale = SIMD3<Float>(repeating: reach * share)
        }
    }

    func syncCamera() {
        let eye = player.eye
        camera.orientation = player.orientation
        guard GameSettings.shared.viewBehind else {
            camera.position = eye
            aimOrigin = eye
            cameraCrowded = false
            followCamera(eye)
            return
        }
        // Behind and a little to the right, so you can see where you're aiming past your character.
        let look = player.lookDirection
        let right = player.orientation.act(SIMD3<Float>(1, 0, 0))
        let wanted = eye + right * 0.55 + SIMD3<Float>(0, 0.25, 0) - look * 3.6
        let path = wanted - eye
        let length = simd_length(path)
        var reach: Float = 1
        // Walls and hills push the camera in.
        var t: Float = 0.08
        while t <= 1 {
            let p = eye + path * t
            if world.isSolidForPhysics(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z))) {
                reach = max(0, t - 0.3 / max(length, 0.01))
                break
            }
            t += 0.1 / max(length, 0.01)
        }
        let cam = eye + path * reach
        camera.position = cam
        aimOrigin = cam + look * max(0, simd_dot(eye - cam, look))
        cameraCrowded = length * reach < 1.1
        followCamera(cam)
    }

    /// The sky and haze move with the camera.
    func followCamera(_ eye: SIMD3<Float>) {
        sky.position = eye
        for shell in hazeShells { shell.position = eye }
    }

    // MARK: Frame

    func update(dt rawDelta: TimeInterval) {
        let dt = Float(min(max(rawDelta, 0), 0.05))
        clock += dt
        input.mouseLookEnabled = screen == .playing && travelText == nil
        let frame = input.poll(dt: dt)
        if keyboardMode != input.usingKeyboard { keyboardMode = input.usingKeyboard }
        #if os(macOS)
        let free = screen == .playing && !input.pointerCaptured
        if pointerFree != free { pointerFree = free }
        #endif

        // Keep the land around the camera loaded and drawn.
        let settings = GameSettings.shared
        if place == .surface {
            renderer.update(focus: camera.position, detailRadius: settings.detailRadius, farRadius: settings.farDistance)
        }
        updateTogether(dt: dt)
        updateMusic()
        effects.update(dt: dt)
        updateGlitchGlow(dt: dt)
        if screen == .playing && place == .surface && travelText == nil {
            updateArmory(dt: dt)
            updateGlitch(dt: dt)
        } else {
            stopGlitchHum()
        }
        if frame.help && (screen == .playing || screen == .starMap) {
            showHelp.toggle()
            Sound.shared.play("menu-move")
        }
        if messageTimer > 0 {
            messageTimer -= dt
            if messageTimer <= 0 { message = "" }
        }

        if screen == .title || place != .surface || driving != nil || travelText != nil {
            me.root.isEnabled = false
            lastMePosition = nil
        }
        if travelText != nil {
            hideLaser()
            return
        }
        switch screen {
        case .title:
            orbitCamera(dt: dt)
            hideLaser()
            highlight.isEnabled = false
            updateMenu(frame)
            return
        case .backpack:
            hideLaser()
            updateBackpack(frame)
            return
        case .map:
            if frame.map {
                closeMap()
                return
            }
            hideLaser()
            updateMenu(frame)
            return
        case .crew:
            if menuReturn == .title { orbitCamera(dt: dt) }
            hideLaser()
            updateCrewPicker(frame)
            return
        case .story:
            if storyReturn == .title { orbitCamera(dt: dt) }
            hideLaser()
            updateStory(frame)
            return
        case .paused, .settings, .controls, .friends, .critterBook:
            if screen != .paused && menuReturn == .title { orbitCamera(dt: dt) }
            hideLaser()
            updateMenu(frame)
            return
        case .starMap:
            updateStarMap(frame)
            hideLaser()
            return
        case .playing:
            if frame.pause {
                pause()
                return
            }
            if frame.map {
                openMap()
                return
            }
            if frame.backpack || (frame.action && driving == nil && place == .surface) {
                openBackpack()
                return
            }
        }

        // Out in space: only the ship.
        if place == .space {
            updateSpace(frame, dt: dt)
            nearVehicle = nil
            updatePetPrompt(nil)
            return
        }

        // In the rover or the starship: steering instead of walking and building.
        if driving != nil {
            updateDriving(frame, dt: dt)
            nearVehicle = nil
            ghost.isEnabled = false
            updatePickups(dt: dt)
            updatePetPrompt(nil)
            updateCritters(dt: dt, fallSpeed: 0, wasOnGround: true)
            saveTimer += dt
            if saveTimer > 60 {
                saveTimer = 0
                save()
            }
            return
        }

        if frame.perspective { switchView() }
        let lookY = frame.look.y * (settings.invertLook ? -1 : 1)
        player.yaw += frame.look.x * settings.lookMultiplier
        player.pitch = min(max(player.pitch + lookY * settings.lookMultiplier, -1.5), 1.5)

        if frame.hotbarStep != 0 {
            let count = hotbar.count
            selectSlot(((hotbarIndex + frame.hotbarStep) % count + count) % count)
        }
        if let slot = frame.hotbarSelect, slot < hotbar.count {
            selectSlot(slot)
        }

        // Double-tap jump to start or stop flying.
        if frame.jumpPressed {
            if clock - lastJumpTap < 0.32 {
                player.flying.toggle()
                lastJumpTap = -10
                show(player.flying ? "Flying" : "Walking")
                Sound.shared.play(player.flying ? "fly-on" : "fly-off", volume: 0.7)
            } else {
                lastJumpTap = clock
            }
        }
        let wasOnGround = player.onGround
        let wasFlying = player.flying
        let fallSpeed = player.velocity.y
        // Sprint, like Minecraft: press L3 and it lasts until you stop.
        if frame.sprintPressed { sprinting.toggle() }
        if simd_length(frame.move) < 0.2 { sprinting = false }
        player.step(dt: dt, move: frame.move, jump: frame.jump, descend: frame.descend, gravity: planet.gravity, world: world, sprint: sprinting)
        if flying != player.flying { flying = player.flying }
        playMovementSounds(dt: dt, wasOnGround: wasOnGround, wasFlying: wasFlying, fallSpeed: fallSpeed)
        syncCamera()

        // Vehicles: walk up to one and press Y (F on a keyboard) to get in.
        let reachable = vehicleInReach()
        if nearVehicle != reachable { nearVehicle = reachable }
        if let reachable, frame.openMap || (frame.usePressed && lookingAt(reachable)) {
            board(reachable)
            return
        }

        // A critter in front of the nearest block takes the laser, or a pat instead of building.
        updateMe(dt: dt)
        shakeCamera()
        let behind = GameSettings.shared.viewBehind && !cameraCrowded
        let footAim = LaserAim(
            origin: aimOrigin,
            direction: player.lookDirection,
            // From the blaster in your character's hand, or just below and right of your eye.
            muzzle: behind ? me.muzzle : player.eye + player.orientation.act(SIMD3<Float>(0.22, -0.2, -0.35))
        )
        let aimed = aimCritter(from: footAim)
        if let weapon = heldWeapon {
            hideLaser()
            updateWeapon(weapon, frame: frame, dt: dt, aim: footAim, critter: aimed)
        } else if laserSelected {
            highlight.isEnabled = false
            ghost.isEnabled = false
            updateLaser(firing: frame.breakHeld, dt: dt, critter: aimed, aim: footAim)
        } else {
            hideLaser()
            if let aimed, !aimed.kind.isGrumpy {
                highlight.isEnabled = false
                petIfPressed(aimed, pressed: frame.placeHeld)
            } else {
                updateBuilding(frame, dt: dt)
            }
        }
        lastPlaceHeld = frame.placeHeld
        updatePetPrompt(aimed)
        updateMachines(dt: dt)
        updatePickups(dt: dt)
        updateCritters(dt: dt, fallSpeed: fallSpeed, wasOnGround: wasOnGround)

        saveTimer += dt
        if saveTimer > 60 {
            saveTimer = 0
            save()
        }
    }

    private func updateBuilding(_ frame: InputFrame, dt: Float) {
        let target = raycast(world: world, origin: aimOrigin, direction: player.lookDirection, maxDistance: Player.reach)
        if let target {
            highlight.isEnabled = true
            highlight.position = SIMD3<Float>(Float(target.block.x) + 0.5, Float(target.block.y) + 0.5, Float(target.block.z) + 0.5)
        } else {
            highlight.isEnabled = false
        }

        // Hold a trigger to keep breaking or placing.
        if !frame.breakHeld { breakCooldown = 0 }
        if !frame.placeHeld { placeCooldown = 0 }
        breakCooldown -= dt
        placeCooldown -= dt

        updateGhost(target: target)

        if frame.breakHeld, breakCooldown <= 0, let target, target.block.y > 0 {
            let id = world.block(target.block)
            changeBlock(target.block, B.air)
            dropPickup(id, at: SIMD3<Float>(target.block) + SIMD3(0.5, 0.5, 0.5))
            breakCooldown = 0.25
            Sound.shared.playVaried("break", volume: 0.8)
        }
        if frame.placeHeld, placeCooldown <= 0, let target {
            if placeHeld(target: target, pressedNow: !lastPlaceHeld) {
                placeCooldown = 0.25
                Sound.shared.playVaried("place", volume: 0.8)
            }
        }
    }

    // MARK: Laser

    /// Hold the right trigger (or left click) to fire. The beam blasts away one block
    /// every tenth of a second, from up to 32 blocks away.
    func updateLaser(firing: Bool, dt: Float, critter: AimedCritter?, aim: LaserAim) {
        guard firing else {
            hideLaser()
            laserCooldown = 0
            return
        }
        if !laserFiring {
            laserFiring = true
            Sound.shared.play("laser-start", volume: 0.6)
            Sound.shared.startLoop("laser-loop", volume: 0.18)
        }
        let direction = aim.direction
        let cat = critter == nil ? catInLine(aim, range: Player.laserRange) : nil
        let target = critter == nil && cat == nil ? raycast(world: world, origin: aim.origin, direction: direction, maxDistance: Player.laserRange) : nil
        let end: SIMD3<Float>
        if let cat {
            end = cat.point
        } else if let critter {
            end = critter.point
        } else if let target {
            end = SIMD3<Float>(Float(target.block.x) + 0.5, Float(target.block.y) + 0.5, Float(target.block.z) + 0.5)
        } else {
            end = aim.origin + direction * Player.laserRange
        }

        let start = aim.muzzle
        let span = end - start
        let length = simd_length(span)
        if length > 0.01 {
            beam.isEnabled = true
            beam.position = (start + end) / 2
            beam.orientation = simd_quatf(from: SIMD3<Float>(0, 0, -1), to: span / length)
            let flicker = 1 + 0.25 * sin(clock * 60)
            beam.scale = SIMD3<Float>(flicker, flicker, length)
        }

        impact.isEnabled = target != nil || critter != nil || cat != nil
        impact.position = end
        laserEnd = end
        impact.scale = SIMD3<Float>(repeating: 1.2 + 0.4 * sin(clock * 40))

        laserCooldown -= dt
        if laserCooldown <= 0, let cat {
            hitCat(cat.id, from: aim.origin)
            laserCooldown = 0.35
        } else if laserCooldown <= 0, let critter {
            zapCritter(critter)
            laserCooldown = 0.3
        } else if laserCooldown <= 0, let target, target.block.y > 0 {
            blastBlock(target.block, loud: false)
            laserCooldown = 0.1
            Sound.shared.playVaried("blast", volume: 0.45, spread: 0.15)
        }
    }

    func hideLaser() {
        laserEnd = nil
        if laserFiring {
            laserFiring = false
            Sound.shared.stopLoop()
        }
        beam.isEnabled = false
        impact.isEnabled = false
    }

    // MARK: Star map and travel

    func openStarMap() {
        starMapSelection = PlanetCatalog.shared.index(of: planet.id)
        screen = .starMap
        highlight.isEnabled = false
        #if os(macOS)
        input.releasePointer()
        #endif
    }

    /// The on-screen "Get in" button.
    func boardFromButton() {
        if let nearVehicle { board(nearVehicle) }
    }

    func closeStarMap() {
        screen = .playing
        #if os(macOS)
        input.capturePointer()
        #endif
    }

    private func updateStarMap(_ frame: InputFrame) {
        let count = planets.count
        let step = frame.menuStep + frame.hotbarStep
        if step != 0 {
            starMapSelection = ((starMapSelection + step) % count + count) % count
            Sound.shared.play("menu-move")
            Speaker.shared.say(planets[starMapSelection].name)
        }
        if frame.cancel || frame.pause {
            closeStarMap()
        } else if frame.confirm {
            travel(to: starMapSelection)
        }
    }

    func selectStarMapItem(_ index: Int) {
        guard planets.indices.contains(index) else { return }
        starMapSelection = index
    }

    func travel(to index: Int) {
        guard planets.indices.contains(index) else { return }
        let destination = planets[index]
        screen = .playing
        if place == .space {
            startHyperspace(to: destination)
            return
        }
        guard destination.id != planet.id else { return }

        save()
        travelText = "Flying to \(destination.name)…"
        Sound.shared.play("launch", volume: 0.9)
        Speaker.shared.say("Flying to \(destination.name)")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            let next = await self.fetchWorld(for: destination)
            self.land(on: destination, world: next)
            // Stay in flight until the ground around the landing pad is ready (at most 8 seconds).
            var waited = 0
            while !self.renderer.isReady(around: self.player.position) && waited < 80 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waited += 1
            }
            self.travelText = nil
        }
    }

    /// Switch to another planet's world. Arrive next to the starship, unless given a spot.
    func land(on destination: Planet, world given: World? = nil, at spot: SIMD3<Float>? = nil) {
        // The host keeps the planet you're leaving, in case friends are still there.
        if session == .hosting && destination.id != planet.id { otherWorlds[planet.id] = world }
        let newWorld = given ?? otherWorlds.removeValue(forKey: destination.id) ?? Game.makeWorld(for: destination).world
        planet = destination
        world = newWorld
        player = Player(position: spot ?? world.arrivalPoint())
        if session != .joined { WorldStore.lastPlanet = destination.id }
        applyPlanet()
        avatars.forgetPoses()
    }

    // MARK: Title, pause and settings

    enum Screen {
        case title, playing, paused, settings, controls, starMap, friends, critterBook, map, backpack, crew, story
    }

    enum MenuItem: Hashable {
        case play, controls, settings, resume, quitToTitle
        case lookSpeed, invertLook, speakNames, viewDistance, restartPlanet, back
        case friends, hostGame, join(String), searching, yourName, yourColor
        case music, soundEffects, danger, critterBook, backpackMode
        case map, goTo(Int), goToPlace(String)
        case crew, cameraView, voices, story
    }

    /// Where Back goes from Settings or Controls.
    @ObservationIgnored var menuReturn: Screen = .title

    var menuItems: [MenuItem] {
        switch screen {
        case .title: return [.play, .crew, .friends, .controls, .settings]
        case .friends:
            let games: [MenuItem] = foundGames.isEmpty ? [.searching] : foundGames.map { .join($0.name) }
            return [.hostGame] + games + [.yourName, .yourColor, .back]
        case .paused: return [.resume, .map, .crew, .critterBook, .story, .controls, .settings, .quitToTitle]
        case .map:
            var items: [MenuItem] = friendSpots.map { .goTo($0.id) }
            if place == .surface {
                items.append(.goToPlace(Landmark.pad.rawValue))
                if nearestSettlement != nil { items.append(.goToPlace(Landmark.settlement.rawValue)) }
                if nearestNest != nil { items.append(.goToPlace(Landmark.nest.rawValue)) }
            }
            return items + [.back]
        case .controls, .critterBook: return [.back]
        case .settings:
            return menuReturn == .paused && session == .solo
                ? [.danger, .backpackMode, .cameraView, .lookSpeed, .invertLook, .viewDistance, .music, .soundEffects, .voices, .speakNames, .restartPlanet, .back]
                : [.danger, .backpackMode, .cameraView, .lookSpeed, .invertLook, .viewDistance, .music, .soundEffects, .voices, .speakNames, .back]
        default: return []
        }
    }

    /// Words shown on a menu row: its title and, for settings, the current value.
    func label(for item: MenuItem) -> (title: String, value: String?) {
        let settings = GameSettings.shared
        switch item {
        case .play: return ("Play", planet.name)
        case .settings: return ("Settings", nil)
        case .controls: return ("Controls", nil)
        case .resume: return ("Keep playing", nil)
        case .quitToTitle:
            switch session {
            case .solo: return ("Save and go to title", nil)
            case .hosting: return ("Stop hosting and go to title", nil)
            case .joined: return ("Leave \(hostName)'s game", nil)
            }
        case .lookSpeed: return ("Look speed", GameSettings.lookSpeedNames[settings.lookSpeed])
        case .invertLook: return ("Flip look up and down", settings.invertLook ? "On" : "Off")
        case .speakNames: return ("Say names out loud", settings.speakNames ? "On" : "Off")
        case .viewDistance: return ("How far you can see", GameSettings.viewDistanceNames[settings.viewDistance])
        case .restartPlanet:
            return confirmingRestart
                ? ("Press again to start \(planet.name) over", nil)
                : ("Start \(planet.name) over", nil)
        case .back: return ("Back", nil)
        case .friends: return ("Play together", nil)
        case .hostGame: return ("Host a game", "on this Wi-Fi")
        case .join(let name): return ("Join \(name)", nil)
        case .searching: return ("Looking for games on this Wi-Fi…", nil)
        case .yourName: return ("Your name", settings.playerNameText)
        case .music: return ("Music", GameSettings.musicLevelNames[min(max(settings.musicLevel, 0), 3)])
        case .soundEffects: return ("Sound effects", settings.soundEffects ? "On" : "Off")
        case .danger: return ("Danger", GameSettings.dangerNames[min(max(settings.danger, 0), 2)])
        case .backpackMode: return ("Backpack", settings.freeBuild ? "Free build" : "Collect & craft")
        case .critterBook: return ("Critter book", "\(foundCritters.count) of \(CritterCatalog.shared.kinds.count)")
        case .map: return ("Map", session == .solo ? nil : "find friends")
        case .goTo(let id):
            guard let friend = friendSpots.first(where: { $0.id == id }) else { return ("Friend", nil) }
            return ("Go to \(friend.name)", whereabouts(friend))
        case .goToPlace(let name):
            if name == Landmark.pad.rawValue {
                let pad = world.padCenter
                return ("Go to the landing pad", directions(to: SIMD2(Float(pad.x), Float(pad.y))))
            }
            if name == Landmark.nest.rawValue {
                guard let nest = nearestNest else { return ("Go to a Glitch Nest", nil) }
                return ("Go to the nearest Glitch Nest", directions(to: nest.groundCenter))
            }
            guard let site = nearestSettlement else { return ("Go", nil) }
            return ("Go to \(settlementName(site))", directions(to: SIMD2(Float(site.center.x), Float(site.center.y))))
        case .yourColor: return ("Your color", GameSettings.playerColorNames[min(max(settings.playerColor, 0), GameSettings.playerColorNames.count - 1)])
        case .crew: return ("Character", Crew.member(settings.crew).name)
        case .cameraView:
            let name = Crew.member(settings.crew).name
            return ("Camera", settings.viewBehind ? "Behind \(name)" : "\(name)'s eyes")
        case .voices: return ("Voices", settings.voices ? "On" : "Off")
        case .story: return ("The Story", "the Red Glitch")
        }
    }

    private func updateMenu(_ frame: InputFrame) {
        let items = menuItems
        guard !items.isEmpty else { return }
        if frame.menuMove != 0 {
            moveMenu(to: ((menuIndex + frame.menuMove) % items.count + items.count) % items.count)
        }
        let item = items[min(menuIndex, items.count - 1)]
        if frame.menuStep != 0 {
            adjust(item, by: frame.menuStep)
        }
        if frame.confirm {
            activate(item)
        } else if frame.cancel || frame.pause {
            goBack()
        }
    }

    func moveMenu(to index: Int) {
        guard index != menuIndex else { return }
        menuIndex = index
        Sound.shared.play("menu-move")
        confirmingRestart = false
    }

    /// Tap or click on a row.
    func tapMenu(_ item: MenuItem) {
        if let index = menuItems.firstIndex(of: item) { moveMenu(to: index) }
        activate(item)
    }

    private func adjust(_ item: MenuItem, by step: Int) {
        let settings = GameSettings.shared
        Sound.shared.play("menu-move")
        switch item {
        case .lookSpeed:
            settings.lookSpeed = min(max(settings.lookSpeed + step, 0), 2)
        case .invertLook:
            settings.invertLook.toggle()
        case .speakNames:
            settings.speakNames.toggle()
        case .viewDistance:
            settings.viewDistance = min(max(settings.viewDistance + step, 0), 3)
            applyViewDistance()
        case .yourName:
            let count = GameSettings.playerNames.count
            settings.playerName = ((settings.playerName + step) % count + count) % count
            Speaker.shared.say(settings.playerNameText)
        case .yourColor:
            let count = GameSettings.playerColors.count
            settings.playerColor = ((settings.playerColor + step) % count + count) % count
        case .music:
            settings.musicLevel = min(max(settings.musicLevel + step, 0), 3)
            Sound.shared.applyVolumes()
        case .soundEffects:
            settings.soundEffects.toggle()
            Sound.shared.applyVolumes()
        case .danger:
            settings.danger = min(max(settings.danger + step, 0), 2)
            dangerChanged()
        case .backpackMode:
            settings.freeBuild.toggle()
        case .cameraView:
            settings.viewBehind.toggle()
        case .voices:
            settings.voices.toggle()
            if settings.voices { Voices.shared.say("hi", interrupt: true) }
        default:
            break
        }
    }

    func activate(_ item: MenuItem) {
        if item != .searching { Sound.shared.play("menu-select", volume: 0.7) }
        switch item {
        case .play where !UserDefaults.standard.bool(forKey: "seenStory"):
            UserDefaults.standard.set(true, forKey: "seenStory")
            openStory()
        case .play, .resume:
            screen = .playing
            syncCamera()
            if !UserDefaults.standard.bool(forKey: "seenWeapons") {
                UserDefaults.standard.set(true, forKey: "seenWeapons")
                show("New! Wolfie Military weapons are in your backpack. Press \(keyboardMode ? "I" : Btn.triangle)")
            }
            #if os(macOS)
            input.capturePointer()
            #endif
        case .settings:
            menuReturn = screen
            screen = .settings
            menuIndex = 0
        case .controls:
            menuReturn = screen
            screen = .controls
            menuIndex = 0
        case .quitToTitle:
            leaveSpaceQuietly()
            save()
            endSession()
            screen = .title
            menuIndex = 0
        case .lookSpeed:
            let settings = GameSettings.shared
            settings.lookSpeed = (settings.lookSpeed + 1) % 3
        case .invertLook, .speakNames:
            adjust(item, by: 1)
        case .viewDistance:
            let settings = GameSettings.shared
            settings.viewDistance = (settings.viewDistance + 1) % 4
            applyViewDistance()
        case .restartPlanet:
            if confirmingRestart {
                confirmingRestart = false
                restartPlanet()
            } else {
                confirmingRestart = true
            }
        case .back:
            goBack()
        case .friends:
            menuReturn = screen
            screen = .friends
            menuIndex = 0
            startLooking()
        case .hostGame:
            hostGame()
        case .join(let name):
            join(named: name)
        case .searching:
            break
        case .yourName, .yourColor, .soundEffects:
            adjust(item, by: 1)
        case .danger:
            let settings = GameSettings.shared
            settings.danger = (settings.danger + 1) % 3
            dangerChanged()
        case .backpackMode:
            adjust(item, by: 1)
        case .critterBook:
            menuReturn = screen
            screen = .critterBook
            menuIndex = 0
        case .map:
            openMap()
        case .goTo(let id):
            fastTravel(to: id)
        case .goToPlace(let name):
            if let landmark = Landmark(rawValue: name) { fastTravel(to: landmark) }
        case .music:
            let settings = GameSettings.shared
            settings.musicLevel = (settings.musicLevel + 1) % 4
            Sound.shared.applyVolumes()
        case .crew:
            openCrewPicker()
        case .story:
            openStory()
        case .cameraView, .voices:
            adjust(item, by: 1)
        }
    }

    private func goBack() {
        confirmingRestart = false
        switch screen {
        case .settings, .controls, .critterBook:
            let from: MenuItem = screen == .settings ? .settings : (screen == .controls ? .controls : .critterBook)
            screen = menuReturn
            menuIndex = menuItems.firstIndex(of: from) ?? 0
        case .map:
            closeMap()
        case .friends:
            stopLooking()
            screen = menuReturn
            menuIndex = menuItems.firstIndex(of: .friends) ?? 0
        case .paused:
            activate(.resume)
        case .crew:
            closeCrewPicker()
        case .story:
            closeStory()
        default:
            break
        }
    }

    func pause() {
        guard screen == .playing else { return }
        showHelp = false
        Sound.shared.stopLoop(channel: "engine")
        screen = .paused
        menuIndex = 0
        highlight.isEnabled = false
        hideLaser()
    }

    /// Apple TV's Menu button, and the on-screen pause button.
    func handleBackButton() {
        switch screen {
        case .playing: pause()
        case .starMap: closeStarMap()
        case .backpack: closeBackpack()
        default: goBack()
        }
    }

    /// Throws away this planet's saved world and makes a fresh one.
    private func restartPlanet() {
        WorldStore.delete(planet: planet.id)
        glitch.reset(planet: planet.id)
        forgetSpots()
        world = World(planet: planet)
        player = Player(position: world.spawnPoint())
        applyPlanet()
        save()
        screen = .playing
        show("\(planet.name) is brand new")
    }

    /// Behind the title screen, the camera circles slowly over the world.
    private func orbitCamera(dt: Float) {
        let center = world.spawnPoint() + SIMD3<Float>(0, 4, 0)
        let angle = clock * 0.08
        let eye = center + SIMD3<Float>(sin(angle) * 30, 14, cos(angle) * 30)
        let d = simd_normalize(center - eye)
        let yaw = atan2(-d.x, -d.z)
        let pitch = asin(d.y)
        camera.position = eye
        camera.orientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0)) * simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
        followCamera(eye)
    }

    // MARK: Sounds

    /// Footsteps, jumps and landings.
    private func playMovementSounds(dt: Float, wasOnGround: Bool, wasFlying: Bool, fallSpeed: Float) {
        let sound = Sound.shared
        if wasOnGround && !player.onGround && player.velocity.y > 1 && !player.flying {
            sound.playVaried("jump", volume: 0.5)
        }
        if !wasOnGround && player.onGround && fallSpeed < -7 {
            sound.playVaried("land", volume: min(1, -fallSpeed / 20))
            stepDistance = 0
        }
        if wasFlying && !player.flying && player.onGround {
            sound.play("fly-off", volume: 0.5)
        }
        if player.onGround && !player.flying {
            let speed = simd_length(SIMD2<Float>(player.velocity.x, player.velocity.z))
            stepDistance += speed * dt
            if stepDistance > 2.1 {
                stepDistance = 0
                sound.playVaried("step-\(Int.random(in: 1...3))", volume: 0.3, spread: 0.12)
            }
        }
    }

    /// Title music on the title screens, the planet's music everywhere else.
    private func updateMusic() {
        let onTitle = screen == .title || (menuReturn == .title && (screen == .settings || screen == .controls || screen == .friends))
        Sound.shared.playMusic((onTitle && travelText == nil) || place == .space ? "music-title" : "music-\(planet.id)")
    }

    // MARK: Hotbar

    func selectSlot(_ index: Int) {
        guard index != hotbarIndex, hotbar.indices.contains(index) else { return }
        hotbarIndex = index
        holsterWeapon()
        Sound.shared.play("hotbar")
        Speaker.shared.say(ItemCatalog.shared.name(hotbar[index]))
    }

    // MARK: Saving

    func save() {
        // A friend's world belongs to the host; it's saved on their device.
        guard session != .joined else { return }
        saveOtherWorlds()
        rememberSpots()
        do {
            let file = SaveFile(
                version: SaveFile.currentVersion,
                planet: planet.id,
                seed: world.seed,
                height: World.height,
                edits: try world.compressedEdits(),
                player: [player.position.x, player.position.y, player.position.z, player.yaw, player.pitch, player.flying ? 1 : 0],
                hotbarIndex: hotbarIndex
            )
            try WorldStore.save(file, planet: planet.id)
            WorldStore.lastPlanet = planet.id
            show("World saved")
        } catch {
            show("Couldn't save the world: \(error.localizedDescription)")
        }
    }

    func show(_ text: String) {
        message = text
        messageTimer = 2.5
    }

    // MARK: Helpers

    private static func color(_ c: SIMD3<Float>) -> PlatformColor {
        PlatformColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }

    private static func glow(_ c: SIMD3<Float>, opacity: Float) -> UnlitMaterial {
        var material = UnlitMaterial(color: color(c))
        if opacity < 1 {
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        return material
    }

    /// See-through sky-coloured material for the haze shells, visible from inside.
    private static func haze(_ c: SIMD3<Float>, opacity: Float) -> UnlitMaterial {
        var material = UnlitMaterial(color: color(c))
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        material.faceCulling = .none
        return material
    }

    /// A few hundred tiny cubes far away, shown on planets with a dark sky.
    private static func makeStars() -> ModelEntity {
        var builder = MeshBuilder()
        let noise = Noise(seed: 99)
        for i in 0..<420 {
            let u = noise.hash(i, 1) * 2 - 1
            let theta = noise.hash(i, 2) * 2 * Float.pi
            let r = (1 - u * u).squareRoot()
            let direction = SIMD3<Float>(r * cos(theta), abs(u) * 0.9 + 0.05, r * sin(theta))
            let center = simd_normalize(direction) * Game.skyRadius * 0.9
            let size: Float = (0.8 + noise.hash(i, 3) * 1.4) * 6
            for face in VoxelMesher.faces {
                builder.addFace(face, at: center - SIMD3<Float>(repeating: size / 2), u: 0.5, size: size)
            }
        }
        let entity = ModelEntity()
        if let mesh = try? builder.mesh(name: "stars") {
            entity.model = ModelComponent(mesh: mesh, materials: [UnlitMaterial(color: .white)])
        }
        return entity
    }

    /// A band of the sky dome from straight down up to a little above the horizon, radius 1.
    private static func hazeMesh(topDegrees: Float) -> MeshResource? {
        let latitudes: [Float] = [-90, -60, -35, -18, -8, -3, 0, topDegrees]
        let segments = 48
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for lat in latitudes {
            let a = lat * .pi / 180
            for k in 0...segments {
                let b = Float(k) / Float(segments) * 2 * .pi
                let p = SIMD3<Float>(cos(a) * cos(b), sin(a), cos(a) * sin(b))
                positions.append(p)
                normals.append(-p)
            }
        }
        let row = UInt32(segments + 1)
        for r in 0..<UInt32(latitudes.count - 1) {
            for k in 0..<UInt32(segments) {
                let a = r * row + k
                let b = a + row
                indices.append(contentsOf: [a, b, a + 1, a + 1, b, b + 1])
            }
        }
        var descriptor = MeshDescriptor(name: "haze")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}
