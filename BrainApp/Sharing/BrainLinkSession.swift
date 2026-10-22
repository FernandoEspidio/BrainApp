import Foundation
import Network
import Observation

/// The brain trade, as the user sees it: both phones look for each other at the same time
/// (no "host" or "join" choice), both confirm the match, then each one pushes its brain through the portal.
///
/// Under the hood (Network framework, peer-to-peer Wi-Fi, no Internet):
/// - Every phone advertises `_brain-link._tcp` as "Name#token" AND browses for others.
/// - Of two phones that see each other, the one with the smaller random token opens the connection;
///   the other waits (if it never gets a call, it dials too after a few seconds).
/// - Messages: intro → accept/decline (both) → card (each, when its brain enters the portal) → done.
/// - Both screens show the same 3 emojis, derived from both tokens, so people can check
///   they matched with the right person before accepting.
/// - The intro carries the card's stable ID, so a brain you already met is recognized ("Sam is back!").
/// - Once linked, both phones swap Nearby Interaction tokens (when the iPhone has UWB) so the portal can
///   charge by pointing the phone at the friend and walking closer.
/// - "Practice" swaps the network for a fictional friend, for when nobody else is around.
@MainActor
@Observable
final class BrainLinkSession {
    struct Peer: Equatable, Sendable {
        let name: String
        let colorIndex: Int
        let token: String
        /// Their card's stable ID: lets the UI recognize a friend you already have.
        let cardID: UUID?
        /// Same 3 emojis on both phones.
        let matchCode: [String]
    }

    enum Phase: Equatable {
        case idle
        case searching
        /// A brain was found; waiting for this user to say yes.
        case found(Peer)
        /// This user said yes; waiting for the other one.
        case waitingForPeer(Peer)
        /// Both said yes: portal time.
        case linked(Peer)
        /// This brain went through; waiting for theirs.
        case sent(Peer)
        case arrived(Peer, ShareableBrainCard)
        /// The other person said "not them"; back to searching in a moment.
        case declined(Peer)
        case failed(String)
    }

    enum Mode { case network, simulated }

    private(set) var phase: Phase = .idle
    /// Their brain already came through (they were faster): the UI can hint "it's on its way".
    private(set) var peerHasSent = false

    private(set) var mode: Mode
    /// Distance/direction to the friend while linked (nil = not available on this phone or pair).
    private(set) var aim: NearbyRanging.Reading?
    private(set) var aimAvailable = false

    private var engine: LinkEngine?
    private let ranging = NearbyRanging()
    private var myCard: ShareableBrainCard?
    private var theirCard: ShareableBrainCard?
    private var myAccepted = false
    private var peerAccepted = false
    private var mySent = false
    /// People declined in this session aren't offered again right away.
    private var snoozed: Set<String> = []
    private var resumeTask: Task<Void, Never>?

    init(mode: Mode) {
        self.mode = mode
        ranging.onReading = { [weak self] reading in
            guard let self else { return }
            self.aim = reading.distance == nil ? nil : reading
            if reading.distance != nil { self.aimAvailable = true }
        }
    }

    var peer: Peer? {
        switch phase {
        case .found(let p), .waitingForPeer(let p), .linked(let p), .sent(let p), .declined(let p), .arrived(let p, _): return p
        default: return nil
        }
    }

    // MARK: - User actions

    func start(card: ShareableBrainCard) {
        myCard = card
        beginSearch()
    }

    /// Nobody around: trade with a fictional brain instead (it shows the same ceremony).
    func startPractice() {
        mode = .simulated
        beginSearch()
    }

    func accept() {
        guard case .found(let p) = phase else { return }
        myAccepted = true
        engine?.send(.accept)
        if peerAccepted { link(p) } else { phase = .waitingForPeer(p) }
    }

    private func link(_ p: Peer) {
        phase = .linked(p)
        // Pointing to send needs UWB on both phones. Optional: dragging and tapping always work.
        if mode == .network, let token = ranging.start(cameraAssistance: false) {
            engine?.send(.ranging(token))
        }
    }

