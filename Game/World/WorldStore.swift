import Foundation

/// A saved world. The same file is what you'll share with friends later.
/// Worlds are endless and rebuilt from the planet's seed, so only changed chunks are stored.
struct SaveFile: Codable {
    static let currentVersion = 2

    var version: Int
    /// Which planet this world belongs to.
    var planet: String
    var seed: UInt64
    var height: Int
    /// Changed chunks, keyed "x,z", each LZFSE-compressed.
    var edits: [String: Data]
    /// Player feet position (x, y, z), yaw, pitch, then 1 if flying.
    var player: [Float]
    var hotbarIndex: Int
}

enum WorldStore {
    static var folder: URL {
        #if os(tvOS)
        // Apple TV has no permanent app storage; caches can be cleared by the system.
        // Phase 4 moves Apple TV saves to iCloud.
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        #else
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #endif
        return base.appendingPathComponent("WolfieGalactic", isDirectory: true)
    }

    /// One saved world per planet.
    static func worldURL(planet: String) -> URL {
        folder.appendingPathComponent("\(planet).wgworld")
    }

    static func save(_ file: SaveFile, planet: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(file)
        try data.write(to: worldURL(planet: planet), options: .atomic)
    }

    static func load(planet: String) -> SaveFile? {
        guard let data = try? Data(contentsOf: worldURL(planet: planet)) else { return nil }
        return try? PropertyListDecoder().decode(SaveFile.self, from: data)
    }

    static func delete(planet: String) {
        try? FileManager.default.removeItem(at: worldURL(planet: planet))
    }

    /// The planet you were on last time.
    static var lastPlanet: String? {
        get { UserDefaults.standard.string(forKey: "lastPlanet") }
        set { UserDefaults.standard.set(newValue, forKey: "lastPlanet") }
    }

    static func compress(_ data: Data) throws -> Data {
        try (data as NSData).compressed(using: .lzfse) as Data
    }

    static func decompress(_ data: Data) throws -> Data {
        try (data as NSData).decompressed(using: .lzfse) as Data
    }
}
