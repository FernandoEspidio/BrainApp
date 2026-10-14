import Foundation
import Network
import Observation

/// Messages for the "throw your brain" test. Separate from `WireMessage` so the earlier test keeps working.
enum ThrowMessage: Codable {
    case hello(name: String)
    case rangingToken(Data)
    case card(ShareableBrainCard)
}

/// TEST: like PeerToPeerSession, but the connection STAYS OPEN so you can throw cards back and forth,
/// and it optionally measures distance/direction with Nearby Interaction.
/// Reuses the same Bonjour type (`_brain-p2p._tcp`); throw hosts are marked with " (throw)" in their name.
@MainActor
@Observable
final class ThrowSession {
    enum Phase: Equatable {
        case idle, hosting(code: String), browsing, connecting(String), connected(String), failed(String)

        var label: String {
            switch self {
            case .idle: return "Not connected"
            case .hosting(let code): return "Visible as \(code). Waiting…"
            case .browsing: return "Looking for nearby phones…"
            case .connecting(let name): return "Connecting to \(name)…"
            case .connected(let name): return "Connected with \(name)"
            case .failed(let message): return "Failed: \(message)"
            }
        }
    }

    static let marker = " (throw)"

    private(set) var phase: Phase = .idle
    private(set) var peers: [PeerToPeerSession.FoundPeer] = []
    private(set) var reading = NearbyRanging.Reading()
    private(set) var rangingActive = false
    private(set) var incoming: ShareableBrainCard?
    /// Increments every time a card arrives, to trigger the landing animation.
    private(set) var incomingCount = 0
    private(set) var log: [PeerToPeerSession.LogLine] = []

    var isConnected: Bool { if case .connected = phase { return true } else { return false } }

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var myName = ""
    private var useRanging = true
    private var cameraAssistance = false
    private let ranging = NearbyRanging()

    init() {
        ranging.onReading = { [weak self] reading in self?.reading = reading }
        ranging.onLog = { [weak self] text in self?.write("📡 \(text)") }
    }

    // MARK: - Connect (same pattern as the first test)

