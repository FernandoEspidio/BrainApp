import Foundation
import Observation

/// Observable source of truth for one dataset (real or demo).
/// Every change recomputes discoveries on device and is saved locally.
@MainActor
@Observable
final class LocalRepository {
    private(set) var snapshot: AppSnapshot
    private(set) var report: InsightReport = .empty
    var lastError: String? = nil
    let isDemo: Bool
    /// Check-ins the user skipped this session (not persisted: skipping is not a statement).
    private(set) var skippedCheckIns: Set<UUID> = []

    private let store: SnapshotStore
    private let engine: InsightEngine
    private let simulator = PhoneSensingSimulator()

    init(store: SnapshotStore, isDemo: Bool, engine: InsightEngine? = nil) {
        self.store = store
        self.isDemo = isDemo
        self.engine = engine ?? InsightEngine()

        var loaded = AppSnapshot()
        var loadError: String?
        do {
            if let existing = try store.load() { loaded = existing }
        } catch {
            (store as? FileSnapshotStore)?.quarantineUnreadableFile()
            loadError = "Your saved entries couldn't be read. The file was set aside (not deleted) and the app started empty."
        }
        self.snapshot = loaded
        self.lastError = loadError
        syncDetections()
        refreshInsights()
        updateUnderstanding()
    }

    // MARK: - Reads

    var areas: [LifeArea] { LifeArea.builtIns + snapshot.customAreas }

    func area(id: String) -> LifeArea { areas.first { $0.id == id } ?? .unknown(id: id) }

    func priority(for areaID: String) -> Priority { snapshot.priorities[areaID] ?? .some }

    var openExperiment: Experiment? { snapshot.experiments.first { $0.isOpen } }

    func experiment(id: UUID) -> Experiment? { snapshot.experiments.first { $0.id == id } }

    func feedback(for discoveryID: String) -> DiscoveryFeedback { snapshot.feedback[discoveryID] ?? DiscoveryFeedback() }

    var companionStage: Int { CompanionStage.stage(forUnderstanding: snapshot.understandingHighWater) }

    // MARK: - Passive sensing (simulated in this prototype)

    /// Imports moments "detected by the phone" since sensing started. Idempotent.
    func syncDetections(now: Date = .now) {
        guard !isDemo, snapshot.simulateSensing, snapshot.hasCompletedOnboarding,
              let start = snapshot.sensingStartDate else { return }
        let existing = Set(snapshot.activities.map(\.id))
        let fresh = simulator.moments(from: start, through: now)
            .filter { !existing.contains($0.id) && !snapshot.dismissedDetections.contains($0.id) }
        guard !fresh.isEmpty else { return }
        mutate { $0.activities.append(contentsOf: fresh) }
    }

    func setSimulateSensing(_ enabled: Bool) {
        mutate(refresh: false) { s in
            s.simulateSensing = enabled
            if enabled && s.sensingStartDate == nil { s.sensingStartDate = Calendar.current.startOfDay(for: .now) }
        }
        if enabled { syncDetections() }
    }

    // MARK: - Entries

    func add(_ activity: Activity) {
        mutate { $0.activities.append(activity) }
    }

    func update(_ activity: Activity) {
        mutate { s in
            guard let index = s.activities.firstIndex(where: { $0.id == activity.id }) else { return }
            var updated = activity
            updated.updatedAt = .now
            s.activities[index] = updated
        }
    }

    func deleteActivities(_ ids: Set<UUID>) {
        mutate { s in
            let detected = s.activities.filter { ids.contains($0.id) && $0.isDetected }.map(\.id)
            s.dismissedDetections.formUnion(detected)
            s.activities.removeAll { ids.contains($0.id) }
        }
    }

    /// One-tap check-in: "How did it feel?"
    func setFeeling(_ enjoyment: Int, for activityID: UUID) {
        mutate { s in
            guard let index = s.activities.firstIndex(where: { $0.id == activityID }) else { return }
            s.activities[index].enjoyment = enjoyment
            s.activities[index].updatedAt = .now
        }
    }

    func skipCheckIn(_ activityID: UUID) {
        skippedCheckIns.insert(activityID)
    }

    // MARK: - Areas and priorities

    func setPriority(_ priority: Priority, for areaID: String) {
        mutate(refresh: false) { $0.priorities[areaID] = priority }
    }

    @discardableResult
    func addCustomArea(name: String, symbol: String) -> LifeArea {
        let area = LifeArea(id: UUID().uuidString, name: name, symbol: symbol, isBuiltIn: false,
                            paletteIndex: 5 + snapshot.customAreas.count)
        mutate { $0.customAreas.append(area) }
        return area
    }

