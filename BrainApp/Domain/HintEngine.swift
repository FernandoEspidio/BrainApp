import Foundation

/// The sentence between the data and the person: one connection to their goal, said the way a person
/// would say it, one number that makes it believable, and one thing to do about it.
/// It says "came with", never "caused": one person's days can't show a cause.
struct Hint: Identifiable, Sendable {
    /// How well the days back it up.
    enum Strength: Int, Comparable, Sendable {
        case hunch, pattern, strongPattern

        var label: String {
            switch self {
            case .hunch: return "Hunch"
            case .pattern: return "Pattern"
            case .strongPattern: return "Strong pattern"
            }
        }

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var id: String { result.id }
    let strength: Strength
    /// "Nights over 7h came with better study days."
    let sentence: String
    /// "5 of 6 good study days vs 2 of 7".
    let number: String
    /// What protects the goal, when the better side is something you can do today. Nil otherwise, and
    /// always nil for a hunch: on test data many are luck ("Make time for groceries"), so they get tested, not acted on.
    let action: String?
    /// The comparison behind it, for "Why?".
    let result: HealthConnections.Result
}

/// What Today can say for a goal.
enum HintState: Sendable {
    /// The strongest hint, then the others from strongest to weakest.
    case hint(Hint, others: [Hint])
    /// Too few days yet. `checkIns` is true when the missing days are answers to the daily question.
    case waiting(daysLeft: Int, checkIns: Bool)
    /// Enough days, but nothing stands out.
    case nothingYet
    /// Only one signal, so nothing to compare it with: exercise on an iPhone alone, for example.
    case needsSignal

    /// What the buddy says on Today.
    func headline(for goal: Goal) -> String {
        switch self {
        case .hint(let hint, _):
            return hint.sentence
        case .waiting(let daysLeft, let checkIns):
            let wait = checkIns ? countLabel(daysLeft, "more check-in", "more check-ins") : countLabel(daysLeft, "more day", "more days")
            return "\(wait) and I'll tell you what comes with \(goal.change(better: true))."
        case .nothingYet:
            return "Nothing stands out yet. More days will show smaller differences."
        case .needsSignal:
            return "I need something to compare with \(goal.noun): Screen Time or an Apple Watch."
        }
    }
}

/// Turns Health days and daily answers into hints for one goal.
/// PROVISIONAL thresholds, like `HealthConnections`: tune them on real phones.
enum HintEngine {
    /// Days with both numbers before a hunch is possible: three per group.
    static let daysForFirstHint = 6
    /// Each comparison is another chance of a hit by luck, so only the most frequent activities are compared.
    static let maxActivities = 5

    static func state(for goal: Goal, days: [HealthDay], now: Date = .now, calendar: Calendar = .current) -> HintState {
        let outcome = outcome(for: goal, days: days)
        // A cause with no data at all can't be compared, and leaving it out keeps chance hits down.
        let available = causes(for: goal, outcome: outcome, days: days).filter { cause in days.contains { (cause.value($0) ?? 0) > 0 } }
        guard !available.isEmpty else { return .needsSignal }

        // For sleep, the cause is the day before the night (a night counts for the morning it ends).
        let rules = available.map { cause in
            HealthConnections.Rule(id: "\(goal.rawValue).\(cause.id)", title: "\(cause.label) → \(goal.label)",
                                   cause: cause, effect: outcome, effectNextDay: goal == .sleep)
        }
        let results = HealthConnections.evaluate(days, rules: rules, now: now, calendar: calendar)
        let hints = results.compactMap { hint(from: $0, goal: goal) }
            .sorted { ($0.strength, abs($0.result.effectSize)) > ($1.strength, abs($1.result.effectSize)) }
        if let first = hints.first {
            return .hint(first, others: Array(hints.dropFirst()))
        }
        let pairedDays = results.map { $0.high.days + $0.low.days }.max() ?? 0
        return pairedDays < daysForFirstHint
            ? .waiting(daysLeft: daysForFirstHint - pairedDays, checkIns: outcome == .answer)
            : .nothingYet
    }

    /// What the hints are about: the daily answer, or Health's own number when it measures the goal.
    static func outcome(for goal: Goal, days: [HealthDay]) -> HealthConnections.Metric {
        switch goal {
        case .feel, .focus, .energy:
            return .answer
        case .sleep:
            // Time in bed alone overestimates sleep: the morning question is better.
            return days.contains { $0.sleepMinutes != nil && !$0.sleepIsTimeInBed } ? .sleep : .answer
        case .exercise:
            return days.contains { ($0.exerciseMinutes ?? 0) > 0 } ? .exercise : .steps
        }
    }

