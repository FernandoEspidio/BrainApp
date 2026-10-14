import Foundation

/// Reference to what the user has already seen of a discovery, used to detect later changes.
struct SeenDiscovery: Codable, Hashable, Sendable {
    var signature: String
    var title: String
    var seenAt: Date
}

/// The user's opinion about a discovery. Stored separately from the evidence.
struct DiscoveryFeedback: Codable, Hashable, Sendable {
    var context: String = ""
    var notRepresentative: Bool = false
    var updatedAt: Date = .now
}

struct Friend: Identifiable, Codable, Hashable, Sendable {
    var id: UUID { card.id }
    var card: ShareableBrainCard
    var receivedAt: Date
    var via: TransportKind
}

/// Everything the app stores on the device. A single versioned document.
struct AppSnapshot: Codable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion = AppSnapshot.currentSchemaVersion
    var activities: [Activity] = []
    var customAreas: [LifeArea] = []
    var priorities: [String: Priority] = [:]
    var experiments: [Experiment] = []
    var feedback: [String: DiscoveryFeedback] = [:]
    var seenDiscoveries: [String: SeenDiscovery] = [:]
    var companion = CompanionAppearance()
    /// Understanding high-water mark: the companion never regresses because of inactivity.
    var understandingHighWater = 0
    var friends: [Friend] = []
    /// ID of this device's shareable card (does not identify the person).
    var localCardID = UUID()
    var hasCompletedOnboarding = false
    /// What the companion calls the user ("Hi, Fer").
    var userName = ""
    /// Prototype: the phone's passive detection is simulated (see PhoneSensingSimulator).
    var simulateSensing = true
    var sensingStartDate: Date?
    /// Detections the user deleted, so the simulator doesn't bring them back.
    var dismissedDetections: Set<UUID> = []

    init() {}

    enum CodingKeys: String, CodingKey {
        case schemaVersion, activities, customAreas, priorities, experiments, feedback,
             seenDiscoveries, companion, understandingHighWater, friends, localCardID, hasCompletedOnboarding,
             userName, simulateSensing, sensingStartDate, dismissedDetections
    }

    /// Tolerant decoding: missing keys take their default value.
    /// Lets future versions add fields without breaking existing data.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSnapshot()
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? d.schemaVersion
        activities = try c.decodeIfPresent([Activity].self, forKey: .activities) ?? d.activities
        customAreas = try c.decodeIfPresent([LifeArea].self, forKey: .customAreas) ?? d.customAreas
        priorities = try c.decodeIfPresent([String: Priority].self, forKey: .priorities) ?? d.priorities
        experiments = try c.decodeIfPresent([Experiment].self, forKey: .experiments) ?? d.experiments
        feedback = try c.decodeIfPresent([String: DiscoveryFeedback].self, forKey: .feedback) ?? d.feedback
        seenDiscoveries = try c.decodeIfPresent([String: SeenDiscovery].self, forKey: .seenDiscoveries) ?? d.seenDiscoveries
        companion = try c.decodeIfPresent(CompanionAppearance.self, forKey: .companion) ?? d.companion
        understandingHighWater = try c.decodeIfPresent(Int.self, forKey: .understandingHighWater) ?? d.understandingHighWater
        friends = try c.decodeIfPresent([Friend].self, forKey: .friends) ?? d.friends
        localCardID = try c.decodeIfPresent(UUID.self, forKey: .localCardID) ?? d.localCardID
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? d.hasCompletedOnboarding
        userName = try c.decodeIfPresent(String.self, forKey: .userName) ?? d.userName
        simulateSensing = try c.decodeIfPresent(Bool.self, forKey: .simulateSensing) ?? d.simulateSensing
        sensingStartDate = try c.decodeIfPresent(Date.self, forKey: .sensingStartDate)
        dismissedDetections = try c.decodeIfPresent(Set<UUID>.self, forKey: .dismissedDetections) ?? d.dismissedDetections
    }
}
