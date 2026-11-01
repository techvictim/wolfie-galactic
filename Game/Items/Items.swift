import Foundation
import simd

/// Something you can hold, carry in your backpack, make, and use.
enum Item: Hashable, Sendable {
    case laser
    /// A block, including machines (jump pads, teleporters…).
    case block(UInt8)
    /// A pre-made build from builds.json.
    case build(String)
    case vehicle(VehicleKind)
    /// A Wolfie Military weapon from weapons.json.
    case weapon(String)

    /// "laser", "block:7", "build:house", "vehicle:rover"
    var key: String {
        switch self {
        case .laser: return "laser"
        case .block(let id): return "block:\(id)"
        case .build(let id): return "build:\(id)"
        case .vehicle(let kind): return "vehicle:\(kind.rawValue)"
        case .weapon(let id): return "weapon:\(id)"
        }
    }

    init?(key: String) {
        if key == "laser" { self = .laser; return }
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "block": guard let id = UInt8(parts[1]) else { return nil }; self = .block(id)
        case "build": self = .build(parts[1])
        case "vehicle": guard let kind = VehicleKind(rawValue: parts[1]) else { return nil }; self = .vehicle(kind)
        case "weapon": guard Arsenal.shared.weapon(parts[1]) != nil else { return nil }; self = .weapon(parts[1])
        default: return nil
        }
    }

    var isVehicle: Bool {
        if case .vehicle = self { return true }
        return false
    }

    /// The laser and weapons: always yours, never used up.
    var isTool: Bool {
        switch self {
        case .laser, .weapon: return true
        default: return false
        }
    }

    var weapon: WeaponDef? {
        if case .weapon(let id) = self { return Arsenal.shared.weapon(id) }
        return nil
    }

    var isMachine: Bool {
        if case .block(let id) = self { return Machine(rawValue: id) != nil }
        return false
    }
}

/// Blocks that do something when you step on them.
enum Machine: UInt8, CaseIterable {
    /// Bounces you high into the air.
    case jumpPad = 31
    /// Takes you to the nearest other teleporter.
    case teleporter = 32
    /// Zooms you forward.
    case speedPad = 33
    /// Makes a crystal every little while.
    case crystalMaker = 34

    var help: String {
        switch self {
        case .jumpPad: return "Step on it to bounce sky-high"
        case .teleporter: return "Place two; step on one to zap to the other"
        case .speedPad: return "Step on it to zoom forward"
        case .crystalMaker: return "Makes a crystal every few seconds"
        }
    }
}

/// The tabs in the backpack.
enum ItemGroup: Int, CaseIterable {
    case weapons, blocks, builds, vehicles, machines

    var title: String {
        switch self {
        case .weapons: return "Weapons"
        case .blocks: return "Blocks"
        case .builds: return "Builds"
        case .vehicles: return "Vehicles"
        case .machines: return "Machines"
        }
    }

    var symbol: String {
        switch self {
        case .weapons: return "scope"
        case .blocks: return "cube.fill"
        case .builds: return "house.fill"
        case .vehicles: return "car.fill"
        case .machines: return "gearshape.2.fill"
        }
    }
}

/// A pre-made build: a list of simple shapes made of blocks.
struct BuildDef: Codable, Sendable {
    struct Part: Codable, Sendable {
        /// box, walls, frame, roof, dome or column.
        let shape: String
        let from: [Int]
        let to: [Int]
        let block: UInt8
    }

    let id: String
    let name: String
    let size: [Int]
    let parts: [Part]

    /// Every block, in the build's own grid (x across, y up, z away from you).
    func blocks() -> [(SIMD3<Int>, UInt8)] {
        var grid: [SIMD3<Int>: UInt8] = [:]
        for part in parts where part.from.count == 3 && part.to.count == 3 {
            let a = SIMD3<Int>(min(part.from[0], part.to[0]), min(part.from[1], part.to[1]), min(part.from[2], part.to[2]))
            let b = SIMD3<Int>(max(part.from[0], part.to[0]), max(part.from[1], part.to[1]), max(part.from[2], part.to[2]))
            for y in a.y...b.y {
                for z in a.z...b.z {
                    for x in a.x...b.x where BuildDef.inside(part.shape, x, y, z, a, b) {
                        grid[SIMD3(x, y, z)] = part.block
                    }
                }
            }
        }
        return grid.map { ($0.key, $0.value) }
    }

