import Foundation

/// A connection to one other player, over Wi-Fi (PeerLink) or the internet (CloudRoom).
@MainActor
protocol FriendLink: AnyObject {
    var onReady: (() -> Void)? { get set }
    var onMessage: ((NetMessage) -> Void)? { get set }
    var onClose: (() -> Void)? { get set }
    func start()
    func send(_ message: NetMessage)
    func close()
}

extension PeerLink: FriendLink {}

/// Playing with a friend somewhere else, with an invite code, the way Wolfie Military does it:
///  - the host makes a room and gets a short code (like COMET-42) to tell the other grown-up
///  - the friend picks the code; the host is asked "Nova wants to join. OK?" and nothing connects
///    until yes
///  - a code works for one friend; the host gets a new one for the next. Nothing personal is
///    sent, just the name picked in the game, where you are and what you build.
///
/// It uses Wolfie Military's room layout (its database.rules.json):
///   rooms/CODE: { host, ver, created, open, guest?, hostChar, req/{uid}: {char, ver, ok?},
///                 st/{uid}: "json", ev/{id}: {u, k, d} }
/// Messages go as events (ev), batched every tenth of a second and split if they're big;
/// positions go in each player's state (st), which also says "still here".
@MainActor
final class CloudRoom: FriendLink {
    enum Role { case host, guest }

    var onReady: (() -> Void)?
    var onMessage: ((NetMessage) -> Void)?
    var onClose: (() -> Void)?
    /// Host only: someone asks to join (their uid and name).
    var onRequest: ((String, String) -> Void)?

    let role: Role
    private(set) var code: String
    private(set) var peer: String?
    private(set) var isClosed = false
    private var connected = false

    private let cloud = Cloud.shared
    private var listener: Task<Void, Never>?
    private var pump: Task<Void, Never>?
    private var outbox: [String] = []
    private var poses: [Int: String] = [:]
    private var posesChanged = false
    private var lastStateSent = Date.distantPast
    private var lastHeard = Date()
    private var seen = Set<String>()
    private var parts: [String: [Int: String]] = [:]
    private var asked = Set<String>()
    private var nextMessage = 0

