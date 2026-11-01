import Foundation
import RealityKit
import simd

/// The backpack: what you've collected, what you hold, making new things, placing builds and
/// vehicles, picking up what you break, and machines that do things when you step on them.
extension Game {
    // MARK: Counting

    /// Settings › Backpack: Free build gives you everything, as many as you like.
    var freeBuild: Bool { GameSettings.shared.freeBuild }

    func count(_ item: Item) -> Int {
        item == .laser ? 1 : backpack[item.key] ?? 0
    }

    func has(_ item: Item) -> Bool {
        freeBuild || item == .laser || count(item) > 0
    }

    func add(_ item: Item, _ n: Int = 1) {
        guard item != .laser, n > 0 else { return }
        backpack[item.key, default: 0] += n
        saveBackpack()
    }

    /// Use one up. True if you had one (always, in Free build).
    @discardableResult
    func take(_ item: Item, _ n: Int = 1) -> Bool {
        if freeBuild || item == .laser { return true }
        guard count(item) >= n else { return false }
        backpack[item.key] = count(item) - n
        if backpack[item.key] == 0 { backpack[item.key] = nil }
        saveBackpack()
        return true
    }

    static func loadBackpack() -> [String: Int] {
        if let saved = UserDefaults.standard.dictionary(forKey: "backpack") as? [String: Int] { return saved }
        return ItemCatalog.shared.starter
    }

    func saveBackpack() {
        UserDefaults.standard.set(backpack, forKey: "backpack")
    }

    static func loadHotbar() -> [Item] {
        let saved = (UserDefaults.standard.stringArray(forKey: "hotbarItems") ?? []).compactMap(Item.init(key:))
        let items = saved.count == 6 ? saved : ItemCatalog.shared.startingHotbar
        return Array((items + Array(repeating: Item.block(7), count: 6)).prefix(6))
    }

    func saveHotbar() {
        UserDefaults.standard.set(hotbar.map(\.key), forKey: "hotbarItems")
    }

    var heldItem: Item { hotbar[hotbarIndex] }

    // MARK: Making things

    /// The first recipe for an item you have everything for.
    func affordableRecipe(_ item: Item) -> Recipe? {
        ItemCatalog.shared.recipes(for: item).first { recipe in
            recipe.needs.allSatisfy { count($0.0) >= $0.1 }
        }
    }

    /// Make one batch of an item from what's in your backpack.
    @discardableResult
    func make(_ item: Item) -> Bool {
        let catalog = ItemCatalog.shared
        guard !freeBuild else { return false }
        guard let recipe = affordableRecipe(item) else {
            if let recipe = catalog.recipes(for: item).first {
                let missing = recipe.needs.filter { count($0.0) < $0.1 }
                    .map { "\($0.1 - count($0.0)) more \(catalog.name($0.0))" }
                show("You need " + missing.joined(separator: " and "))
            } else {
                show("Find \(catalog.name(item)) out in the world")
            }
            Sound.shared.play("menu-move", pitch: 0.7)
            return false
        }
        for (need, n) in recipe.needs { take(need, n) }
        add(item, recipe.count)
        Sound.shared.play("craft", volume: 0.8)
        Voices.shared.say("up", chance: 0.5, cooldown: 15)
        show("Made \(recipe.count) \(catalog.name(item))!")
        return true
    }

    // MARK: The backpack screen

    func openBackpack() {
        guard screen == .playing, driving == nil, place == .surface else { return }
        screen = .backpack
        backpackIndex = 0
        hideLaser()
        highlight.isEnabled = false
        ghost.isEnabled = false
        Sound.shared.play("menu-select", volume: 0.6)
        #if os(macOS)
        input.releasePointer()
        #endif
    }

    func closeBackpack() {
        screen = .playing
        #if os(macOS)
        input.capturePointer()
        #endif
    }

    /// What shows on the current tab: everything, in Free build; otherwise what you have or can make.
    var backpackItems: [Item] {
        let catalog = ItemCatalog.shared
        return catalog.catalog(backpackTab).filter { item in
            freeBuild || count(item) > 0 || !catalog.recipes(for: item).isEmpty
        }
    }

    static let backpackColumns = 6

    func updateBackpack(_ frame: InputFrame) {
        if frame.cancel || frame.pause || frame.backpack {
            closeBackpack()
            return
        }
        if frame.hotbarStep != 0 {
            let all = ItemGroup.allCases
            let next = (backpackTab.rawValue + frame.hotbarStep + all.count) % all.count
            backpackTab = all[next]
            backpackIndex = 0
            Sound.shared.play("menu-move")
        }
        let items = backpackItems
        guard !items.isEmpty else { return }
        var index = min(backpackIndex, items.count - 1)
        if frame.menuStep != 0 { index = max(0, min(items.count - 1, index + frame.menuStep)) }
        if frame.menuMove != 0 { index = max(0, min(items.count - 1, index + frame.menuMove * Game.backpackColumns)) }
        if index != backpackIndex {
            backpackIndex = index
            Sound.shared.play("menu-move")
        }
        let item = items[index]
        if frame.action { make(item) }
        if frame.confirm { hold(item) }
    }

