import Foundation

/// PROVISIONAL product thresholds. They are not validated scientific thresholds:
/// they exist so every conclusion is explainable and open to discussion. Tune them after user testing.
enum InsightThresholds {
    /// Below this, no pattern is claimed ("First experiences" state).
    static let minimumActivitiesForPatterns = 6
    /// Minimum entries in each group being compared.
    static let minimumPerGroup = 3
    /// Minimum difference between means (1–5 scale) before mentioning an association.
    static let minimumMeanDifference = 0.8
    /// "Long rest" for the rest ↔ focus association.
    static let longRestMinutes = 7 * 60
    static let strengthMinimumRated = 4
    static let strengthPositiveShare = 0.75
    static let observationMinimumShare = 0.4
    /// Minimum entries to compare the older half with the recent half (discovery status).
    static let stabilityMinimumItems = 8
}

enum TimeBand: String, CaseIterable, Sendable {
    case morning, afternoon, evening

    init(date: Date, calendar: Calendar) {
        switch calendar.component(.hour, from: date) {
        case 5..<12: self = .morning
        case 12..<19: self = .afternoon
        default: self = .evening
        }
    }

    var phrase: String {
        switch self {
        case .morning: return "in the morning"
        case .afternoon: return "in the afternoon"
        case .evening: return "in the evening"
        }
    }

    var plural: String {
        switch self {
        case .morning: return "mornings"
        case .afternoon: return "afternoons"
        case .evening: return "evenings"
        }
    }

    var title: String {
        switch self {
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        }
    }

    var symbol: String {
        switch self {
        case .morning: return "sunrise"
        case .afternoon: return "sun.max"
        case .evening: return "moon.stars"
        }
    }
}

/// Local inference engine based on explainable rules.
/// Each rule returns its evidence (period, n, sources, comparison) and its limitations.
/// No opaque models: complex models are postponed until we define what evidence supports each conclusion.
struct InsightEngine {
    var calendar: Calendar = .current

    func analyze(activities: [Activity], areas: [LifeArea], now: Date = .now) -> InsightReport {
        let usable = activities.filter { $0.date <= now }
        var report = InsightReport(usableCount: usable.count, generatedAt: now)
        guard usable.count >= InsightThresholds.minimumActivitiesForPatterns else { return report }

        var found: [Discovery] = []
        if let d = volumeByTimeBand(usable) { found.append(d) }
        if let d = focusByTimeBand(usable) { found.append(d) }
        if let result = restAndFocus(usable) {
            found.append(result.discovery)
            if let connection = result.connection { report.connections.append(connection) }
        }
        found += strengths(usable, areas: areas)

        report.discoveries = found.sorted { ($0.level.sortOrder, $0.title) < ($1.level.sortOrder, $1.title) }
        return report
    }

    // MARK: - Rule 1 · Observation: when you log the most

    private func volumeByTimeBand(_ items: [Activity]) -> Discovery? {
        let counts = Dictionary(grouping: items) { TimeBand(date: $0.date, calendar: calendar) }.mapValues(\.count)
        let ranked = TimeBand.allCases.map { (band: $0, count: counts[$0] ?? 0) }.sorted { $0.count > $1.count }
        guard ranked.count > 1 else { return nil }
        let leader = ranked[0]
        let share = Double(leader.count) / Double(items.count)
        guard share >= InsightThresholds.observationMinimumShare, leader.count - ranked[1].count >= 2 else { return nil }

        let band = leader.band
        let status = stability(of: items) { subset -> Double? in
            guard subset.count >= 3 else { return nil }
            let c = Dictionary(grouping: subset) { TimeBand(date: $0.date, calendar: calendar) }.mapValues(\.count)
            let mine = c[band] ?? 0
            let others = TimeBand.allCases.filter { $0 != band }.map { c[$0] ?? 0 }.max() ?? 0
            return Double(mine - others)
        }

        let rows = ranked.map { Evidence.Row(label: $0.band.title, value: countLabel($0.count, "moment", "moments"), count: $0.count,
                                      fraction: Double($0.count) / Double(max(items.count, 1))) }
        return Discovery(
            id: "volume.timeBand",
            signature: "volume.timeBand.\(band.rawValue)",
            level: .observation,
            title: "Most of your day happens \(band.phrase)",
            summary: "\(leader.count) of your \(items.count) moments happened \(band.phrase).",
            symbol: band.symbol,
            status: status,
            evidence: evidence(for: items, total: items.count, rows: rows, limitations: [
                "This reflects when you log, which may not match when you actually do things.",
                "It is a summary of your entries, not a validated pattern."
            ]),
            areaIDs: [],
            revealsSchedule: true,
            usesHealthData: false,
            reflectionQuestion: "Is that time of day easier for logging, or for doing things?",
            suggestedExperiment: nil
        )
    }

