import Foundation

/// The online part of playing together: Firebase (the same project Wolfie Military uses for
/// "Play with a friend"), spoken to directly over HTTPS with no SDK. Anonymous sign-in, a
/// realtime database, and a live stream of changes (server-sent events).
///
/// The web API key comes from GitHub Secrets at build time (Info.plist WGFirebaseKey). Without
/// it, online play is simply off and Wi-Fi play still works.
@MainActor
final class Cloud {
    static let shared = Cloud()

    static let database = "https://wolfie-military-default-rtdb.firebaseio.com"
    private let apiKey = (Bundle.main.object(forInfoDictionaryKey: "WGFirebaseKey") as? String ?? "")
        .trimmingCharacters(in: .whitespaces)

    var available: Bool { !apiKey.isEmpty && !apiKey.hasPrefix("$(") }
    private(set) var uid: String?
    private var idToken: String?
    private var expires = Date.distantPast
    private var refreshing: Task<String, Error>?

    enum CloudError: Error, LocalizedError {
        case notSetUp, denied, server(String)
        var errorDescription: String? {
            switch self {
            case .notSetUp: return "Online play isn't set up in this build"
            case .denied: return "Not allowed"
            case let .server(m): return m
            }
        }
    }

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: c)
    }()
    /// Streams stay open for a long time.
    private let streamSession: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 60 * 60
        c.timeoutIntervalForResource = 24 * 60 * 60
        return URLSession(configuration: c)
    }()

    // MARK: Signing in

    /// A fresh ID token, signing in (anonymously) or refreshing as needed.
    func token() async throws -> String {
        guard available else { throw CloudError.notSetUp }
        if let idToken, Date() < expires { return idToken }
        if let refreshing { return try await refreshing.value }
        let task = Task { () throws -> String in
            defer { self.refreshing = nil }
            if let refresh = UserDefaults.standard.string(forKey: "cloudRefresh"), let t = try? await self.refresh(refresh) {
                return t
            }
            return try await self.signUp()
        }
        refreshing = task
        return try await task.value
    }

    private func signUp() async throws -> String {
        var req = URLRequest(url: URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=\(apiKey)")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["returnSecureToken": true])
        let json = try await object(for: req)
        guard let token = json["idToken"] as? String, let id = json["localId"] as? String else {
            throw CloudError.server(Cloud.message(json) ?? "Couldn't sign in")
        }
        signedIn(token: token, uid: id, refresh: json["refreshToken"] as? String, expiresIn: json["expiresIn"])
        return token
    }

    private func refresh(_ refresh: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://securetoken.googleapis.com/v1/token?key=\(apiKey)")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "grant_type=refresh_token&refresh_token=\(refresh)".data(using: .utf8)
        let json = try await object(for: req)
        guard let token = json["id_token"] as? String, let id = json["user_id"] as? String else {
            throw CloudError.server(Cloud.message(json) ?? "Couldn't sign in")
        }
        signedIn(token: token, uid: id, refresh: json["refresh_token"] as? String, expiresIn: json["expires_in"])
        return token
    }

    private func signedIn(token: String, uid id: String, refresh: String?, expiresIn: Any?) {
        idToken = token
        uid = id
        let seconds = Double("\(expiresIn ?? "3600")") ?? 3600
        expires = Date().addingTimeInterval(seconds - 300)
        if let refresh { UserDefaults.standard.set(refresh, forKey: "cloudRefresh") }
    }

    private func object(for req: URLRequest) async throws -> [String: Any] {
        let (data, _) = try await session.data(for: req)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private static func message(_ json: [String: Any]) -> String? {
        if let e = json["error"] as? [String: Any] { return e["message"] as? String }
        return json["error"] as? String
    }

    // MARK: The database

    private func url(_ path: String, token: String, extra: String = "") -> URL {
        URL(string: "\(Cloud.database)/\(path).json?auth=\(token)\(extra)")!
    }

    /// Read, write, add to or delete something in the database. Values are plain JSON.
    @discardableResult
    func call(_ method: String, _ path: String, _ value: Any? = nil) async throws -> Any? {
        let t = try await token()
        var req = URLRequest(url: url(path, token: t))
        req.httpMethod = method
        if let value {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        }
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        if status == 401 || status == 403 { throw CloudError.denied }
        guard (200..<300).contains(status) else {
            throw CloudError.server((json as? [String: Any]).flatMap(Cloud.message) ?? "Server said \(status)")
        }
        return json is NSNull ? nil : json
    }

    func get(_ path: String) async throws -> Any? { try await call("GET", path) }
    func put(_ path: String, _ value: Any) async throws { try await call("PUT", path, value) }
    func patch(_ path: String, _ value: [String: Any]) async throws { try await call("PATCH", path, value) }
    func post(_ path: String, _ value: Any) async throws { try await call("POST", path, value) }
    func delete(_ path: String) async throws { try await call("DELETE", path) }

    /// The server's clock, for "created" times.
    static let now: [String: Any] = [".sv": "timestamp"]

    // MARK: Listening

    /// A change under a path: where (relative to the path), and the new value there.
    struct Change {
        /// "put" replaces the value at `path`; "patch" merges each child of `data` into it.
        let patch: Bool
        let path: String
        let data: Any?
    }

    /// Every change under a path, live, starting with what's there now. Ends when the path
    /// can't be read any more (the room was closed). Reconnects by itself, with a fresh token.
    func listen(_ path: String) -> AsyncThrowingStream<Change, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                var failures = 0
                while !Task.isCancelled {
                    do {
                        let t = try await self.token()
                        var req = URLRequest(url: self.url(path, token: t))
                        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                        let (bytes, response) = try await self.streamSession.bytes(for: req)
                        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                        if status == 401 || status == 403 { throw CloudError.denied }
                        guard status == 200 else { throw CloudError.server("Server said \(status)") }
                        failures = 0
                        var event = ""
                        for try await line in bytes.lines {
                            if line.hasPrefix("event:") {
                                event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                            } else if line.hasPrefix("data:") {
                                let body = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                                switch event {
                                case "put", "patch":
                                    guard let obj = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any] else { continue }
                                    let data = obj["data"]
                                    continuation.yield(Change(patch: event == "patch", path: obj["path"] as? String ?? "/",
                                                              data: data is NSNull ? nil : data))
                                case "cancel":
                                    throw CloudError.denied
                                case "auth_revoked":
                                    self.expires = .distantPast
                                    throw CloudError.server("token")
                                default:
                                    break   // keep-alive
                                }
                            }
                        }
                    } catch CloudError.denied {
                        continuation.finish(throwing: CloudError.denied)
                        return
                    } catch {
                        if Task.isCancelled { break }
                        failures += 1
                        if failures > 6 {
                            continuation.finish(throwing: error)
                            return
                        }
                        try? await Task.sleep(nanoseconds: UInt64(min(8, failures * 2)) * 1_000_000_000)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