    func tapBackpack(_ index: Int) {
        let items = backpackItems
        guard items.indices.contains(index) else { return }
        if index == backpackIndex {
            hold(items[index])
        } else {
            backpackIndex = index
            Sound.shared.play("menu-move")
        }
    }

    /// Put an item in the hotbar slot you have selected, and get back to playing.
    func hold(_ item: Item) {
        if !has(item) && !make(item) { return }
        var bar = hotbar
        // Already in another slot? Just switch to that one.
        if let existing = bar.firstIndex(of: item) {
            hotbarIndex = existing
        } else {
            bar[hotbarIndex] = item
            hotbar = bar
            saveHotbar()
        }
        Speaker.shared.say(ItemCatalog.shared.name(item))
        Sound.shared.play("menu-select", volume: 0.7)
        closeBackpack()
    }

    // MARK: Breaking and picking up

    /// Breaking or blasting a block drops it, to collect.
    func dropPickup(_ id: UInt8, at center: SIMD3<Float>) {
        guard !freeBuild, id != B.air else { return }
        pickups.drop(id, at: center)
    }

    func updatePickups(dt: Float) {
        guard place == .surface else { return }
        let reach: Float = driving != nil ? 9 : 3.5
        let collector = player.position + SIMD3<Float>(0, driving != nil ? 1.5 : 1, 0)
        let got = pickups.update(dt: dt, collector: collector, reach: reach, world: world, clock: critterClock)
        for id in got {
            add(.block(id))
            pickupTally[id, default: 0] += 1
            Sound.shared.play("pickup", volume: 0.45, pitch: Float.random(in: 0.9...1.25))
        }
        // Say what you picked up, a moment after the last one.
        if !got.isEmpty { pickupTimer = 0.8 }
        if pickupTimer > 0 {
            pickupTimer -= dt
            if pickupTimer <= 0 && !pickupTally.isEmpty {
                let names = pickupTally.sorted { $0.value > $1.value }.prefix(3)
                    .map { "+\($0.value) \(BlockRegistry.shared.name($0.key))" }
                show(names.joined(separator: "  "))
                pickupTally = [:]
            }
        }
    }

    // MARK: Placing builds and vehicles

    /// Where a build goes: in front of you, facing away from you.
    private struct Placement {
        let anchor: SIMD3<Int>
        let forward: SIMD3<Int>
        let right: SIMD3<Int>

        func world(_ local: SIMD3<Int>, width: Int) -> SIMD3<Int> {
            anchor &+ right &* (local.x - width / 2) &+ SIMD3(0, local.y, 0) &+ forward &* local.z
        }
    }

    private func placement(for target: RayHit) -> Placement {
        let f = player.lookDirection
        let forward = abs(f.x) > abs(f.z) ? SIMD3<Int>(f.x > 0 ? 1 : -1, 0, 0) : SIMD3<Int>(0, 0, f.z > 0 ? 1 : -1)
        let right = SIMD3<Int>(-forward.z, 0, forward.x)
        // Sit on the ground: from the block you're looking at, the cell above it.
        var anchor = target.previous
        if target.previous.y > target.block.y { anchor = target.previous } else {
            anchor = SIMD3(target.previous.x, world.surfaceY(x: target.previous.x, z: target.previous.z), target.previous.z)
        }
        return Placement(anchor: anchor, forward: forward, right: right)
    }

    /// Show where a build or vehicle will go, as a see-through box.
    func updateGhost(target: RayHit?) {
        guard let target else {
            ghost.isEnabled = false
            return
        }
        switch heldItem {
        case .build(let id):
            guard let def = ItemCatalog.shared.build(id) else { ghost.isEnabled = false; return }
            let p = placement(for: target)
            let cells = def.blocks().map { p.world($0.0, width: def.size.first ?? 1) }
            guard let first = cells.first else { ghost.isEnabled = false; return }
            var lo = first, hi = first
            for c in cells { lo = simd_min(lo, c); hi = simd_max(hi, c) }
            let size = SIMD3<Float>(hi &- lo) + 1
            ghost.isEnabled = true
            ghost.position = SIMD3<Float>(lo) + size / 2
            ghost.scale = size + 0.04
            highlight.isEnabled = false
        case .vehicle(let kind):
            let p = placement(for: target)
            let size: SIMD3<Float> = kind.isShip ? SIMD3(8, 4, 8) : SIMD3(3, 2.5, 4)
            ghost.isEnabled = true
            ghost.position = SIMD3<Float>(Float(p.anchor.x) + 0.5, Float(p.anchor.y) + size.y / 2, Float(p.anchor.z) + 0.5)
            ghost.scale = size
            highlight.isEnabled = false
        default:
            ghost.isEnabled = false
        }
    }

