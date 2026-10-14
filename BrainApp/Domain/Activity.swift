import Foundation

/// Short, optional measures the user can rate from 1 to 5.
enum Measure: String, Codable, CaseIterable, Identifiable, Sendable {
    case focus, energy, enjoyment

    var id: String { rawValue }

    var label: String {
        switch self {
        case .focus: return "Focus"
        case .energy: return "Energy"
        case .enjoyment: return "Enjoyment"
        }
    }

    /// Lowercase form for use inside sentences.
    var inSentence: String { label.lowercased() }

    var symbol: String {
        switch self {
        case .focus: return "scope"
        case .energy: return "bolt"
        case .enjoyment: return "face.smiling"
        }
    }
}

/// Where each observation came from. Always stored so it can be explained.
enum DataSource: String, Codable, CaseIterable, Sendable {
    case manual, healthKit, demo, phone

    var label: String {
        switch self {
        case .manual: return "Added by you"
        case .healthKit: return "Health (HealthKit)"
        case .demo: return "Fictional example"
        case .phone: return "Detected by your phone (simulated)"
        }
    }
}

/// How the phone noticed a moment. The prototype ASSUMES these signals exist
/// (sleep tracking, motion, Screen Time…); see `PhoneSensingSimulator`.
enum Detection: String, Codable, CaseIterable, Sendable {
    case sleep, walk, workout, reading, focusSession, call

    var label: String {
        switch self {
        case .sleep: return "Sleep tracking"
        case .walk: return "Motion"
        case .workout: return "Workout detection"
        case .reading: return "Reading app time"
        case .focusSession: return "Focus mode"
        case .call: return "Calls"
        }
    }

    var symbol: String {
        switch self {
        case .sleep: return "moon.zzz.fill"
        case .walk: return "figure.walk"
        case .workout: return "dumbbell.fill"
        case .reading: return "book.fill"
        case .focusSession: return "scope"
        case .call: return "phone.fill"
        }
    }
}

/// A logged experience. The minimum is activity + time + area;
/// duration and ratings are optional, depending on what the user wants to explore.
struct Activity: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var areaID: String
    /// Start time.
    var date: Date
    var durationMinutes: Int?
    var focus: Int?
    var energy: Int?
    var enjoyment: Int?
    var note: String
    var source: DataSource
    /// true if the area came from the automatic suggestion and the user kept it.
    var areaWasSuggested: Bool
    var experimentID: UUID?
    var experimentArm: Experiment.Arm?
    /// Set when the phone detected this moment instead of the user logging it.
    var detection: Detection?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        areaID: String,
        date: Date,
        durationMinutes: Int? = nil,
        focus: Int? = nil,
        energy: Int? = nil,
        enjoyment: Int? = nil,
        note: String = "",
        source: DataSource = .manual,
        areaWasSuggested: Bool = false,
        experimentID: UUID? = nil,
        experimentArm: Experiment.Arm? = nil,
        detection: Detection? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.areaID = areaID
        self.date = date
        self.durationMinutes = durationMinutes
        self.focus = focus
        self.energy = energy
        self.enjoyment = enjoyment
        self.note = note
        self.source = source
        self.areaWasSuggested = areaWasSuggested
        self.experimentID = experimentID
        self.experimentArm = experimentArm
        self.detection = detection
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var endDate: Date { date.addingTimeInterval(Double(durationMinutes ?? 0) * 60) }

    var isDetected: Bool { detection != nil }

    /// Icon for lists and chips: the detection icon, or the area's.
    func symbol(area: LifeArea) -> String { detection?.symbol ?? area.symbol }

    func rating(_ measure: Measure) -> Int? {
        switch measure {
        case .focus: return focus
        case .energy: return energy
        case .enjoyment: return enjoyment
        }
    }
}
