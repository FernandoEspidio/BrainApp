import Foundation
import Network
import Observation

/// TEST TRANSPORT: swaps brain cards between two nearby iPhones using Network framework over
/// Apple's peer-to-peer Wi-Fi (`includePeerToPeer`). No Internet, no router, no special entitlement.
///
/// Requires two Info.plist keys (see README): NSLocalNetworkUsageDescription and
/// NSBonjourServices = ["_brain-p2p._tcp"]. Without them, browsing fails with "NoAuth (-65555)".
///
/// Flow: one phone HOSTS (advertises "Name · 1234"), the other JOINS (sees the list, taps it).
/// Joiner sends its card first, host replies with its own, both close. Messages are
/// length-prefixed JSON (`WireMessage`). Not encrypted yet: cards carry no private data, but
/// production should add TLS with a pre-shared code.
enum PeerWire {
    static let serviceType = "_brain-p2p._tcp"

    static func parameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 2
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }

    static func frame(_ body: Data) -> Data {
        let length = UInt32(body.count)
        var data = Data([UInt8((length >> 24) & 0xFF), UInt8((length >> 16) & 0xFF),
                         UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)])
        data.append(body)
        return data
    }

    /// Reads one length-prefixed message (max 64 KB). The completion runs on the connection's queue (main).
    /// Only touches Network/Foundation types so it is safe to call from any isolation.
    nonisolated static func receiveFrame(on connection: NWConnection, completion: @escaping (Result<Data, Error>) -> Void) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { header, _, _, error in
            if let error { completion(.failure(error)); return }
            guard let header, header.count == 4 else { completion(.failure(NWError.posix(.ECONNRESET))); return }
            let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard length > 0, length <= 65_536 else { completion(.failure(NWError.posix(.EBADMSG))); return }
            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { body, _, _, error in
                if let error { completion(.failure(error)); return }
                guard let body, body.count == Int(length) else { completion(.failure(NWError.posix(.ECONNRESET))); return }
                completion(.success(body))
            }
        }
    }
}

enum PeerError: LocalizedError {
    case closed, badMessage, incompatible

    var errorDescription: String? {
        switch self {
        case .closed: return "The other phone closed the connection."
        case .badMessage: return "Received something that isn't a brain card."
        case .incompatible: return "The other phone runs an incompatible version."
        }
    }
}

@MainActor
@Observable
final class PeerToPeerSession {
    enum Phase: Equatable {
        case idle
        case hosting(code: String)
        case browsing
        case connecting(String)
        case done
        case failed(String)

        var label: String {
            switch self {
            case .idle: return "Not connected"
            case .hosting(let code): return "Visible as code \(code). Waiting for a friend…"
            case .browsing: return "Looking for nearby phones…"
            case .connecting(let name): return "Connecting to \(name)…"
            case .done: return "Cards swapped ✓"
            case .failed(let message): return "Failed: \(message)"
            }
        }
    }