    /// Left trigger with something in hand. Returns true if it was used.
    func placeHeld(target: RayHit, pressedNow: Bool) -> Bool {
        let item = heldItem
        switch item {
        case .laser:
            return false
        case .block(let id):
            let cell = target.previous
            guard world.inBounds(cell.x, cell.y, cell.z), world.block(cell) == B.air, !player.occupies(cell) else { return false }
            guard take(item) else {
                if pressedNow { outOf(item) }
                return false
            }
            changeBlock(cell, id)
            return true
        case .build(let id):
            guard pressedNow, let def = ItemCatalog.shared.build(id) else { return false }
            let p = placement(for: target)
            let width = def.size.first ?? 1
            let cells = def.blocks().map { (p.world($0.0, width: width), $0.1) }
            if cells.contains(where: { $0.1 != B.air && player.occupies($0.0) }) {
                show("Step back to make room")
                return false
            }
            guard take(item) else { outOf(item); return false }
            for (cell, block) in cells where cell.y > 0 && cell.y < World.height {
                changeBlock(cell, block)
            }
            effects.blockBurst(at: SIMD3<Float>(p.anchor) + SIMD3(0.5, 1, 0.5), blockColor: SIMD3(1, 0.9, 0.5))
            Sound.shared.play("craft", volume: 0.9)
            show("Built a \(def.name)!")
            return true
        case .vehicle(let kind):
            guard pressedNow else { return false }
            guard take(item) else { outOf(item); return false }
            let p = placement(for: target)
            var v = Vehicle(kind: kind, position: SIMD3<Float>(Float(p.anchor.x) + 0.5, 0, Float(p.anchor.z) + 0.5),
                            yaw: player.yaw, id: Vehicle.newID(kind))
            settle(&v)
            vehicles[v.id] = v
            showVehicles()
            rememberSpots()
            shareVehicle(v, on: planet.id, driver: nil)
            Sound.shared.play("vehicle-in", volume: 0.8)
            show("Your \(kind.displayName) is ready! Press \(keyboardMode ? "F" : "Y") to get in")
            return true
        }
    }

    private func outOf(_ item: Item) {
        let name = ItemCatalog.shared.name(item)
        let button = keyboardMode ? "I" : "X"
        show(affordableRecipe(item) != nil ? "Out of \(name). Make more in your backpack (\(button))" : "Out of \(name). Collect more!")
    }

    // MARK: Machines

    /// Step on a machine and it does its thing.
    func updateMachines(dt: Float) {
        machineCooldown = max(0, machineCooldown - dt)
        crystalTimer -= dt
        let feet = SIMD3<Int>(Int(floor(player.position.x)), Int(floor(player.position.y - 0.1)), Int(floor(player.position.z)))
        if player.onGround, machineCooldown <= 0, let machine = Machine(rawValue: world.block(feet)) {
            switch machine {
            case .jumpPad:
                player.velocity.y = 21
                player.onGround = false
                jumpPadClock = critterClock
                machineCooldown = 0.3
                Sound.shared.play("boing", volume: 0.8)
                Voices.shared.say("chute", chance: 0.6, cooldown: 10)
            case .speedPad:
                let forward = SIMD3<Float>(-sin(player.yaw), 0, -cos(player.yaw))
                player.knock(forward * 26 + SIMD3<Float>(0, 4, 0))
                machineCooldown = 0.5
                Sound.shared.play("zoom", volume: 0.8)
            case .teleporter:
                machineCooldown = 1.5
                let others = (world.machines[Machine.teleporter.rawValue] ?? []).filter { $0 != feet }
                guard let other = others.min(by: { simd_distance(SIMD3<Float>($0), player.position) < simd_distance(SIMD3<Float>($1), player.position) }) else {
                    show("Place another teleporter to link them")
                    break
                }
                effects.spark(at: player.position + SIMD3(0, 1, 0))
                player.position = SIMD3<Float>(Float(other.x) + 0.5, Float(other.y) + 1, Float(other.z) + 0.5)
                player.velocity = .zero
                syncCamera()
                effects.spark(at: player.position + SIMD3(0, 1, 0))
                Sound.shared.play("teleport", volume: 0.9)
            case .crystalMaker:
                break
            }
        }
        // Crystal makers near you pop out a crystal now and then.
        if crystalTimer <= 0 {
            crystalTimer = 10
            for cell in world.machines[Machine.crystalMaker.rawValue] ?? [] where simd_distance(SIMD3<Float>(cell), player.position) < 48 {
                dropPickup(B.crystal, at: SIMD3<Float>(cell) + SIMD3(0.5, 1.4, 0.5))
            }
        }
    }
}