    static let words = ["WOLF", "COMET", "ROCKET", "PLANET", "STAR", "MOON", "NOVA", "ORBIT", "GALAXY", "LASER",
                        "ROBOT", "GECKO", "METEOR", "NEBULA", "PUPPY", "ZOOM", "TURBO", "BLAST", "SPACE", "JET"]
    static var version: String { "wg-\(Net.version)" }
    /// Wolfie Military's rules: a code works for 10 minutes; we freshen it before that.
    private static let renewEvery: TimeInterval = 8 * 60
    private static let eventLimit = 100_000
    private static let stateLimit = 1_900
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func pretty(_ code: String) -> String {
        code.replacingOccurrences(of: #"^([A-Z]+)(\d+)$"#, with: "$1-$2", options: .regularExpression)
    }

    private var room: String { "rooms/\(code)" }

    private init(role: Role, code: String) {
        self.role = role
        self.code = code
    }

    // MARK: Hosting

    /// Make a room with a fresh code. Nobody can take over someone else's room, so a code
    /// that's in use is simply refused, and another is tried.
    static func host(name: String) async throws -> CloudRoom {
        var last: Error = Cloud.CloudError.server("Couldn't make a code")
        for _ in 0..<6 {
            let code = words.randomElement()! + String(Int.random(in: 10...99))
            let room = CloudRoom(role: .host, code: code)
            do {
                let uid = try await room.signedIn()
                try await Cloud.shared.put("rooms/\(code)", [
                    "host": uid, "ver": version, "created": Cloud.now, "open": true, "hostChar": String(name.prefix(23)),
                ] as [String: Any])
                room.listenForRequests()
                return room
            } catch {
                last = error
                if case Cloud.CloudError.denied = error { continue }
                throw error
            }
        }
        throw last
    }

    private func signedIn() async throws -> String {
        _ = try await cloud.token()
        guard let uid = cloud.uid else { throw Cloud.CloudError.server("Couldn't sign in") }
        return uid
    }

    /// Host: wait for someone to ask, and keep the code fresh.
    private func listenForRequests() {
        listener = Task { [weak self] in
            guard let self else { return }
            let stream = self.cloud.listen(self.room)
            Task { [weak self] in
                var renewed = Date()
                while let self, !self.isClosed, !self.connected {
                    try? await Task.sleep(nanoseconds: 20_000_000_000)
                    if Date().timeIntervalSince(renewed) > CloudRoom.renewEvery {
                        renewed = Date()
                        try? await self.cloud.patch(self.room, ["created": Cloud.now])
                    }
                }
            }
            do {
                for try await change in stream {
                    if self.isClosed { break }
                    self.handle(change)
                }
            } catch {}
            if !self.isClosed { self.finish() }
        }
    }

    /// Host: let them in.
    func approve(_ uid: String) async throws {
        try await cloud.patch(room, ["guest": uid, "open": false])
        try await cloud.patch("\(room)/req/\(uid)", ["ok": true])
        peer = uid
        becomeConnected()
    }

    /// Host: say no.
    func decline(_ uid: String) {
        Task { try? await cloud.patch("\(room)/req/\(uid)", ["ok": false]) }
    }

    // MARK: Joining

    enum JoinError: Error, LocalizedError {
        case noRoom, saidNo, version, noAnswer
        var errorDescription: String? {
            switch self {
            case .noRoom: return "No game with that code. Check it and try again"
            case .saidNo: return "They said not this time"
            case .version: return "Update Wolfie Galactic on both devices to play together"
            case .noAnswer: return "Nobody answered. Try again?"
            }
        }
    }

    /// Ask to join a room, and wait (up to 3 minutes) for the host to say yes.
    static func join(code: String, name: String) async throws -> CloudRoom {
        let room = CloudRoom(role: .guest, code: code)
        let uid = try await room.signedIn()
        let request = "rooms/\(code)/req/\(uid)"
        do {
            try await Cloud.shared.put(request, ["char": String(name.prefix(23)), "ver": version] as [String: Any])
        } catch Cloud.CloudError.denied {
            throw JoinError.noRoom
        }
        let started = Date()
        while Date().timeIntervalSince(started) < 180 {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let answer = (try? await Cloud.shared.get(request)) as? [String: Any]
            if let ok = answer?["ok"] {
                if let yes = ok as? Bool {
                    guard yes else { throw JoinError.saidNo }
                    room.peer = "host"
                    return room
                }
                throw JoinError.version
            }
        }
        try? await Cloud.shared.delete(request)
        throw JoinError.noAnswer
    }

    /// Guest: stop waiting.
    static func cancelJoin(code: String) {
        guard let uid = Cloud.shared.uid else { return }
        Task { try? await Cloud.shared.delete("rooms/\(code)/req/\(uid)") }
    }

    // MARK: Connected

    func start() {
        if role == .guest { becomeConnected() }
        // The host's room is already listening; it connects on approve().
    }

    private func becomeConnected() {
        guard !connected, !isClosed else { return }
        connected = true
        lastHeard = Date()
        if role == .guest {
            listener = Task { [weak self] in
                guard let self else { return }
                do {
                    for try await change in self.cloud.listen(self.room) {
                        if self.isClosed { break }
                        self.handle(change)
                    }
                } catch {}
                if !self.isClosed { self.finish() }
            }
        }
        pump = Task { [weak self] in
            while let self, !self.isClosed {
                await self.flush()
                // Gone quiet for too long (switched off, out of range): they've left.
                if Date().timeIntervalSince(self.lastHeard) > 20 {
                    self.finish()
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        onReady?()
    }

    func send(_ message: NetMessage) {
        guard !isClosed, let data = try? CloudRoom.encoder.encode(message), let json = String(data: data, encoding: .utf8) else { return }
        if case let .pose(id, _) = message {
            poses[id] = json
            posesChanged = true
        } else {
            outbox.append(json)
        }
    }

    func close() {
        guard !isClosed else { return }
        let room = self.room
        let role = self.role
        Task {
            if role == .host {
                try? await Cloud.shared.delete(room)
            } else {
                try? await Cloud.shared.delete("\(room)/guest")
            }
        }
        finish()
    }

    private func finish() {
        guard !isClosed else { return }
        isClosed = true
        listener?.cancel()
        pump?.cancel()
        onClose?()
    }

    // MARK: Sending

    private func flush() async {
        guard let uid = cloud.uid else { return }
        if !outbox.isEmpty {
            let batch = "[" + outbox.joined(separator: ",") + "]"
            outbox.removeAll()
            if batch.count <= CloudRoom.eventLimit {
                try? await cloud.post("\(room)/ev", ["u": uid, "k": "m", "d": batch])
            } else {
                // Big (a whole planet's building): in pieces, put back together at the other end.
                nextMessage += 1
                let id = "\(nextMessage)"
                let chars = Array(batch)
                let size = CloudRoom.eventLimit - 40
                let count = (chars.count + size - 1) / size
                for i in 0..<count {
                    let piece = String(chars[(i * size)..<min(chars.count, (i + 1) * size)])
                    try? await cloud.post("\(room)/ev", ["u": uid, "k": "p", "d": "\(id)|\(i)|\(count)|" + piece])
                }
            }
        }
        // Where everyone is, at most about 7 times a second; and every few seconds anyway, so
        // the other side knows we're still here.
        let since = Date().timeIntervalSince(lastStateSent)
        if (posesChanged && since > 0.14) || since > 3 {
            posesChanged = false
            lastStateSent = Date()
            var list: [String] = []
            var length = 2
            for json in poses.values where length + json.count + 1 < CloudRoom.stateLimit {
                list.append(json)
                length += json.count + 1
            }
            let state = "[" + list.joined(separator: ",") + "]"
            try? await cloud.put("\(room)/st/\(uid)", state)
        }
    }

    // MARK: Receiving

    private func handle(_ change: Cloud.Change) {
        let path = change.path.split(separator: "/").map(String.init)
        if path.isEmpty {
            // The whole room (first thing, and after reconnecting).
            guard let all = change.data as? [String: Any] else {
                if !change.patch { finish() }    // the room is gone
                return
            }
            if role == .host && connected && all["guest"] == nil { finish(); return }
            if let req = all["req"] as? [String: Any] { for (k, v) in req { request(k, v) } }
            if let ev = all["ev"] as? [String: Any] { for k in ev.keys.sorted() { event(k, ev[k]) } }
            if let st = all["st"] as? [String: Any] { for (k, v) in st { state(k, v) } }
            return
        }
        let top = path[0]
        if path.count == 1 {
            // A whole branch, or a patch into it.
            switch top {
            case "guest":
                if role == .host && connected && change.data == nil { finish() }
            case "req", "ev", "st":
                guard let children = change.data as? [String: Any] else { return }
                for k in children.keys.sorted() {
                    switch top {
                    case "req": request(k, children[k])
                    case "ev": event(k, children[k])
                    default: state(k, children[k])
                    }
                }
            default:
                break
            }
            return
        }
        let key = path[1]
        switch top {
        case "req": if path.count == 2 { request(key, change.data) }
        case "ev": if path.count == 2 { event(key, change.data) }
        case "st": if path.count == 2 { state(key, change.data) }
        default: break
        }
    }

    private func request(_ uid: String, _ value: Any?) {
        guard role == .host, !connected, let r = value as? [String: Any], r["ok"] == nil, !asked.contains(uid) else { return }
        asked.insert(uid)
        guard (r["ver"] as? String) == CloudRoom.version else {
            Task { try? await cloud.patch("\(room)/req/\(uid)", ["ok": "version"]) }
            return
        }
        onRequest?(uid, (r["char"] as? String) ?? "A friend")
    }

    private func event(_ key: String, _ value: Any?) {
        guard connected, let e = value as? [String: Any], let from = e["u"] as? String, from != cloud.uid,
              let kind = e["k"] as? String, let d = e["d"] as? String, seen.insert(key).inserted else { return }
        lastHeard = Date()
        // Tidy up: the room only keeps what hasn't been read yet.
        Task { try? await cloud.delete("\(room)/ev/\(key)") }
        if kind == "p" {
            let bits = d.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
            guard bits.count == 4, let i = Int(bits[1]), let count = Int(bits[2]) else { return }
            let id = String(bits[0])
            parts[id, default: [:]][i] = String(bits[3])
            guard let got = parts[id], got.count == count else { return }
            parts[id] = nil
            deliver((0..<count).map { got[$0] ?? "" }.joined())
        } else {
            deliver(d)
        }
    }

    private func state(_ uid: String, _ value: Any?) {
        guard connected, uid != cloud.uid, let s = value as? String else { return }
        lastHeard = Date()
        deliver(s)
    }

    private func deliver(_ batch: String) {
        guard let data = batch.data(using: .utf8),
              let items = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return }
        for item in items {
            guard let one = try? JSONSerialization.data(withJSONObject: item),
                  let message = try? CloudRoom.decoder.decode(NetMessage.self, from: one) else { continue }
            onMessage?(message)
            if isClosed { return }
        }
    }
}