    /// The days' strength: the difference against its own uncertainty (a t statistic),
    /// so few days need a big difference.
    static func strength(_ result: HealthConnections.Result) -> Hint.Strength? {
        let high = Double(result.high.days), low = Double(result.low.days)
        let smaller = min(high, low)
        guard smaller >= 3 else { return nil }
        let t = abs(result.effectSize) / (1 / high + 1 / low).squareRoot()
        if smaller >= 7, t >= 2.5 { return .strongPattern }
        if smaller >= 5, t >= 1.7 { return .pattern }
        return t >= 1 ? .hunch : nil
    }

    // MARK: - Sentences

    /// Health's numbers, then the activities logged on at least 3 days, most frequent first.
    /// Steps and exercise minutes measure the same movement, and a workout is exercise: neither explains the other.
    private static func causes(for goal: Goal, outcome: HealthConnections.Metric, days: [HealthDay]) -> [HealthConnections.Metric] {
        var causes: [HealthConnections.Metric] = [.sleep, .steps, .exercise, .workout, .mindful]
        if goal == .sleep { causes.removeAll { $0 == .sleep } }
        if outcome == .steps || outcome == .exercise { causes.removeAll { [.steps, .exercise, .workout].contains($0) } }

        var counts: [String: Int] = [:]
        for day in days {
            for name in day.activities { counts[name, default: 0] += 1 }
        }
        let activities = counts.filter { $0.value >= 3 }
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(maxActivities)
            .map { HealthConnections.Metric.activity($0.key) }
        return causes + activities
    }

    private static func hint(from result: HealthConnections.Result, goal: Goal) -> Hint? {
        guard let strength = strength(result) else { return nil }
        // Every outcome is better when higher: more sleep, more steps, a better answer.
        let better = result.effectSize > 0
        var sentence = "\(causePhrase(result)) came with \(effectPhrase(result, goal: goal, better: better))"
        if result.rule.effectNextDay { sentence += " that night" }
        return Hint(strength: strength, sentence: sentence + ".", number: number(result, goal: goal),
                    action: better && strength >= .pattern ? action(for: result.rule.cause) : nil, result: result)
    }

    /// "Nights over 7h 10m", "Days over 8,200 steps", "Days with a workout", "Days with “Play guitar”".
    private static func causePhrase(_ result: HealthConnections.Result) -> String {
        let cause = result.rule.cause
        switch cause {
        case .sleep: return "Nights over \(cause.format(result.split))"
        case .workout, .mindful, .activity: return "Days with \(cause.noun)"
        case .exercise: return "Days over \(Int(result.split)) exercise minutes"
        default: return "Days over \(cause.format(result.split))"
        }
    }

    /// "better study days", "35m more sleep", "1,200 more steps".
    private static func effectPhrase(_ result: HealthConnections.Result, goal: Goal, better: Bool) -> String {
        let effect = result.rule.effect
        let difference = abs(result.high.mean - result.low.mean)
        switch effect {
        case .sleep: return "\(effect.format(difference)) \(better ? "more" : "less") sleep"
        case .steps: return "\(Int(difference.rounded()).formatted()) \(better ? "more" : "fewer") steps"
        case .exercise: return "\(Int(difference.rounded())) \(better ? "more" : "fewer") exercise minutes"
        default: return goal.change(better: better)
        }
    }

    /// Counts of good days when they agree with the averages, since counts are easier to believe.
    /// Otherwise the two averages.
    private static func number(_ result: HealthConnections.Result, goal: Goal) -> String {
        let high = result.high, low = result.low
        let unit = result.rule.cause == .sleep ? "nights" : "days"
        let effect = result.rule.effect
        guard effect == .answer else {
            return "\(effect.format(high.mean)) vs \(effect.format(low.mean)) · \(high.days) vs \(low.days) \(unit)"
        }
        let highGood = high.values.filter { $0 >= goal.goodAnswer }.count
        let lowGood = low.values.filter { $0 >= goal.goodAnswer }.count
        let shareDifference = Double(highGood) / Double(high.days) - Double(lowGood) / Double(low.days)
        if shareDifference * result.effectSize > 0 {
            return "\(highGood) of \(high.days) \(goal.goodDays) vs \(lowGood) of \(low.days)"
        }
        return "\(effect.format(high.mean)) vs \(effect.format(low.mean)) of \(goal.answers.count) · \(high.days) vs \(low.days) \(unit)"
    }

    /// Only the side you can act on: there's no button for "walk less".
    private static func action(for cause: HealthConnections.Metric) -> String? {
        switch cause {
        case .sleep: return "Set a wind-down for tonight"
        case .steps: return "Plan a walk today"
        case .exercise: return "Plan 20 active minutes today"
        case .workout: return "Plan a workout"
        case .mindful: return "Take 5 mindful minutes"
        case .activity(let name): return "Make time for “\(name)” today"
        default: return nil
        }
    }
}