    // MARK: - Rule 2 · Provisional pattern: focus by time of day

    private func focusByTimeBand(_ items: [Activity]) -> Discovery? {
        let rated = items.filter { $0.focus != nil }
        let groups = Dictionary(grouping: rated) { TimeBand(date: $0.date, calendar: calendar) }
        let eligible = groups.filter { $0.value.count >= InsightThresholds.minimumPerGroup }
        guard eligible.count >= 2 else { return nil }

        let means = eligible.mapValues { mean($0.compactMap(\.focus)) }
        guard let best = means.max(by: { $0.value < $1.value }),
              let worst = means.min(by: { $0.value < $1.value }),
              best.value - worst.value >= InsightThresholds.minimumMeanDifference else { return nil }
        let bestBand = best.key
        let worstBand = worst.key

        let used = eligible.values.flatMap { $0 }
        let status = stability(of: used) { subset -> Double? in
            let g = Dictionary(grouping: subset) { TimeBand(date: $0.date, calendar: calendar) }
            guard let b = g[bestBand], let w = g[worstBand], b.count >= 2, w.count >= 2 else { return nil }
            return mean(b.compactMap(\.focus)) - mean(w.compactMap(\.focus))
        }

        let rows = TimeBand.allCases.compactMap { band -> Evidence.Row? in
            guard let g = eligible[band], let m = means[band] else { return nil }
            return Evidence.Row(label: band.title, value: "\(format(m)) of 5", count: g.count, fraction: m / 5)
        }
        var limitations = [
            "Focus is estimated from your phone (fewer pickups) and may depend on the task or the place.",
            "An association in your entries does not prove a cause."
        ]
        let unrated = items.count - rated.count
        if unrated > 0 {
            limitations.append("\(countLabel(unrated, "entry", "entries")) without a focus rating were not used.")
        }
        let excluded = rated.count - used.count
        if excluded > 0 {
            limitations.append("\(countLabel(excluded, "entry", "entries")) from times of day with fewer than \(InsightThresholds.minimumPerGroup) ratings were not compared.")
        }

        return Discovery(
            id: "focus.timeBand",
            signature: "focus.timeBand.\(bestBand.rawValue)",
            level: .provisionalPattern,
            title: "You focus best \(bestBand.phrase)",
            summary: "Your focus sessions tend to go better \(bestBand.phrase).",
            symbol: bestBand.symbol,
            status: status,
            evidence: evidence(for: used, total: items.count, rows: rows, limitations: limitations),
            areaIDs: Array(Set(used.map(\.areaID))).sorted(),
            revealsSchedule: true,
            usesHealthData: false,
            reflectionQuestion: "Does the type of task or the place you work also change?",
            suggestedExperiment: ExperimentTemplate(
                question: "Do I focus better \(bestBand.phrase) or \(worstBand.phrase)?",
                conditionA: "\(bestBand.title) session",
                conditionB: "\(worstBand.title) session",
                measure: .focus,
                plannedDays: 10
            )
        )
    }

    // MARK: - Rule 3 · Provisional pattern + map connection: rest ↔ focus

    struct RestFocusResult {
        let discovery: Discovery
        let connection: MapConnection?
    }

