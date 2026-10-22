import Foundation
import Observation

/// Composition root. Decides which dataset is active (real or demo)
/// and which nearby exchange transports exist in this build.
@MainActor
@Observable
final class AppModel {
    private(set) var repository: LocalRepository
    /// Which sample profile is showing (nil = your real data).
    private(set) var demoProfile: DemoProfile?
    private(set) var nearby: NearbySharingCoordinator
    /// What the user chose to share (Friends tab). Every sharing flow uses it.
    var shareOptions = ShareOptions()

    var isDemoMode: Bool { demoProfile != nil }

    private let realRepository: LocalRepository
    private static let demoProfileKey = "demoProfile"
    private static let legacyDemoModeKey = "demoMode"

    init(realStore: SnapshotStore? = nil) {
        // Created inside the (main-actor) body instead of as a default argument, which is evaluated nonisolated.
        let real = LocalRepository(store: realStore ?? FileSnapshotStore(), isDemo: false)
        let defaults = UserDefaults.standard
        var profile = defaults.string(forKey: Self.demoProfileKey).flatMap(DemoProfile.init(rawValue:))
        if profile == nil && defaults.bool(forKey: Self.legacyDemoModeKey) { profile = .full }
        realRepository = real
        demoProfile = profile
        repository = profile.map(Self.makeDemoRepository) ?? real
        nearby = NearbySharingCoordinator(transports: NearbyTransportFactory.make(isDemo: profile != nil))
    }

    /// Sample profiles use an in-memory store with fictional data.
    /// Real entries are not read, modified or mixed in.
    func setDemoProfile(_ profile: DemoProfile?) {
        guard profile != demoProfile else { return }
        nearby.cancel()
        demoProfile = profile
        let defaults = UserDefaults.standard
        defaults.set(profile?.rawValue, forKey: Self.demoProfileKey)
        defaults.removeObject(forKey: Self.legacyDemoModeKey)
        repository = profile.map(Self.makeDemoRepository) ?? realRepository
        shareOptions = ShareOptions()
        nearby = NearbySharingCoordinator(transports: NearbyTransportFactory.make(isDemo: profile != nil))
    }

    func setDemoMode(_ enabled: Bool) { setDemoProfile(enabled ? .full : nil) }

    /// A brain trade always looks for real nearby phones, also with a sample profile
    /// (so two phones in Demo can trade). "Practice" inside the trade uses a fictional friend.
    func makeBrainLink() -> BrainLinkSession {
        BrainLinkSession(mode: .network)
    }

    /// The card built from the user's current share choices.
    func makeCard() -> ShareableBrainCard { makeCard(options: shareOptions) }

    func makeCard(options: ShareOptions) -> ShareableBrainCard {
        BrainCardFactory.make(
            cardID: repository.snapshot.localCardID,
            appearance: repository.snapshot.companion,
            stage: repository.companionStage,
            discoveries: repository.rankedDiscoveries,
            hunches: repository.snapshot.hunches,
            options: options,
            isDemo: repository.isDemo,
            mood: repository.companionState().mood,
            rings: repository.rings(),
            animoji: repository.snapshot.animoji
        )
    }

    private static func makeDemoRepository(_ profile: DemoProfile) -> LocalRepository {
        let repo = LocalRepository(store: InMemorySnapshotStore(initial: DemoData.makeSnapshot(profile: profile)), isDemo: true)
        // Sample rings start already closed: don't greet the viewer with a stack of celebrations.
        for ring in repo.rings() where ring.isComplete { repo.markCelebrated(ring) }
        return repo
    }
}
