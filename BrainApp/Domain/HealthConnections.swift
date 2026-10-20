import Foundation

/// One day of Health numbers. A night counts for the morning it ends.
struct HealthDay: Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    var sleepMinutes: Int?
    var steps: Int?
    var exerciseMinutes: Int?
    var workoutMinutes = 0
    var mindfulMinutes = 0
    /// Average State of Mind logged that day, from -1 (very unpleasant) to 1 (very pleasant).
    var valence: Double?
}

/// SPIKE: connections built from Health history alone, so they can appear on day 1 without any ratings.
/// Each rule splits your days into two groups by one number and compares a second number between them.
/// PROVISIONAL thresholds, like `InsightThresholds`. If these hold up on real phones, they move into
/// `InsightEngine` as discoveries with evidence.
enum HealthConnections {
    static let minimumDaysPerGroup = 5
    /// Standardized difference (Cohen's d) before calling it a connection. 0.2 is small, 0.5 medium.
    static let minimumEffectSize = 0.4

    enum Metric: String, Sendable {
        case sleep, steps, exercise, workout, mindful, mood

        func value(_ day: HealthDay) -> Double? {
            switch self {
            case .sleep: return day.sleepMinutes.map(Double.init)
            case .steps: return day.steps.map(Double.init)
            case .exercise: return day.exerciseMinutes.map(Double.init)
            case .workout: return Double(day.workoutMinutes)
            case .mindful: return Double(day.mindfulMinutes)
            case .mood: return day.valence
            }
        }

        /// Yes/no metrics split into "with" and "without"; the others split at your own median.
        var isYesNo: Bool { self == .workout || self == .mindful }

        var label: String {
            switch self {
            case .sleep: return "Sleep"
            case .steps: return "Steps"
            case .exercise: return "Exercise minutes"
            case .workout: return "Workouts"
            case .mindful: return "Mindful minutes"
            case .mood: return "Mood (State of Mind)"
            }
        }

        /// For "Days with …".
        var noun: String {
            switch self {
            case .workout: return "a workout"
            case .mindful: return "mindful minutes"
            default: return label.lowercased()
            }
        }

        func format(_ value: Double) -> String {
            switch self {
            case .sleep:
                let minutes = Int(value.rounded())
                return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
            case .steps: return "\(Int(value.rounded()).formatted()) steps"
            case .exercise, .workout, .mindful: return "\(Int(value.rounded())) min"
            case .mood: return value.formatted(.number.precision(.fractionLength(2)))
            }
        }
    }

    struct Rule: Identifiable, Sendable {
        let id: String
        let title: String
        let cause: Metric
        let effect: Metric
        /// The effect is read on the next day: for sleep, the night after.
        let effectNextDay: Bool
    }

    static let rules: [Rule] = [
        Rule(id: "sleep.steps", title: "Sleep → steps that day", cause: .sleep, effect: .steps, effectNextDay: false),
        Rule(id: "sleep.exercise", title: "Sleep → exercise that day", cause: .sleep, effect: .exercise, effectNextDay: false),
        Rule(id: "sleep.mood", title: "Sleep → mood that day", cause: .sleep, effect: .mood, effectNextDay: false),
        Rule(id: "workout.sleep", title: "Workout → sleep that night", cause: .workout, effect: .sleep, effectNextDay: true),
        Rule(id: "steps.sleep", title: "Steps → sleep that night", cause: .steps, effect: .sleep, effectNextDay: true),
        Rule(id: "workout.mood", title: "Workout → mood that day", cause: .workout, effect: .mood, effectNextDay: false),
        Rule(id: "mindful.sleep", title: "Mindful minutes → sleep that night", cause: .mindful, effect: .sleep, effectNextDay: true)
    ]

    struct Group: Sendable {
        let label: String
        let days: Int
        let mean: Double
    }

    enum Verdict: Sendable {
        case connection, tooWeak, notEnoughData
    }

    struct Result: Identifiable, Sendable {
        var id: String { rule.id }
        let rule: Rule
        /// Days with more of the cause (over the median, or "with").
        let high: Group
        let low: Group
        /// Cohen's d, high minus low: the difference in units of day-to-day spread.
        let effectSize: Double
        let verdict: Verdict

        /// "+1,240 steps (+16%)".
        var differenceText: String {
            let diff = high.mean - low.mean
            let sign = diff >= 0 ? "+" : "−"
            var text = sign + rule.effect.format(abs(diff))
            if rule.effect != .mood, low.mean > 0 {
                text += " (\(sign)\(Int((abs(diff) / low.mean * 100).rounded()))%)"
            }
            return text
        }
    }

    /// Today is left out: its steps and exercise aren't finished yet.
    static func evaluate(_ days: [HealthDay], now: Date = .now, calendar: Calendar = .current) -> [Result] {
        let today = calendar.startOfDay(for: now)
        let past = days.filter { $0.date < today }
        let byDate = Dictionary(uniqueKeysWithValues: past.map { ($0.date, $0) })

        return rules.map { rule in
            let pairs: [(cause: Double, effect: Double)] = past.compactMap { day in
                guard let cause = rule.cause.value(day) else { return nil }
                let effectDay = rule.effectNextDay
                    ? calendar.date(byAdding: .day, value: 1, to: day.date).flatMap { byDate[$0] }
                    : day
                guard let effectDay, let effect = rule.effect.value(effectDay) else { return nil }
                return (cause, effect)
            }

            let split = rule.cause.isYesNo ? 0 : median(pairs.map(\.cause))
            let high = pairs.filter { $0.cause > split }.map(\.effect)
            let low = pairs.filter { $0.cause <= split }.map(\.effect)
            let highLabel = rule.cause.isYesNo ? "Days with \(rule.cause.noun)" : "Over \(rule.cause.format(split))"
            let lowLabel = rule.cause.isYesNo ? "Days without" : "\(rule.cause.format(split)) or less"

            let d = effectSize(high, low)
            let verdict: Verdict
            if high.count < minimumDaysPerGroup || low.count < minimumDaysPerGroup {
                verdict = .notEnoughData
            } else {
                verdict = abs(d) >= minimumEffectSize ? .connection : .tooWeak
            }
            return Result(rule: rule,
                          high: Group(label: highLabel, days: high.count, mean: mean(high)),
                          low: Group(label: lowLabel, days: low.count, mean: mean(low)),
                          effectSize: d, verdict: verdict)
        }
    }

    /// Days that have each kind of data.
    static func coverage(_ days: [HealthDay]) -> [(metric: Metric, days: Int)] {
        [Metric.sleep, .steps, .exercise, .workout, .mindful, .mood].map { metric in
            (metric, days.filter { (metric.value($0) ?? 0) > 0 || (metric == .mood && $0.valence != nil) }.count)
        }
    }

    // MARK: - Helpers

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    private static func effectSize(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count > 1, b.count > 1 else { return 0 }
        func variance(_ values: [Double]) -> Double {
            let m = mean(values)
            return values.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(values.count - 1)
        }
        let pooled = (Double(a.count - 1) * variance(a) + Double(b.count - 1) * variance(b)) / Double(a.count + b.count - 2)
        return pooled > 0 ? (mean(a) - mean(b)) / pooled.squareRoot() : 0
    }
}
