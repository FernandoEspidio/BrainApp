import Foundation

/// One day of Health numbers, plus BrainApp's own check-ins. A night counts for the morning it ends.
struct HealthDay: Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    var sleepMinutes: Int?
    /// Only time in bed was recorded (no Watch): an overestimate of sleep.
    var sleepIsTimeInBed = false
    var steps: Int?
    var exerciseMinutes: Int?
    var workoutMinutes = 0
    var mindfulMinutes = 0
    /// Average State of Mind logged that day, from -1 (very unpleasant) to 1 (very pleasant).
    var valence: Double?
    /// Average "How did it feel?" answer in BrainApp that day, 1 to 5. Not from Health.
    var feeling: Double?
    /// Answer to the goal's daily question, from 1 to the number of answers (see `Goal`). Not from Health.
    var answer: Double?
    /// Names of the activities logged by hand that day (see `HealthConnections.addingActivities`). Not from Health.
    var activities: Set<String> = []
}

/// SPIKE: connections built from Health history alone, so they can appear on day 1 without any ratings.
/// Each rule splits your days into two groups by one number and compares a second number between them.
/// PROVISIONAL thresholds, like `InsightThresholds`. If these hold up on real phones, they move into
/// `InsightEngine` as discoveries with evidence.
enum HealthConnections {
    static let minimumDaysPerGroup = 5
    /// Standardized difference (Cohen's d) before calling it a connection. 0.2 is small, 0.5 medium.
    static let minimumEffectSize = 0.4

    enum Metric: Hashable, Sendable {
        case sleep, steps, exercise, workout, mindful, mood, feeling, answer
        /// An activity logged by hand, by name: done that day or not.
        case activity(String)

        /// The rows of "Data found". `answer` and activities are left out: they belong to `HintEngine`.
        static let all: [Metric] = [.sleep, .steps, .exercise, .workout, .mindful, .mood, .feeling]

        /// Stable, for rule IDs: "steps", "activity.Play guitar".
        var id: String {
            switch self {
            case .sleep: return "sleep"
            case .steps: return "steps"
            case .exercise: return "exercise"
            case .workout: return "workout"
            case .mindful: return "mindful"
            case .mood: return "mood"
            case .feeling: return "feeling"
            case .answer: return "answer"
            case .activity(let name): return "activity.\(name)"
            }
        }

        func value(_ day: HealthDay) -> Double? {
            switch self {
            case .sleep: return day.sleepMinutes.map(Double.init)
            case .steps: return day.steps.map(Double.init)
            case .exercise: return day.exerciseMinutes.map(Double.init)
            case .workout: return Double(day.workoutMinutes)
            case .mindful: return Double(day.mindfulMinutes)
            case .mood: return day.valence
            case .feeling: return day.feeling
            case .answer: return day.answer
            case .activity(let name): return day.activities.contains(name) ? 1 : 0
            }
        }

        /// Scores have no meaningful percentage change.
        var isScore: Bool { self == .mood || self == .feeling || self == .answer }

        /// Yes/no metrics split into "with" and "without"; the others split at your own median.
        var isYesNo: Bool {
            switch self {
            case .workout, .mindful, .activity: return true
            default: return false
            }
        }

        var label: String {
            switch self {
            case .sleep: return "Sleep"
            case .steps: return "Steps"
            case .exercise: return "Exercise minutes"
            case .workout: return "Workouts"
            case .mindful: return "Mindful minutes"
            case .mood: return "Mood (State of Mind)"
            case .feeling: return "Check-ins (BrainApp)"
            case .answer: return "Daily answers (BrainApp)"
            case .activity(let name): return "“\(name)”"
            }
        }

        /// For "Days with …".
        var noun: String {
            switch self {
            case .workout: return "a workout"
            case .mindful: return "mindful minutes"
            case .activity: return label
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
            case .feeling: return "\(value.formatted(.number.precision(.fractionLength(1)))) of 5"
            case .answer: return value.formatted(.number.precision(.fractionLength(1)))
            case .activity: return value > 0 ? "done" : "not done"
            }
        }

