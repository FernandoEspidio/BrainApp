import Foundation

/// A goal for one life area, like an Apple Fitness ring.
/// Progress always comes from real moments (logged or detected), never from taps on the ring.
struct AreaGoal: Codable, Hashable, Sendable {
    enum Unit: String, Codable, CaseIterable, Identifiable, Sendable {
        case minutes, moments
        var id: String { rawValue }
        var label: String { self == .minutes ? "Minutes" : "Moments" }
    }

    enum Period: String, Codable, CaseIterable, Identifiable, Sendable {
        case day, week
        var id: String { rawValue }
        var label: String { self == .day ? "Daily" : "Weekly" }
        var short: String { self == .day ? "today" : "this week" }
    }

    var target: Int
    var unit: Unit
    var period: Period

    /// Sensible starting points; the user can change them in the ring's detail.
    static func defaultGoal(for areaID: String) -> AreaGoal {
        switch areaID {
        case LifeArea.rest.id: return AreaGoal(target: 420, unit: .minutes, period: .day)
        case LifeArea.learning.id: return AreaGoal(target: 45, unit: .minutes, period: .day)
        case LifeArea.movement.id: return AreaGoal(target: 30, unit: .minutes, period: .day)
        case LifeArea.creativity.id: return AreaGoal(target: 2, unit: .moments, period: .week)
        case LifeArea.social.id: return AreaGoal(target: 3, unit: .moments, period: .week)
        default: return AreaGoal(target: 3, unit: .moments, period: .week)
        }
    }

    /// Stepper bounds and step for the current unit.
    var range: ClosedRange<Int> { unit == .minutes ? 5...900 : 1...50 }
    var step: Int { unit == .minutes ? (target >= 120 ? 30 : 5) : 1 }

    func format(_ value: Int) -> String {
        unit == .minutes ? formatMinutes(value) : "\(value)"
    }

    /// Moments without a duration count as this many minutes toward a minutes goal.
    static let assumedMinutesWithoutDuration = 15
}

/// Current state of one ring.
struct RingProgress: Identifiable, Hashable, Sendable {
    var id: String { area.id }
    let area: LifeArea
    let goal: AreaGoal
    let value: Int
    let periodStart: Date

    var fraction: Double { goal.target > 0 ? Double(value) / Double(goal.target) : 0 }
    var percent: Int { Int((fraction * 100).rounded()) }
    var isComplete: Bool { value >= goal.target }
    var remaining: Int { max(goal.target - value, 0) }

    /// "45m / 1h" or "2 / 3".
    var valueText: String { "\(goal.format(value)) / \(goal.format(goal.target))" }

    /// Identifies "this goal, this period": each one celebrates once.
    var celebrationKey: String {
        "\(area.id)|\(goal.period.rawValue)|\(goal.unit.rawValue)|\(goal.target)|\(Int(periodStart.timeIntervalSince1970))"
    }
}

/// One past (or the current) period of a ring, for the history dots.
struct PeriodResult: Identifiable, Hashable, Sendable {
    var id: Date { start }
    let start: Date
    let fraction: Double
    var isComplete: Bool { fraction >= 1 }
}