    func decline() {
        guard let p = peer else { return }
        engine?.send(.decline)
        snoozed.insert(p.token)
        // Give the message a moment to leave before closing.
        restartSearch(after: 0.3)
    }

    /// Called when the brain enters the portal.
    func sendBrain() {
        guard case .linked(let p) = phase, let myCard else { return }
        mySent = true
        engine?.send(.card(myCard))
        if let theirCard {
            arrive(p, theirCard)
        } else {
            phase = .sent(p)
        }
    }

    func stop() {
        resumeTask?.cancel()
        engine?.stop()
        engine = nil
        stopRanging()
        phase = .idle
    }

    private func arrive(_ p: Peer, _ card: ShareableBrainCard) {
        phase = .arrived(p, card)
        stopRanging()
        engine?.finishSoon()
    }

    private func stopRanging() {
        ranging.stop()
        aim = nil
        aimAvailable = false
    }

    // MARK: - Engine events

    private func beginSearch() {
        resumeTask?.cancel()
        engine?.stop()
        resetHandshake()
        guard let myCard else { return }
        let intro = LinkIntro(version: ShareableBrainCard.currentVersion, token: Self.makeToken(),
                              name: myCard.displayName, colorIndex: myCard.appearance.colorIndex, cardID: myCard.id)
        let engine: LinkEngine = mode == .network
            ? NetworkLinkEngine(intro: intro, snoozed: snoozed)
            : SimulatedLinkEngine(intro: intro)
        engine.onEvent = { [weak self] event in self?.handle(event) }
        self.engine = engine
        phase = .searching
        engine.start()
    }

    private func resetHandshake() {
        theirCard = nil
        stopRanging()
        myAccepted = false
        peerAccepted = false
        mySent = false
        peerHasSent = false
    }

    private func restartSearch(after seconds: Double) {
        resumeTask?.cancel()
        engine?.stop()
        engine = nil
        resumeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.beginSearch()
        }
    }

    private func handle(_ event: LinkEvent) {
        switch event {
        case .introduced(let intro, let myToken):
            guard phase == .searching else { return }
            guard intro.version == ShareableBrainCard.currentVersion else {
                phase = .failed("Your friend needs to update the app to trade brains.")
                engine?.stop()
                return
            }
            let p = Peer(name: String(intro.name.prefix(40)),
                         colorIndex: max(0, min(intro.colorIndex, Theme.brainVariants.count - 1)),
                         token: intro.token,
                         cardID: intro.cardID,
                         matchCode: MatchCode.emojis(intro.token, myToken))
            phase = .found(p)
        case .message(.accept):
            peerAccepted = true
            if case .waitingForPeer(let p) = phase { link(p) }
        case .message(.decline):
            guard let p = peer else { return }
            snoozed.insert(p.token)
            phase = .declined(p)
            restartSearch(after: 2.2)
        case .message(.card(let card)):
            guard theirCard == nil, card.protocolVersion == ShareableBrainCard.currentVersion else { return }
            let safe = card.sanitized()
            theirCard = safe
            peerHasSent = true
            if mySent, let p = peer { arrive(p, safe) }
        case .message(.ranging(let data)):
            ranging.connect(peerTokenData: data)
        case .message(.intro):
            break
        case .lost:
            switch phase {
            case .searching, .idle, .arrived, .failed:
                break
            case .found, .waitingForPeer, .declined:
                // Lost before anything was traded: quietly look again.
                restartSearch(after: 0.5)
            case .linked(let p), .sent(let p):
                if theirCard == nil {
                    phase = .failed("Lost the connection with \(p.name). Stand a little closer and try again.")
                }
            }
        case .failure(let message):
            phase = .failed(message)
        }
    }

    private static func makeToken() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10)).lowercased()
    }
}

// MARK: - Wire format

struct LinkIntro: Codable, Sendable {
    var version: Int
    var token: String
    var name: String
    var colorIndex: Int
    /// Optional so older builds still decode.
    var cardID: UUID?
}