    func startHosting(name: String, ranging: Bool, cameraAssistance: Bool) {
        stop()
        configure(name: name, ranging: ranging, cameraAssistance: cameraAssistance)
        let code = String(format: "%04d", Int.random(in: 0...9999))
        let serviceName = String("\(name) - \(code)".prefix(50)) + Self.marker
        do {
            let listener = try NWListener(using: PeerWire.parameters())
            listener.service = NWListener.Service(name: serviceName, type: PeerWire.serviceType)
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated {
                    if case .failed(let error) = state { self?.fail("Listener: \(error.debugDescription)") }
                    if case .ready = state { self?.write("Hosting as “\(serviceName)”") }
                }
            }
            listener.newConnectionHandler = { [weak self] incoming in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard self.connection == nil else { incoming.cancel(); return }
                    self.write("Friend connecting…")
                    self.open(incoming, label: "friend")
                }
            }
            self.listener = listener
            phase = .hosting(code: code)
            listener.start(queue: .main)
        } catch {
            fail("Couldn't create listener: \(error.localizedDescription)")
        }
    }

    func startBrowsing(name: String, ranging: Bool, cameraAssistance: Bool) {
        stop()
        configure(name: name, ranging: ranging, cameraAssistance: cameraAssistance)
        let browser = NWBrowser(for: .bonjour(type: PeerWire.serviceType, domain: nil), using: PeerWire.parameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                self?.peers = results.compactMap { result in
                    guard case let .service(name, _, _, _) = result.endpoint, name.hasSuffix(Self.marker) else { return nil }
                    return PeerToPeerSession.FoundPeer(name: name, endpoint: result.endpoint,
                                                       interfaceNames: result.interfaces.map(\.name),
                                                       directInterface: result.interfaces.first { $0.name.hasPrefix("awdl") })
                }
                .sorted { $0.name < $1.name }
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                if case .failed(let error) = state { self?.fail("Browser: \(error.debugDescription)") }
            }
        }
        self.browser = browser
        phase = .browsing
        browser.start(queue: .main)
    }

    func connect(to peer: PeerToPeerSession.FoundPeer) {
        browser?.cancel()
        browser = nil
        let parameters = PeerWire.parameters()
        if let direct = peer.directInterface { parameters.requiredInterface = direct }
        let name = peer.name.replacingOccurrences(of: Self.marker, with: "")
        phase = .connecting(name)
        open(NWConnection(to: peer.endpoint, using: parameters), label: name)
    }

    private func configure(name: String, ranging: Bool, cameraAssistance: Bool) {
        myName = name
        useRanging = ranging
        self.cameraAssistance = cameraAssistance
        incoming = nil
    }

    private func open(_ newConnection: NWConnection, label: String) {
        connection = newConnection
        newConnection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch state {
                case .ready:
                    let names = newConnection.currentPath?.availableInterfaces.map(\.name).joined(separator: ",") ?? "?"
                    self.write("Connected on [\(names)]")
                    self.phase = .connected(label)
                    self.send(.hello(name: self.myName))
                    if self.useRanging, let token = self.ranging.start(cameraAssistance: self.cameraAssistance) {
                        self.send(.rangingToken(token))
                    }
                    self.receiveLoop()
                case .waiting(let error):
                    self.write("Waiting: \(error.debugDescription)")
                case .failed(let error):
                    self.fail("Connection: \(error.debugDescription)")
                case .cancelled:
                    self.write("Connection closed")
                default:
                    break
                }
            }
        }
        newConnection.start(queue: .main)
    }

    // MARK: - Messages

    func throwCard(_ card: ShareableBrainCard) {
        send(.card(card))
        write("🧠 Thrown!")
    }

    private func send(_ message: ThrowMessage) {
        guard let connection else { return }
        do {
            let body = try JSONEncoder().encode(message)
            connection.send(content: PeerWire.frame(body), completion: .contentProcessed { [weak self] error in
                MainActor.assumeIsolated {
                    if let error { self?.write("Send failed: \(error.localizedDescription)") }
                }
            })
        } catch {
            write("Couldn't encode: \(error.localizedDescription)")
        }
    }

    private func receiveLoop() {
        guard let connection else { return }
        PeerWire.receiveFrame(on: connection) { [weak self] result in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch result {
                case .failure(let error):
                    self.fail("Friend disconnected (\(error.localizedDescription))")
                case .success(let body):
                    self.handle(body)
                    self.receiveLoop()
                }
            }
        }
    }

    private func handle(_ body: Data) {
        guard let message = try? JSONDecoder().decode(ThrowMessage.self, from: body) else {
            write("Ignored an unknown message")
            return
        }
        switch message {
        case .hello(let name):
            phase = .connected(name)
            write("Friend is “\(name)”")
        case .rangingToken(let data):
            if useRanging {
                ranging.connect(peerTokenData: data)
                rangingActive = true
            }
        case .card(let card):
            guard card.protocolVersion == ShareableBrainCard.currentVersion else {
                write("Incompatible card version")
                return
            }
            incoming = card.sanitized()
            incomingCount += 1
            write("🎯 Caught “\(card.displayName)”")
        }
    }

    func dismissIncoming() { incoming = nil }

    // MARK: - Helpers

    func stop() {
        ranging.stop()
        rangingActive = false
        reading = NearbyRanging.Reading()
        listener?.cancel()
        browser?.cancel()
        connection?.cancel()
        listener = nil
        browser = nil
        connection = nil
        peers = []
        phase = .idle
    }

    private func fail(_ message: String) {
        write("❌ \(message)")
        stop()
        phase = .failed(message)
    }

    private func write(_ text: String) {
        log.append(PeerToPeerSession.LogLine(text: text))
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }
}
