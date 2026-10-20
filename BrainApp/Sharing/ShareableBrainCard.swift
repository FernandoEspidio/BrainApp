import Foundation

enum TransportKind: String, Codable, Sendable {
    case wifiAware, demo, multipeer, qrCode, peerToPeer

    var label: String {
        switch self {
        case .wifiAware: return "Wi-Fi Aware"
        case .demo: return "simulation"
        case .multipeer: return "Multipeer"
        case .qrCode: return "QR code"
        case .peerToPeer: return "peer-to-peer Wi-Fi"
        }
    }
}

/// One ring as shared: area and percentage only (no minutes, no moments).
struct SharedRing: Codable, Hashable, Sendable {
    var areaID: String
    var percent: Int
}

struct SharedHighlight: Codable, Hashable, Sendable {
    var title: String
    var symbol: String
    var levelLabel: String
}

/// The ONLY thing that leaves the device when sharing (exported image or nearby exchange).
/// By design it contains no entries, schedules, ratings, notes or health data:
/// only the companion's identity and what the user chose to include —
/// discoveries (traits), current mood, ring percentages and a short brain animoji.
/// The optional fields are new: older cards without them still decode.
struct ShareableBrainCard: Codable, Hashable, Identifiable, Sendable {
    static let currentVersion = 1

    var id: UUID
    var protocolVersion: Int
    var displayName: String
    var appearance: CompanionAppearance
    var stage: Int
    var stageName: String
    var highlights: [SharedHighlight]
    var createdAt: Date
    var isDemo: Bool
    /// `BrainMood` raw value.
    var mood: String?
    var rings: [SharedRing]?
    /// A few seconds of facial poses (~50 bytes each), played back as the brain animoji.
    var animoji: [FacePose]?

    var brainMood: BrainMood? { mood.flatMap(BrainMood.init(rawValue:)) }

    /// Data received from another device is untrusted: it is trimmed and normalized.
    func sanitized() -> ShareableBrainCard {
        var card = self
        card.displayName = String(displayName.prefix(40))
        card.appearance.name = String(appearance.name.prefix(40))
        card.appearance.colorIndex = max(0, min(appearance.colorIndex, 15))
        card.stage = max(0, min(stage, CompanionStage.names.count - 1))
        card.stageName = CompanionStage.name(card.stage)
        card.highlights = highlights.prefix(ShareOptions.maxHighlights).map { highlight in
            SharedHighlight(title: String(highlight.title.prefix(80)),
                            symbol: Self.safeSymbol(highlight.symbol),
                            levelLabel: String(highlight.levelLabel.prefix(30)))
        }
        if card.brainMood == nil { card.mood = nil }
        card.rings = rings.map { list in
            list.prefix(LifeArea.builtIns.count).map { SharedRing(areaID: String($0.areaID.prefix(40)), percent: max(0, min($0.percent, 999))) }
        }
        card.animoji = animoji.map { frames in frames.prefix(AnimojiClip.maxFrames).map { $0.clamped() } }
        return card
    }

    private static func safeSymbol(_ name: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789.")
        return name.count <= 40 && !name.isEmpty && name.allSatisfy { allowed.contains($0) } ? name : "sparkles"
    }
}

/// What the user chose to share. One set of choices, used by every sharing flow.
struct ShareOptions: Hashable {
    static let maxHighlights = 3
    var selectedDiscoveryIDs: [String] = []
    var includeSchedulePatterns = false
    var includeTraits = true
    var includeMood = true
    var includeRings = true
    var includeAnimoji = true
}

/// Builds the card applying the privacy filter.
enum BrainCardFactory {
    /// Discoveries that can be shared with these options.
    /// Health/sleep: never. Schedules: only if the user turns it on.
    static func shareable(_ discoveries: [Discovery], options: ShareOptions) -> [Discovery] {
        discoveries.filter { !$0.usesHealthData && (options.includeSchedulePatterns || !$0.revealsSchedule) }
    }

    static func defaultSelection(_ discoveries: [Discovery]) -> [String] {
        shareable(discoveries, options: ShareOptions()).prefix(ShareOptions.maxHighlights).map(\.id)
    }

    static func make(cardID: UUID, appearance: CompanionAppearance, stage: Int, discoveries: [Discovery],
                     options: ShareOptions, isDemo: Bool, mood: BrainMood? = nil, rings: [RingProgress] = [],
                     animoji: [FacePose] = [], now: Date = .now) -> ShareableBrainCard {
        let allowed = shareable(discoveries, options: options)
        // No explicit pick yet → the top shareable discoveries.
        let ids = options.selectedDiscoveryIDs.isEmpty ? defaultSelection(discoveries) : options.selectedDiscoveryIDs
        let chosen = options.includeTraits
            ? Array(ids.compactMap { id in allowed.first { $0.id == id } }.prefix(ShareOptions.maxHighlights))
            : []
        return ShareableBrainCard(
            id: cardID,
            protocolVersion: ShareableBrainCard.currentVersion,
            displayName: appearance.name,
            appearance: appearance,
            stage: stage,
            stageName: CompanionStage.name(stage),
            highlights: chosen.map { SharedHighlight(title: $0.title, symbol: $0.symbol, levelLabel: $0.level.label) },
            createdAt: now,
            isDemo: isDemo,
            mood: options.includeMood ? mood?.rawValue : nil,
            rings: options.includeRings && !rings.isEmpty
                ? rings.map { SharedRing(areaID: $0.area.id, percent: $0.percent) } : nil,
            animoji: options.includeAnimoji && !animoji.isEmpty ? animoji : nil
        )
    }
}

/// Nearby exchange protocol messages (transport-independent).
enum WireMessage: Codable, Sendable {
    case hello(ShareableBrainCard)
    case decline(reason: String)
}
