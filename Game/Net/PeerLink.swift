import Foundation
import Network

/// One connection to another player. Messages go as JSON, each with a 4-byte length in front.
/// Everything runs on the main queue, so the game can use it directly.
@MainActor
final class PeerLink {
    let connection: NWConnection
    var onReady: (() -> Void)?
    var onMessage: ((NetMessage) -> Void)?
    var onClose: (() -> Void)?
    private(set) var isClosed = false
    private var buffer = Data()

    /// A world with lots of building can be a few megabytes; anything bigger is a mistake.
    private static let maxMessage = 32 * 1024 * 1024
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// TCP with no delay, so small position updates go out at once.
    static func parameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = false
        return parameters
    }

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch state {
                case .ready:
                    self.onReady?()
                case .failed, .cancelled, .waiting:
                    self.finish()
                default:
                    break
                }
            }
        }
        receive()
        connection.start(queue: .main)
    }

    func send(_ message: NetMessage) {
        guard !isClosed, let body = try? PeerLink.encoder.encode(message) else { return }
        var frame = Data(capacity: body.count + 4)
        let length = UInt32(body.count)
        frame.append(UInt8(truncatingIfNeeded: length >> 24))
        frame.append(UInt8(truncatingIfNeeded: length >> 16))
        frame.append(UInt8(truncatingIfNeeded: length >> 8))
        frame.append(UInt8(truncatingIfNeeded: length))
        frame.append(body)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    func close() {
        finish()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, !self.isClosed else { return }
                if let data, !data.isEmpty {
                    self.buffer.append(data)
                    self.drain()
                }
                if isComplete || error != nil {
                    self.finish()
                } else if !self.isClosed {
                    self.receive()
                }
            }
        }
    }

    /// Hand over every whole message in the buffer.
    private func drain() {
        while !isClosed && buffer.count >= 4 {
            let header = [UInt8](buffer.prefix(4))
            let length = Int(header[0]) << 24 | Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
            guard length <= PeerLink.maxMessage else {
                finish()
                return
            }
            guard buffer.count >= 4 + length else { return }
            let start = buffer.startIndex + 4
            let body = buffer.subdata(in: start ..< start + length)
            buffer = Data(buffer[(start + length)...])
            if let message = try? PeerLink.decoder.decode(NetMessage.self, from: body) {
                onMessage?(message)
            }
        }
    }

    private func finish() {
        guard !isClosed else { return }
        isClosed = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        onClose?()
    }
}