    private static func inside(_ shape: String, _ x: Int, _ y: Int, _ z: Int, _ a: SIMD3<Int>, _ b: SIMD3<Int>) -> Bool {
        let onX = x == a.x || x == b.x, onY = y == a.y || y == b.y, onZ = z == a.z || z == b.z
        switch shape {
        case "walls":
            return onX || onZ
        case "frame":
            return [onX, onY, onZ].filter { $0 }.count >= 2
        case "roof":
            let k = y - a.y
            return x >= a.x + k && x <= b.x - k && z >= a.z + k && z <= b.z - k
        case "dome":
            let cx = Float(a.x + b.x) / 2, cz = Float(a.z + b.z) / 2
            let rx = Float(b.x - a.x) / 2 + 0.5, rz = Float(b.z - a.z) / 2 + 0.5, ry = Float(b.y - a.y) + 0.5
            let dx = (Float(x) - cx) / rx, dz = (Float(z) - cz) / rz, dy = Float(y - a.y) / ry
            let d = dx * dx + dy * dy + dz * dz
            let inner = (dx * dx) * pow(rx / (rx - 1), 2) + (dy * dy) * pow(ry / (ry - 1), 2) + (dz * dz) * pow(rz / (rz - 1), 2)
            return d <= 1 && inner > 1
        case "column":
            let cx = Float(a.x + b.x) / 2, cz = Float(a.z + b.z) / 2
            let r = Float(min(b.x - a.x, b.z - a.z)) / 2 + 0.5
            let dx = Float(x) - cx, dz = Float(z) - cz
            return dx * dx + dz * dz <= r * r
        default:
            return true
        }
    }
}

/// One way of making something.
struct Recipe: Sendable {
    let makes: Item
    let count: Int
    let needs: [(Item, Int)]
}

/// Builds and recipes, from Resources/builds.json and Resources/recipes.json.
@MainActor
final class ItemCatalog {
    static let shared = ItemCatalog()

    let builds: [BuildDef]
    let recipes: [Recipe]
    let starter: [String: Int]
    let startingHotbar: [Item]

    private struct BuildsFile: Codable { let builds: [BuildDef] }
    private struct RecipeEntry: Codable { let makes: String; let count: Int; let needs: [String: Int] }
    private struct RecipesFile: Codable {
        let recipes: [RecipeEntry]
        let starter: [String: Int]?
        let hotbar: [String]?
    }

    private init() {
        func load<T: Decodable>(_ name: String, _ type: T.Type) -> T? {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        }
        builds = load("builds", BuildsFile.self)?.builds ?? []
        let file = load("recipes", RecipesFile.self)
        recipes = (file?.recipes ?? []).compactMap { entry in
            guard let makes = Item(key: entry.makes) else { return nil }
            let needs = entry.needs.compactMap { key, count in Item(key: key).map { ($0, count) } }
                .sorted { $0.0.key < $1.0.key }
            return Recipe(makes: makes, count: entry.count, needs: needs)
        }
        starter = file?.starter ?? [:]
        let hotbar = (file?.hotbar ?? []).compactMap(Item.init(key:))
        startingHotbar = hotbar.isEmpty ? [.laser] : hotbar
    }

    func build(_ id: String) -> BuildDef? {
        builds.first { $0.id == id }
    }

    func recipes(for item: Item) -> [Recipe] {
        recipes.filter { $0.makes == item }
    }

    func name(_ item: Item) -> String {
        switch item {
        case .laser: return "Laser"
        case .block(let id): return BlockRegistry.shared.name(id)
        case .build(let id): return build(id)?.name ?? "Build"
        case .vehicle(let kind): return kind.displayName
        case .weapon(let id): return Arsenal.shared.weapon(id)?.name ?? "Weapon"
        }
    }

    /// Everything that belongs on a backpack tab, whether you have it yet or not.
    func catalog(_ group: ItemGroup) -> [Item] {
        switch group {
        case .weapons:
            return [.laser] + Arsenal.shared.weapons.map { .weapon($0.id) }
        case .blocks:
            // Blocks you can find in the world or make, but not machines.
            return BlockRegistry.shared.allIDs
                .filter { Machine(rawValue: $0) == nil && !GlitchNest.isGlitch($0) }
                .map { Item.block($0) }
        case .builds:
            return builds.map { .build($0.id) }
        case .vehicles:
            return [VehicleKind.hoverbike, .buggy, .rover, .zoomer, .comet, .hauler, .starship].map { .vehicle($0) }
        case .machines:
            return Machine.allCases.map { .block($0.rawValue) }
        }
    }
}

extension VehicleKind {
    /// Its name with a capital, for the backpack.
    var displayName: String {
        switch self {
        case .rover: return "Rover"
        case .starship: return "Starship"
        case .buggy: return "Moon Buggy"
        case .hoverbike: return "Hover Bike"
        default: return name
        }
    }
}