    struct FoundPeer: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let endpoint: NWEndpoint
        /// Interfaces where the peer was seen, e.g. ["en0", "awdl0"]. en0 = shared Wi-Fi network, awdl0 = direct.
        let interfaceNames: [String]
        /// The direct peer-to-peer interface, if the peer was seen on it.
        let directInterface: NWInterface?
    }

    struct LogLine: Identifiable {
        let id = UUID()
        let date = Date()
        let text: String
    }

    private(set) var phase: Phase = .idle
    private(set) var peers: [FoundPeer] = []
    private(set) var log: [LogLine] = []
    private(set) var received: ShareableBrainCard?

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var outgoing: ShareableBrainCard?
    private var timeout: DispatchWorkItem?
    private var restarts = 0

    // MARK: - Host

    func startHosting(card: ShareableBrainCard) {
        stop()
        outgoing = card
        received = nil
        let code = String(format: "%04d", Int.random(in: 0...9999))
        let name = String("\(card.displayName) - \(code)".prefix(60))

        let listener: NWListener
        do {
            listener = try NWListener(using: PeerWire.parameters())
        } catch {
            fail("Couldn't create listener: \(error.localizedDescription)")
            return
        }
        listener.service = NWListener.Service(name: name, type: PeerWire.serviceType)
        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.listenerChanged(state) }
        }
        listener.newConnectionHandler = { [weak self] newConnection in
            MainActor.assumeIsolated { self?.accept(newConnection) }
        }
        self.listener = listener
        phase = .hosting(code: code)
        write("Hosting as “\(name)”")
        listener.start(queue: .main)
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            write("Listener ready on port \(listener?.port?.debugDescription ?? "?")")
        case .waiting(let error):
            write("Listener waiting: \(describe(error))")
        case .failed(let error):
            fail("Listener: \(describe(error))")
        case .cancelled:
            write("Listener stopped")
        default:
            break
        }
    }

    private func accept(_ incoming: NWConnection) {
        guard connection == nil else {
            write("Another phone tried to connect; busy, rejected")
            incoming.cancel()
            return
        }
        write("Incoming connection from \(incoming.endpoint.debugDescription)")
        restarts = 0
        connection = incoming
        run(incoming, isJoiner: false)
    }

    // MARK: - Join

    func startBrowsing() {
        stop()
        received = nil
        let browser = NWBrowser(for: .bonjour(type: PeerWire.serviceType, domain: nil), using: PeerWire.parameters())
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.browserChanged(state) }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated { self?.updatePeers(results) }
        }
        self.browser = browser
        phase = .browsing
        write("Browsing for \(PeerWire.serviceType)")
        browser.start(queue: .main)
    }

    private func browserChanged(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            write("Browser ready")
        case .waiting(let error):
            write("Browser waiting: \(describe(error))")
        case .failed(let error):
            fail("Browser: \(describe(error))")
        default:
            break
        }
    }

    private func updatePeers(_ results: Set<NWBrowser.Result>) {
        peers = results.compactMap { result in
            if case let .service(name, _, _, _) = result.endpoint {
                return FoundPeer(name: name, endpoint: result.endpoint,
                                 interfaceNames: result.interfaces.map(\.name),
                                 directInterface: result.interfaces.first { $0.name.hasPrefix("awdl") })
            }
            return nil
        }
        .sorted { $0.name < $1.name }
        let summary = peers.map { "\($0.name) [\($0.interfaceNames.isEmpty ? "?" : $0.interfaceNames.joined(separator: ","))]" }
        write("Found \(peers.count) phone(s): \(summary.joined(separator: "; "))")
    }

    /// `forceDirect`: pin the connection to the peer-to-peer interface (awdl0) where the peer was seen.
    /// Without infrastructure Wi-Fi, letting the system pick can stall resolving the service, so pinning helps.
    func connect(to peer: FoundPeer, card: ShareableBrainCard, forceDirect: Bool) {
        browser?.cancel()
        browser = nil
        outgoing = card
        restarts = 0
        let parameters = PeerWire.parameters()
        if forceDirect, let direct = peer.directInterface {
            parameters.requiredInterface = direct
            write("Pinned to \(direct.name) (direct peer-to-peer)")
        } else if forceDirect {
            write("Peer not seen on awdl yet; letting the system choose the interface")
        }
        let newConnection = NWConnection(to: peer.endpoint, using: parameters)
        connection = newConnection
        phase = .connecting(peer.name)
        write("Connecting to “\(peer.name)”")
        run(newConnection, isJoiner: true)
        startTimeout()
    }

    private func startTimeout(seconds: Double = 15) {
        timeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, case .connecting = self.phase else { return }
                self.fail("Timed out. Check both screens are on, Wi-Fi is ON (Airplane mode + Wi-Fi), try Bluetooth ON too, and stand close. Also try with \"Force direct\" on/off.")
            }
        }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: - Exchange

    private func run(_ connection: NWConnection, isJoiner: Bool) {
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.connectionChanged(state, isJoiner: isJoiner) }
        }
        connection.start(queue: .main)
    }

    private func connectionChanged(_ state: NWConnection.State, isJoiner: Bool) {
        switch state {
        case .ready:
            timeout?.cancel()
            let names = connection?.currentPath?.availableInterfaces.map(\.name) ?? []
            let direct = names.contains { $0.hasPrefix("awdl") }
            write("Connected on [\(names.joined(separator: ","))]\(direct ? " → direct peer-to-peer Wi-Fi ✓" : " → through a shared network")")
            if isJoiner {
                sendCard { [weak self] in self?.receiveCard(thenReply: false) }
            } else {
                receiveCard(thenReply: true)
            }
        case .waiting(let error):
            write("Connection waiting: \(describe(error))")
            // A waiting connection doesn't retry quickly on its own; nudge it a couple of times.
            if restarts < 3 {
                restarts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, let connection = self.connection, case .waiting = connection.state else { return }
                        self.write("Retrying (\(self.restarts))…")
                        connection.restart()
                    }
                }
            }
        case .failed(let error):
            fail("Connection: \(describe(error))")
        case .cancelled:
            write("Connection closed")
        default:
            break
        }
    }

    private func sendCard(then next: @escaping () -> Void) {
        guard let connection, let outgoing else { return }
        do {
            let body = try JSONEncoder().encode(WireMessage.hello(outgoing))
            connection.send(content: PeerWire.frame(body), completion: .contentProcessed { [weak self] error in
                MainActor.assumeIsolated {
                    if let error {
                        self?.fail("Send: \(error.localizedDescription)")
                    } else {
                        self?.write("Sent my card (\(body.count) bytes)")
                        next()
                    }
                }
            })
        } catch {
            fail("Couldn't encode my card: \(error.localizedDescription)")
        }
    }

    private func receiveCard(thenReply: Bool) {
        guard let connection else { return }
        PeerWire.receiveFrame(on: connection) { [weak self] result in
            MainActor.assumeIsolated { self?.handleFrame(result, thenReply: thenReply) }
        }
    }

    private func handleFrame(_ result: Result<Data, Error>, thenReply: Bool) {
        switch result {
        case .failure(let error):
            fail("Receive: \(error.localizedDescription)")
        case .success(let body):
            do {
                let message = try JSONDecoder().decode(WireMessage.self, from: body)
                guard case .hello(let card) = message else { throw PeerError.badMessage }
                guard card.protocolVersion == ShareableBrainCard.currentVersion else { throw PeerError.incompatible }
                received = card.sanitized()
                write("Received “\(card.displayName)” (\(body.count) bytes)")
                if thenReply {
                    sendCard { [weak self] in self?.finish() }
                } else {
                    finish()
                }
            } catch {
                fail(error.localizedDescription)
            }
        }
    }

    private func finish() {
        timeout?.cancel()
        phase = .done
        write("Done ✓")
        connection?.cancel()
        connection = nil
        listener?.cancel()
        listener = nil
    }

    // MARK: - Helpers

    func stop() {
        timeout?.cancel()
        listener?.cancel()
        browser?.cancel()
        connection?.cancel()
        listener = nil
        browser = nil
        connection = nil
        peers = []
        if phase != .done { phase = .idle }
    }

    func clearLog() { log = [] }

    private func fail(_ message: String) {
        timeout?.cancel()
        write("❌ \(message)")
        listener?.cancel()
        browser?.cancel()
        connection?.cancel()
        listener = nil
        browser = nil
        connection = nil
        phase = .failed(message)
    }

    private func write(_ text: String) {
        log.append(LogLine(text: text))
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }

    private func describe(_ error: NWError) -> String {
        let text = error.debugDescription
        if text.contains("-65555") || text.contains("NoAuth") {
            return "\(text). Local Network permission denied or NSBonjourServices missing in Info.plist."
        }
        return text
    }
}