    private func restAndFocus(_ items: [Activity]) -> RestFocusResult? {
        // Logged rest minutes ending on each day (a night counts for the day it ends).
        var restByDay: [Date: Int] = [:]
        var restItemsByDay: [Date: [Activity]] = [:]
        for a in items where a.areaID == LifeArea.rest.id {
            guard let minutes = a.durationMinutes, minutes > 0 else { continue }
            let day = calendar.startOfDay(for: a.endDate)
            restByDay[day, default: 0] += minutes
            restItemsByDay[day, default: []].append(a)
        }

        let focusItems = items.filter { $0.focus != nil && $0.areaID != LifeArea.rest.id }
        var long: [Activity] = []
        var short: [Activity] = []
        for a in focusItems {
            // No rest entry ≠ no rest: those days are not interpreted.
            guard let rest = restByDay[calendar.startOfDay(for: a.date)] else { continue }
            if rest >= InsightThresholds.longRestMinutes { long.append(a) } else { short.append(a) }
        }
        guard long.count >= InsightThresholds.minimumPerGroup,
              short.count >= InsightThresholds.minimumPerGroup else { return nil }

        let longMean = mean(long.compactMap(\.focus))
        let shortMean = mean(short.compactMap(\.focus))
        let diff = longMean - shortMean
        guard abs(diff) >= InsightThresholds.minimumMeanDifference else { return nil }

        let longIDs = Set(long.map(\.id))
        let sign: Double = diff > 0 ? 1 : -1
        let focusUsed = long + short
        let status = stability(of: focusUsed) { subset -> Double? in
            let l = subset.filter { longIDs.contains($0.id) }.compactMap(\.focus)
            let s = subset.filter { !longIDs.contains($0.id) }.compactMap(\.focus)
            guard l.count >= 2, s.count >= 2 else { return nil }
            return (mean(l) - mean(s)) * sign
        }

        let hours = InsightThresholds.longRestMinutes / 60
        let rows = [
            Evidence.Row(label: "After \(hours)h+ of sleep", value: "\(format(longMean)) of 5", count: long.count, fraction: longMean / 5),
            Evidence.Row(label: "After less sleep", value: "\(format(shortMean)) of 5", count: short.count, fraction: shortMean / 5)
        ]
        var limitations = [
            "This is an observed association, not a proven cause.",
            "Only days with logged rest count; a day without an entry is not read as a lack of rest.",
            "Other factors (type of task, stress, schedule) are not logged."
        ]
        let daysWithoutRest = Set(focusItems.map { calendar.startOfDay(for: $0.date) }).filter { restByDay[$0] == nil }.count
        if daysWithoutRest > 0 {
            limitations.append("\(countLabel(daysWithoutRest, "day", "days")) with a focus rating had no logged rest and were not used.")
        }

        let usedDays = Set(focusUsed.map { calendar.startOfDay(for: $0.date) })
        let restUsed = usedDays.flatMap { restItemsByDay[$0] ?? [] }
        // The area with the most ratings is the other end of the line on the map.
        let targetArea = Dictionary(grouping: focusUsed, by: \.areaID).max { $0.value.count < $1.value.count }?.key

        let discovery = Discovery(
            id: "rest.focus",
            signature: "rest.focus.\(diff > 0 ? "more" : "less")",
            level: .provisionalPattern,
            title: diff > 0 ? "Good sleep, better focus" : "Your focus doesn't follow your sleep",
            summary: diff > 0
                ? "After \(hours)h+ of sleep, your focus tends to be higher."
                : "On days with less sleep your focus was higher. Other things may be involved.",
            symbol: "moon.zzz",
            status: status,
            evidence: evidence(for: focusUsed + restUsed, total: items.count, rows: rows, limitations: limitations),
            areaIDs: [LifeArea.rest.id] + (targetArea.map { [$0] } ?? []),
            revealsSchedule: false,
            usesHealthData: true, // refers to sleep: never shared
            reflectionQuestion: "What else changes on the days you rest more?",
            suggestedExperiment: nil
        )
        let connection = targetArea.map {
            MapConnection(fromAreaID: LifeArea.rest.id, toAreaID: $0, discoveryID: discovery.id)
        }
        return RestFocusResult(discovery: discovery, connection: connection)
    }