    func canDeleteArea(_ id: String) -> Bool { !snapshot.activities.contains { $0.areaID == id } }

    func deleteCustomArea(_ id: String) {
        guard canDeleteArea(id) else { return }
        mutate { s in
            s.customAreas.removeAll { $0.id == id }
            s.priorities[id] = nil
        }
    }

    // MARK: - Experiments

    func startExperiment(_ experiment: Experiment) {
        guard openExperiment == nil else { return }
        mutate(refresh: false) { $0.experiments.append(experiment) }
    }

    func updateExperiment(_ experiment: Experiment) {
        mutate(refresh: false) { s in
            guard let index = s.experiments.firstIndex(where: { $0.id == experiment.id }) else { return }
            s.experiments[index] = experiment
        }
    }

    // MARK: - Discoveries

    func setFeedback(_ feedback: DiscoveryFeedback, for discoveryID: String) {
        mutate(refresh: false) { $0.feedback[discoveryID] = feedback }
    }

    /// Saves the discovery's current reference so later changes can be detected.
    func markSeen(_ discovery: Discovery) {
        guard snapshot.seenDiscoveries[discovery.id]?.signature != discovery.signature else { return }
        mutate(refresh: false) {
            $0.seenDiscoveries[discovery.id] = SeenDiscovery(signature: discovery.signature, title: discovery.title, seenAt: .now)
        }
    }

    // MARK: - Companion, profile and first run

    func updateCompanion(_ appearance: CompanionAppearance) {
        guard appearance != snapshot.companion else { return }
        mutate(refresh: false) { $0.companion = appearance }
    }

    func setUserName(_ name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        guard trimmed != snapshot.userName else { return }
        mutate(refresh: false) { $0.userName = trimmed }
    }

    func completeOnboarding(simulateSensing: Bool) {
        mutate(refresh: false) { s in
            s.hasCompletedOnboarding = true
            s.simulateSensing = simulateSensing
            s.sensingStartDate = s.sensingStartDate ?? Calendar.current.startOfDay(for: .now)
        }
        syncDetections()
    }

    // MARK: - Friends

    func addFriend(_ card: ShareableBrainCard, via transport: TransportKind) {
        let safe = card.sanitized()
        mutate(refresh: false) { s in
            s.friends.removeAll { $0.card.id == safe.id }
            s.friends.insert(Friend(card: safe, receivedAt: .now, via: transport), at: 0)
        }
    }

    func removeFriend(_ id: UUID) {
        mutate(refresh: false) { $0.friends.removeAll { $0.id == id } }
    }

    // MARK: - Ring goals

    func setGoal(_ goal: AreaGoal, for areaID: String) {
        mutate(refresh: false) { $0.goals[areaID] = goal }
    }

    /// Records that a ring completion was celebrated, so it doesn't fire again.
    func markCelebrated(_ ring: RingProgress) {
        mutate(refresh: false) { $0.celebratedRings.insert(ring.celebrationKey) }
    }

    // MARK: - Brain animoji

    func setAnimoji(_ frames: [FacePose]) {
        mutate(refresh: false) { $0.animoji = Array(frames.prefix(AnimojiClip.maxFrames)) }
    }

    // MARK: - Erase

    func eraseAll() {
        do {
            try store.erase()
        } catch {
            lastError = "Couldn't erase the data: \(error.localizedDescription)"
        }
        snapshot = AppSnapshot()
        skippedCheckIns = []
        refreshInsights()
    }

    // MARK: - Internal

    private func mutate(refresh: Bool = true, _ change: (inout AppSnapshot) -> Void) {
        change(&snapshot)
        if refresh { refreshInsights() }
        updateUnderstanding()
        persist()
    }

    private func refreshInsights() {
        report = engine.analyze(activities: snapshot.activities, areas: areas, now: .now)
    }

    /// Understanding points (provisional): areas with ≥3 entries, discoveries,
    /// finished experiments and added reflections.
    private func updateUnderstanding() {
        let areasWithData = Dictionary(grouping: snapshot.activities, by: \.areaID).filter { $0.value.count >= 3 }.count
        let discoveries = report.discoveries.count * 2
        let finished = snapshot.experiments.filter { $0.status == .finished }.count * 2
        let reflections = snapshot.feedback.values.filter { !$0.context.isEmpty }.count
        let points = areasWithData + discoveries + finished + reflections
        if points > snapshot.understandingHighWater {
            snapshot.understandingHighWater = points
        }
    }

    private func persist() {
        do {
            try store.save(snapshot)
        } catch {
            lastError = "Couldn't save on this device: \(error.localizedDescription)"
        }
    }
}