enum LinkMessage: Codable, Sendable {
    case intro(LinkIntro)
    case accept
    case decline
    case card(ShareableBrainCard)
    /// Archived Nearby Interaction discovery token.
    case ranging(Data)
}

enum LinkEvent {
    case introduced(LinkIntro, myToken: String)
    case message(LinkMessage)
    case lost
    case failure(String)
}

/// Three emojis both people can compare ("do you see 🍓 🌙 ⭐️ too?"). Same on both phones
/// because it's computed from both tokens in a fixed order.
enum MatchCode {
    static let symbols = ["🍓", "🌙", "⭐️", "🍀", "🎈", "🐙", "🍩", "🌈", "🦋", "🍄", "⚡️", "🎲", "🐝", "🌵", "🍉", "🪐"]

    static func emojis(_ a: String, _ b: String) -> [String] {
        let joined = [a, b].sorted().joined(separator: ":")
        // FNV-1a: tiny, stable across launches and devices (unlike Hasher).
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in joined.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return (0..<3).map { index in symbols[Int((hash >> (UInt64(index) * 8)) & 0x0F)] }
    }
}

// MARK: - Engines

@MainActor
protocol LinkEngine: AnyObject {
    var onEvent: ((LinkEvent) -> Void)? { get set }
    func start()
    func send(_ message: LinkMessage)
    /// Close after the last message had time to go out.
    func finishSoon()
    func stop()
}

/// Real exchange between two nearby phones (also works between two simulators on the same Mac).
@MainActor
final class NetworkLinkEngine: LinkEngine {
    static let serviceType = "_brain-link._tcp"

    var onEvent: ((LinkEvent) -> Void)?

    private let intro: LinkIntro
    private let snoozed: Set<String>
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var introduced = false
    private var dialTimers: [String: DispatchWorkItem] = [:]
    private var stopped = false

    init(intro: LinkIntro, snoozed: Set<String>) {
        self.intro = intro
        self.snoozed = snoozed
    }

    func start() {
        startListening()
        startBrowsing()
    }

    // Bonjour names are limited to 63 bytes: a short name plus the token.
    private var serviceName: String {
        let name = String(intro.name.filter { $0 != "#" }.prefix(24))
        return "\(name)#\(intro.token)"
    }

