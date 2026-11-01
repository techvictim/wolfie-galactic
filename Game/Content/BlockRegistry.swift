import Foundation
import simd

/// Block ids used by world generation. Names and colours live in Resources/blocks.json.
enum B {
    static let air: UInt8 = 0
    static let grass: UInt8 = 1
    static let soil: UInt8 = 2
    static let rock: UInt8 = 3
    static let sand: UInt8 = 4
    static let wood: UInt8 = 5
    static let leaves: UInt8 = 6
    static let planks: UInt8 = 7
    static let glass: UInt8 = 8
    static let metal: UInt8 = 9
    static let crystal: UInt8 = 10
    static let lamp: UInt8 = 11
    static let crate: UInt8 = 12
    static let wolfieMoss: UInt8 = 13
    static let violetSoil: UInt8 = 14
    static let alienRock: UInt8 = 15
    static let glowStalk: UInt8 = 16
    static let glowcap: UInt8 = 17
    static let moonDust: UInt8 = 18
    static let moonRock: UInt8 = 19
    static let rustSand: UInt8 = 20
    static let ice: UInt8 = 21
    /// Not a block: the laser blaster, used in the hotbar.
    static let laser: UInt8 = 255
}

struct BlockDef: Codable {
    let id: UInt8
    let name: String
    let color: String
    /// Where to find it, for the backpack.
    var find: String?
}

struct ContentPack: Codable {
    let blocks: [BlockDef]
    let hotbar: [UInt8]
}

/// Loads the block content pack (Resources/blocks.json).
/// Add a block by adding an entry there; ids go up to 63.
final class BlockRegistry {
    static let shared = BlockRegistry()
    static let maxBlocks = 64

    private(set) var defs: [UInt8: BlockDef] = [:]
    private(set) var hotbar: [UInt8] = []

    private init() {
        var pack = ContentPack(blocks: [BlockDef(id: 1, name: "Grass", color: "#6cc24a")], hotbar: [1])
        if let url = Bundle.main.url(forResource: "blocks", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(ContentPack.self, from: data) {
            pack = decoded
        }
        for def in pack.blocks where Int(def.id) < BlockRegistry.maxBlocks {
            defs[def.id] = def
        }
        hotbar = pack.hotbar.filter { defs[$0] != nil || $0 == B.laser }
        if hotbar.isEmpty { hotbar = [1] }
    }

    /// Every block id defined in blocks.json, in order.
    var allIDs: [UInt8] {
        defs.keys.sorted()
    }

    func findHint(_ id: UInt8) -> String? {
        defs[id]?.find
    }

    func name(_ id: UInt8) -> String {
        if id == B.laser { return "Laser" }
        return defs[id]?.name ?? "Block"
    }

    /// Linear 0...1 RGB (sRGB-encoded values) for a block.
    func rgb(_ id: UInt8) -> SIMD3<Float> {
        guard let hex = defs[id]?.color else { return SIMD3<Float>(1, 0, 1) }
        return BlockRegistry.parseHex(hex)
    }

    static func parseHex(_ hex: String) -> SIMD3<Float> {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return SIMD3<Float>(1, 0, 1) }
        let r = Float((v >> 16) & 0xFF) / 255
        let g = Float((v >> 8) & 0xFF) / 255
        let b = Float(v & 0xFF) / 255
        return SIMD3<Float>(r, g, b)
    }
}
