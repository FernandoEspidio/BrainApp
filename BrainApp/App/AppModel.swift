import Foundation
import Observation

/// Composition root. Decides which dataset is active (real or demo)
/// and which nearby exchange transports exist in this build.
@MainActor
@Observable
final class AppModel {
    private(set) var repository: LocalRepository
    private(set) var isDemoMode: Bool
    private(set) var nearby: NearbySharingCoordinator
    /// What the user chose to share (Friends tab). Every sharing flow uses it.
    var shareOptions = ShareOptions()

    private let realRepository: LocalRepository
    private static let demoModeKey = "demoMode"

    init(realStore: SnapshotStore? = nil) {
        // Created inside the (main-actor) body instead of as a default argument, which is evaluated nonisolated.
        let real = LocalRepository(store: realStore ?? FileSnapshotStore(), isDemo: false)
        let demo = UserDefaults.standard.bool(forKey: Self.demoModeKey)
        realRepository = real
        isDemoMode = demo
        repository = demo ? Self.makeDemoRepository() : real
        nearby = NearbySharingCoordinator(transports: NearbyTransportFactory.make(isDemo: demo))
    }

    /// Demo mode uses an in-memory store with fictional data.
    /// Real entries are not read, modified or mixed in.
    func setDemoMode(_ enabled: Bool) {
        guard enabled != isDemoMode else { return }
        nearby.cancel()
        isDemoMode = enabled
        UserDefaults.standard.set(enabled, forKey: Self.demoModeKey)
        repository = enabled ? Self.makeDemoRepository() : realRepository
        nearby = NearbySharingCoordinator(transports: NearbyTransportFactory.make(isDemo: enabled))
    }

    /// The card built from the user's current share choices.
    func makeCard() -> ShareableBrainCard { makeCard(options: shareOptions) }

    func makeCard(options: ShareOptions) -> ShareableBrainCard {
        BrainCardFactory.make(
            cardID: repository.snapshot.localCardID,
            appearance: repository.snapshot.companion,
            stage: repository.companionStage,
            discoveries: repository.rankedDiscoveries,
            options: options,
            isDemo: repository.isDemo,
            mood: repository.companionState().mood,
            rings: repository.rings(),
            animoji: repository.snapshot.animoji
        )
    }

    private static func makeDemoRepository() -> LocalRepository {
        LocalRepository(store: InMemorySnapshotStore(initial: DemoData.makeSnapshot()), isDemo: true)
    }
}
