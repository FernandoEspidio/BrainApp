import Foundation

/// Network-free simulation to walk through the flow in the simulator. Only exists in Demo mode,
/// and the received friend is always marked as fictional.
@MainActor
final class DemoNearbyTransport: NearbyTransport {
    let kind: TransportKind = .demo
    let requirementsNote = "Simulation: there is no real connection and the received companion is fictional."

    private let names = ["Sam", "Lu", "Noa", "Rafa", "Iris"]

    func host(sending card: ShareableBrainCard) async throws -> ShareableBrainCard {
        try await simulateExchange()
    }

    func join(sending card: ShareableBrainCard) async throws -> ShareableBrainCard {
        try await simulateExchange()
    }

    private func simulateExchange() async throws -> ShareableBrainCard {
        try await Task.sleep(nanoseconds: 1_600_000_000)
        return DemoData.demoFriendCard(name: names.randomElement() ?? "Sam", id: UUID())
    }
}