        /// Where to split days: the median rounded to a number a person would say ("over 8,200 steps").
        func roundedSplit(_ median: Double) -> Double {
            switch self {
            case .steps: return (median / 100).rounded() * 100
            case .sleep: return (median / 5).rounded() * 5
            default: return median.rounded()
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
        Rule(id: "mindful.sleep", title: "Mindful minutes → sleep that night", cause: .mindful, effect: .sleep, effectNextDay: true),
        Rule(id: "steps.mood", title: "Steps → mood that day", cause: .steps, effect: .mood, effectNextDay: false),
        // iPhone only: steps and time in bed come free, the check-in is the second signal.
        Rule(id: "steps.feeling", title: "Steps → how your day felt", cause: .steps, effect: .feeling, effectNextDay: false),
        Rule(id: "sleep.feeling", title: "Sleep → how your day felt", cause: .sleep, effect: .feeling, effectNextDay: false)
    ]

    struct Group: Sendable {
        let label: String
        let days: Int
        let mean: Double
        /// The effect on each day of the group.
        let values: [Double]
    }

    enum Verdict: Sendable {
        case connection, tooWeak, notEnoughData
    }

    struct Result: Identifiable, Sendable {
        var id: String { rule.id }
        let rule: Rule
        /// The cause value days are split at: 0 for yes/no causes.
        let split: Double
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
            if !rule.effect.isScore, low.mean > 0 {
                text += " (\(sign)\(Int((abs(diff) / low.mean * 100).rounded()))%)"
            }
            return text
        }
    }

    /// Today is left out: its steps and exercise aren't finished yet.
    static func evaluate(_ days: [HealthDay], rules: [Rule] = HealthConnections.rules,
                         now: Date = .now, calendar: Calendar = .current) -> [Result] {
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

            let split = rule.cause.isYesNo ? 0 : rule.cause.roundedSplit(median(pairs.map(\.cause)))
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
            return Result(rule: rule, split: split,
                          high: Group(label: highLabel, days: high.count, mean: mean(high), values: high),
                          low: Group(label: lowLabel, days: low.count, mean: mean(low), values: low),
                          effectSize: d, verdict: verdict)
        }
    }

    /// Days that have each kind of data.
    static func coverage(_ days: [HealthDay]) -> [(metric: Metric, days: Int)] {
        Metric.all.map { metric in
            (metric, days.filter { metric.isScore ? metric.value($0) != nil : (metric.value($0) ?? 0) > 0 }.count)
        }
    }

    /// Adds BrainApp's "How did it feel?" answers: the second signal for people without a Watch.
    static func addingCheckIns(_ activities: [Activity], to days: [HealthDay], calendar: Calendar = .current) -> [HealthDay] {
        let rated = Dictionary(grouping: activities.filter { $0.enjoyment != nil }) { calendar.startOfDay(for: $0.date) }
        return days.map { day in
            var day = day
            if let ratings = rated[day.date]?.compactMap(\.enjoyment), !ratings.isEmpty {
                day.feeling = Double(ratings.reduce(0, +)) / Double(ratings.count)
            }
            return day
        }
    }

    /// Adds the activities logged by hand: the things you do, which Health doesn't see.
    /// Simulated and detected moments are left out. Names match ignoring case and spaces,
    /// and keep the first spelling logged.
    static func addingActivities(_ activities: [Activity], to days: [HealthDay], calendar: Calendar = .current) -> [HealthDay] {
        var names: [String: String] = [:]
        var logged: [Date: Set<String>] = [:]
        for activity in activities.filter({ $0.source == .manual }).sorted(by: { $0.date < $1.date }) {
            let title = activity.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let name = names[title.lowercased(), default: title]
            names[title.lowercased()] = name
            logged[calendar.startOfDay(for: activity.date), default: []].insert(name)
        }
        return days.map { day in
            var day = day
            day.activities = logged[day.date] ?? []
            return day
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