    private func startListening() {
        do {
            let listener = try NWListener(using: PeerWire.parameters())
            listener.service = NWListener.Service(name: serviceName, type: Self.serviceType)
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated {
                    if case .failed(let error) = state { self?.report(error) }
                }
            }
            listener.newConnectionHandler = { [weak self] incoming in
                MainActor.assumeIsolated { self?.adopt(incoming) }
            }
            self.listener = listener
            listener.start(queue: .main)
        } catch {
            onEvent?(.failure("Couldn't start looking for brains."))
        }
    }

    private func startBrowsing() {
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: PeerWire.parameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated { self?.consider(results) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                if case .failed(let error) = state { self?.report(error) }
            }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    private func consider(_ results: Set<NWBrowser.Result>) {
        guard connection == nil, !stopped else { return }
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint,
                  let token = name.split(separator: "#").last.map(String.init),
                  token != intro.token, !snoozed.contains(token), dialTimers[token] == nil else { continue }
            let endpoint = result.endpoint
            let direct = result.interfaces.first { $0.name.hasPrefix("awdl") }
            if intro.token < token {
                dial(endpoint, direct: direct)
                return
            }
            // The other phone should call us. If it doesn't within a few seconds, call it.
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.connection == nil, !self.stopped else { return }
                    self.dial(endpoint, direct: direct)
                }
            }
            dialTimers[token] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
        }
    }

    private func dial(_ endpoint: NWEndpoint, direct: NWInterface?) {
        guard connection == nil else { return }
        let parameters = PeerWire.parameters()
        if let direct { parameters.requiredInterface = direct }
        adopt(NWConnection(to: endpoint, using: parameters))
    }

    private func adopt(_ newConnection: NWConnection) {
        guard connection == nil, !stopped else {
            newConnection.cancel()
            return
        }
        connection = newConnection
        dialTimers.values.forEach { $0.cancel() }
        newConnection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self, newConnection === self.connection else { return }
                switch state {
                case .ready:
                    // One partner at a time: stop advertising and browsing while we talk.
                    self.browser?.cancel()
                    self.browser = nil
                    self.listener?.cancel()
                    self.listener = nil
                    self.send(.intro(self.intro))
                    self.receiveLoop()
                case .failed, .cancelled:
                    self.lose()
                default:
                    break
                }
            }
        }
        newConnection.start(queue: .main)
    }

    func send(_ message: LinkMessage) {
        guard let connection, let body = try? JSONEncoder().encode(message) else { return }
        connection.send(content: PeerWire.frame(body), completion: .contentProcessed { _ in })
    }

    private func receiveLoop() {
        guard let connection else { return }
        PeerWire.receiveFrame(on: connection) { [weak self] result in
            MainActor.assumeIsolated {
                guard let self, connection === self.connection else { return }
                switch result {
                case .failure:
                    self.lose()
                case .success(let body):
                    if let message = try? JSONDecoder().decode(LinkMessage.self, from: body) {
                        if case .intro(let theirs) = message {
                            guard !self.introduced else { break }
                            self.introduced = true
                            self.onEvent?(.introduced(theirs, myToken: self.intro.token))
                        } else {
                            self.onEvent?(.message(message))
                        }
                    }
                    self.receiveLoop()
                }
            }
        }
    }

    func finishSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    private func lose() {
        guard !stopped else { return }
        connection?.cancel()
        connection = nil
        onEvent?(.lost)
    }

    func stop() {
        stopped = true
        dialTimers.values.forEach { $0.cancel() }
        dialTimers = [:]
        listener?.cancel()
        browser?.cancel()
        connection?.cancel()
        listener = nil
        browser = nil
        connection = nil
    }

    private func report(_ error: NWError) {
        let text = error.debugDescription
        if text.contains("-65555") || text.contains("NoAuth") {
            onEvent?(.failure("Allow Local Network for this app in Settings to find nearby brains."))
        } else {
            onEvent?(.failure("Couldn't look for nearby brains (\(text))."))
        }
    }
}

/// Demo mode: a fictional friend shows up, accepts and sends their brain, all on one phone.
@MainActor
final class SimulatedLinkEngine: LinkEngine {
    var onEvent: ((LinkEvent) -> Void)?
    private let intro: LinkIntro
    private var tasks: [Task<Void, Never>] = []
    private let friend: DemoData.DemoFriend
    private var delivered = false

    init(intro: LinkIntro) {
        self.intro = intro
        friend = DemoData.demoFriends.randomElement() ?? DemoData.demoFriends[0]
    }

    func start() {
        later(2.8) { [weak self] in
            guard let self else { return }
            let theirs = LinkIntro(version: ShareableBrainCard.currentVersion, token: "demo\(Int.random(in: 1000...9999))",
                                   name: self.friend.name, colorIndex: self.friend.appearance.colorIndex,
                                   cardID: self.friend.id)
            self.onEvent?(.introduced(theirs, myToken: self.intro.token))
        }
    }

    func send(_ message: LinkMessage) {
        switch message {
        case .accept:
            later(1.4) { [weak self] in self?.onEvent?(.message(.accept)) }
            // Sometimes the friend is faster and their brain is already on its way.
            later(4.5) { [weak self] in self?.deliver() }
        case .card:
            later(0.9) { [weak self] in self?.deliver() }
        default:
            break
        }
    }

    private func deliver() {
        guard !delivered else { return }
        delivered = true
        onEvent?(.message(.card(DemoData.demoFriendCard(friend))))
    }

    func finishSoon() {}

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    private func later(_ seconds: Double, _ work: @escaping @MainActor () -> Void) {
        tasks.append(Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            work()
        })
    }
}
