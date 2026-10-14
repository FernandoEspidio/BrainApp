import Foundation
import Observation

/// State machine for the nearby exchange, independent of the concrete transport.
@MainActor
@Observable
final class NearbySharingCoordinator {
    enum Role {
        case host, join
    }

    enum State: Equatable {
        case idle
        case working(Role)
        case received(ShareableBrainCard)
        case failed(String)
    }

    private(set) var state: State = .idle
    let transports: [any NearbyTransport]

    private var task: Task<Void, Never>?

    init(transports: [any NearbyTransport]) {
        self.transports = transports
    }

    var primaryTransport: (any NearbyTransport)? { transports.first }

    func start(_ role: Role, card: ShareableBrainCard, onReceive: @escaping (ShareableBrainCard) -> Void) {
        guard let transport = primaryTransport else { return }
        task?.cancel()
        state = .working(role)
        task = Task { [weak self] in
            do {
                let received: ShareableBrainCard
                switch role {
                case .host: received = try await transport.host(sending: card)
                case .join: received = try await transport.join(sending: card)
                }
                guard !Task.isCancelled else { return }
                guard received.protocolVersion == ShareableBrainCard.currentVersion else {
                    throw NearbyError.incompatibleVersion
                }
                let safe = received.sanitized()
                onReceive(safe)
                self?.state = .received(safe)
            } catch is CancellationError {
                self?.state = .idle
            } catch {
                self?.state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = .idle
    }

    func reset() {
        state = .idle
    }
}
