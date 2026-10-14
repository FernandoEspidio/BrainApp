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

struct SharedHighlight: Codable, Hashable, Sendable {
    var title: String
    var symbol: String
    var levelLabel: String
}

/// The ONLY thing that leaves the device when sharing (exported image or nearby exchange).
/// By design it contains no entries, schedules, ratings, notes or health data:
/// only the companion's identity and the titles of chosen discoveries.
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
        return card
    }

    private static func safeSymbol(_ name: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789.")
        return name.count <= 40 && !name.isEmpty && name.allSatisfy { allowed.contains($0) } ? name : "sparkles"
    }
}

struct ShareOptions: Hashable {
    static let maxHighlights = 3
    var selectedDiscoveryIDs: [String] = []
    var includeSchedulePatterns = false
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
                     options: ShareOptions, isDemo: Bool, now: Date = .now) -> ShareableBrainCard {
        let allowed = shareable(discoveries, options: options)
        let chosen = options.selectedDiscoveryIDs
            .compactMap { id in allowed.first { $0.id == id } }
            .prefix(ShareOptions.maxHighlights)
        return ShareableBrainCard(
            id: cardID,
            protocolVersion: ShareableBrainCard.currentVersion,
            displayName: appearance.name,
            appearance: appearance,
            stage: stage,
            stageName: CompanionStage.name(stage),
            highlights: chosen.map { SharedHighlight(title: $0.title, symbol: $0.symbol, levelLabel: $0.level.label) },
            createdAt: now,
            isDemo: isDemo
        )
    }
}

/// Nearby exchange protocol messages (transport-independent).
enum WireMessage: Codable, Sendable {
    case hello(ShareableBrainCard)
    case decline(reason: String)
}
