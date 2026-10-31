import Foundation
import Network

/// Hosting: shows this game to devices on the same Wi-Fi and keeps a connection to each friend.
@MainActor
final class NetHost {
    var onMessage: ((Int, NetMessage) -> Void)?
    var onDisconnect: ((Int) -> Void)?
    var onFailed: (() -> Void)?

    private var listener: NWListener?
    private var links: [Int: PeerLink] = [:]
    private var nextID = 1
    /// Up to this many friends at once, besides the host.
    static let maxFriends = 7

    func start(name: String) throws {
        let listener = try NWListener(using: PeerLink.parameters())
        listener.service = NWListener.Service(name: name, type: Net.serviceType)
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated {
                self?.accept(connection)
            }
        }
        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                if case .failed = state { self?.onFailed?() }
            }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    func stop() {
        listener?.newConnectionHandler = nil
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        listener = nil
        let all = links
        links.removeAll()
        for link in all.values {
            link.onClose = nil
            link.close()
        }
    }

    var friendCount: Int { links.count }

    func send(_ message: NetMessage, to id: Int) {
        links[id]?.send(message)
    }

    func broadcast(_ message: NetMessage, except skip: Int? = nil) {
        for (id, link) in links where id != skip {
            link.send(message)
        }
    }

    func disconnect(_ id: Int) {
        guard let link = links.removeValue(forKey: id) else { return }
        link.onClose = nil
        link.close()
    }

    private func accept(_ connection: NWConnection) {
        let link = PeerLink(connection: connection)
        guard links.count < NetHost.maxFriends else {
            // The closure keeps the link alive until it has said why, then lets it go.
            link.onReady = {
                link.send(.refused(reason: "This game is full"))
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    link.close()
                    link.onReady = nil
                }
            }
            link.start()
            return
        }
        let id = nextID
        nextID += 1
        links[id] = link
        link.onMessage = { [weak self] message in
            self?.onMessage?(id, message)
        }
        link.onClose = { [weak self] in
            guard let self, self.links.removeValue(forKey: id) != nil else { return }
            self.onDisconnect?(id)
        }
        link.start()
    }
}

/// A game someone is hosting on this Wi-Fi.
struct FoundGame: Hashable {
    let name: String
    let endpoint: NWEndpoint
}

/// Looks for games being hosted on this Wi-Fi.
@MainActor
final class NetBrowser {
    var onChange: (([FoundGame]) -> Void)?
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: Net.serviceType, domain: nil), using: PeerLink.parameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                let games = results.compactMap { result -> FoundGame? in
                    if case let .service(name, _, _, _) = result.endpoint {
                        return FoundGame(name: name, endpoint: result.endpoint)
                    }
                    return nil
                }
                self?.onChange?(games.sorted { $0.name < $1.name })
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                // Restart if the Wi-Fi drops and comes back.
                if case .failed = state {
                    self?.stop()
                    self?.start()
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.browseResultsChangedHandler = nil
        browser?.stateUpdateHandler = nil
        browser?.cancel()
        browser = nil
    }
}
