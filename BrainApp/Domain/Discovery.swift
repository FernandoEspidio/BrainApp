import Foundation

/// Something the app recognizes in the entries. Each one states what it allows us to claim (level),
/// how well it holds up (status) and what it is based on (evidence).
struct Discovery: Identifiable, Hashable, Sendable {
    enum Level: String, Hashable, Sendable {
        case observation, provisionalPattern, possibleStrength

        var label: String {
            switch self {
            case .observation: return "Observation"
            case .provisionalPattern: return "Provisional pattern"
            case .possibleStrength: return "Possible strength"
            }
        }

        /// What each level allows us to claim (table in the base document).
        var meaning: String {
            switch self {
            case .observation: return "A summary of the available entries."
            case .provisionalPattern: return "An association that may change with new entries."
            case .possibleStrength: return "A hypothesis about a strength that needs your context; not a fixed label."
            }
        }

        var sortOrder: Int {
            switch self {
            case .possibleStrength: return 0
            case .provisionalPattern: return 1
            case .observation: return 2
            }
        }
    }

    /// Plain-language statuses, with no made-up confidence percentages.
    enum Status: String, Hashable, Sendable {
        case exploring, repeating, changing

        var label: String {
            switch self {
            case .exploring: return "Exploring"
            case .repeating: return "Repeats in your entries"
            case .changing: return "Changing"
            }
        }

        var symbol: String {
            switch self {
            case .exploring: return "magnifyingglass"
            case .repeating: return "repeat"
            case .changing: return "arrow.triangle.2.circlepath"
            }
        }
    }

    /// Identifies the rule (stable across recalculations).
    let id: String
    /// Changes when the conclusion changes (e.g. which time of day stands out). Used to detect
    /// changes against the reference the user has already seen.
    let signature: String
    let level: Level
    let title: String
    let summary: String
    let symbol: String
    let status: Status
    let evidence: Evidence
    let areaIDs: [String]
    /// Reveals schedules: excluded from sharing by default.
    let revealsSchedule: Bool
    /// Refers to sleep or health: never shared in this version.
    let usesHealthData: Bool
    let reflectionQuestion: String?
    let suggestedExperiment: ExperimentTemplate?
}

struct Evidence: Hashable, Sendable {
    struct Row: Hashable, Identifiable, Sendable {
        var id: String { label }
        let label: String
        let value: String
        let count: Int
        /// 0…1, used to draw a simple bar.
        var fraction: Double = 0
    }

    let periodStart: Date
    let periodEnd: Date
    let usableCount: Int
    let totalCount: Int
    let sources: [DataSource]
    let comparison: [Row]
    let limitations: [String]
    let activityIDs: [UUID]
}

/// A line between two areas on the map. It always points to a discovery and its evidence.
struct MapConnection: Identifiable, Hashable, Sendable {
    var id: String { "\(fromAreaID)-\(toAreaID)-\(discoveryID)" }
    let fromAreaID: String
    let toAreaID: String
    let discoveryID: String

    func involves(_ areaID: String) -> Bool { fromAreaID == areaID || toAreaID == areaID }
    func other(than areaID: String) -> String { fromAreaID == areaID ? toAreaID : fromAreaID }
}

struct InsightReport: Sendable {
    var discoveries: [Discovery] = []
    var connections: [MapConnection] = []
    var usableCount = 0
    var generatedAt: Date = .distantPast

    var isEarlyStage: Bool { usableCount < InsightThresholds.minimumActivitiesForPatterns }

    func discovery(id: String) -> Discovery? { discoveries.first { $0.id == id } }

    static let empty = InsightReport()
}