    // MARK: - Rule 4 · Possible strength: sustained enjoyment in an area

    private func strengths(_ items: [Activity], areas: [LifeArea]) -> [Discovery] {
        let byArea = Dictionary(grouping: items.filter { $0.enjoyment != nil }, by: \.areaID)
        return byArea.sorted { $0.key < $1.key }.compactMap { entry -> Discovery? in
            let areaID = entry.key
            let rated = entry.value
            guard rated.count >= InsightThresholds.strengthMinimumRated else { return nil }
            let positive = rated.filter { ($0.enjoyment ?? 0) >= 4 }
            let share = Double(positive.count) / Double(rated.count)
            guard share >= InsightThresholds.strengthPositiveShare else { return nil }

            let area = areas.first { $0.id == areaID } ?? .unknown(id: areaID)
            let status = stability(of: rated) { subset -> Double? in
                guard subset.count >= 2 else { return nil }
                let s = Double(subset.filter { ($0.enjoyment ?? 0) >= 4 }.count) / Double(subset.count)
                return s - 0.5
            }
            let negative = rated.count - positive.count
            return Discovery(
                id: "strength.enjoyment.\(areaID)",
                signature: "strength.enjoyment.\(areaID)",
                level: .possibleStrength,
                title: "\(area.name) lights you up",
                summary: "\(positive.count) of \(rated.count) \(area.name.lowercased()) moments felt great.",
                symbol: area.symbol,
                status: status,
                evidence: evidence(for: rated, total: items.count, rows: [
                    Evidence.Row(label: "Felt great", value: countLabel(positive.count, "time", "times"), count: positive.count,
                                 fraction: Double(positive.count) / Double(rated.count)),
                    Evidence.Row(label: "Felt so-so", value: countLabel(negative, "time", "times"), count: negative,
                                 fraction: Double(negative) / Double(rated.count))
                ], limitations: [
                    "Enjoying something is not the same as having a skill: add context to refine it.",
                    "It is a hypothesis, not a fixed label.",
                    "Self-reports can be biased, for example by logging mostly what went well."
                ]),
                areaIDs: [areaID],
                revealsSchedule: false,
                usesHealthData: false,
                reflectionQuestion: "What do those experiences have in common? Who were you with, where were you, what kind of task was it?",
                suggestedExperiment: nil
            )
        }
    }

    // MARK: - Helpers

    /// Compares the older half of the data with the recent half.
    /// `effect` returns a signed value: positive = agrees with the current conclusion.
    private func stability(of items: [Activity], effect: ([Activity]) -> Double?) -> Discovery.Status {
        let sorted = items.sorted { $0.date < $1.date }
        guard sorted.count >= InsightThresholds.stabilityMinimumItems else { return .exploring }
        let mid = sorted.count / 2
        guard let newer = effect(Array(sorted[mid...])), newer > 0,
              let older = effect(Array(sorted[..<mid])) else { return .exploring }
        return older > 0 ? .repeating : .changing
    }

    private func evidence(for items: [Activity], total: Int, rows: [Evidence.Row], limitations: [String]) -> Evidence {
        let dates = items.map(\.date)
        return Evidence(
            periodStart: dates.min() ?? .now,
            periodEnd: dates.max() ?? .now,
            usableCount: items.count,
            totalCount: total,
            sources: Array(Set(items.map(\.source))).sorted { $0.rawValue < $1.rawValue },
            comparison: rows,
            limitations: limitations,
            activityIDs: items.map(\.id)
        )
    }

    private func mean(_ values: [Int]) -> Double {
        values.isEmpty ? 0 : Double(values.reduce(0, +)) / Double(values.count)
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
