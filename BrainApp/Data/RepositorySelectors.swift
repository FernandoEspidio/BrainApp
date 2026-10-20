import Foundation

/// Summary of an area for the map. Counts moments (doesn't mix hours, steps or moods).
struct AreaSummary: Identifiable {
    var id: String { area.id }
    let area: LifeArea
    let recentCount: Int
    let previousCount: Int
    let totalCount: Int
    let priority: Priority
    let sources: [DataSource: Int]
}

struct WeekCount: Identifiable {
    var id: Date { weekStart }
    let weekStart: Date
    let count: Int
}

/// A moment of today, shown as a small chip on Home.
struct TodayMoment: Identifiable {
    var id: UUID { activity.id }
    let activity: Activity
    let mood: BrainMood
    let symbol: String
    let shortValue: String
}

/// The single card on Home. Only one at a time, to keep the screen calm.
enum HomeCard {
    case newDiscovery(Discovery)
    case changedDiscovery(Discovery)
    case checkIn(Activity)
    case experiment(Experiment, logged: Int)
    case gettingToKnowYou(daysLeftHint: Int)
    case allQuiet
}

extension LocalRepository {
    /// Window used by the map (explained in the legend).
    static let windowDays = 14

    func areaSummaries(now: Date = .now, calendar: Calendar = .current) -> [AreaSummary] {
        let recentStart = calendar.date(byAdding: .day, value: -Self.windowDays, to: now) ?? now
        let previousStart = calendar.date(byAdding: .day, value: -2 * Self.windowDays, to: now) ?? now
        return areas.map { area in
            let items = snapshot.activities.filter { $0.areaID == area.id }
            let recent = items.filter { $0.date >= recentStart && $0.date <= now }.count
            let previous = items.filter { $0.date >= previousStart && $0.date < recentStart }.count
            let sources = Dictionary(grouping: items, by: \.source).mapValues(\.count)
            return AreaSummary(area: area, recentCount: recent, previousCount: previous, totalCount: items.count,
                               priority: priority(for: area.id), sources: sources)
        }
    }

    func weeklyCounts(areaID: String, weeks: Int = 8, now: Date = .now, calendar: Calendar = .current) -> [WeekCount] {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        return (0..<weeks).reversed().compactMap { offset -> WeekCount? in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let count = snapshot.activities.filter { $0.areaID == areaID && $0.date >= start && $0.date < end }.count
            return WeekCount(weekStart: start, count: count)
        }
    }

    func connections(involving areaID: String) -> [MapConnection] {
        report.connections.filter { $0.involves(areaID) }
    }

    // MARK: - Discoveries ranked by relevance

    var rankedDiscoveries: [Discovery] {
        report.discoveries.sorted { rank($0) < rank($1) }
    }

    func isUnseen(_ discovery: Discovery) -> Bool { snapshot.seenDiscoveries[discovery.id] == nil }

    func hasChangedSinceSeen(_ discovery: Discovery) -> Bool {
        guard let seen = snapshot.seenDiscoveries[discovery.id] else { return false }
        return seen.signature != discovery.signature
    }

    private func rank(_ d: Discovery) -> Int {
        var value: Int
        if isUnseen(d) { value = 0 }
        else if hasChangedSinceSeen(d) { value = 1 }
        else {
            switch d.status {
            case .changing: value = 2
            case .repeating: value = 3
            case .exploring: value = 4
            }
        }
        if snapshot.feedback[d.id]?.notRepresentative == true { value += 10 }
        return value
    }

    // MARK: - Goal and hints

    func dailyAnswer(for goal: Goal, on day: Date) -> Int? {
        snapshot.dailyAnswers.first { $0.goal == goal && $0.day == day }?.value
    }

    /// What `HintEngine` reads: one row per day for the last `daysBack` days, with Health's numbers when
    /// there are any, the answers to this goal's question and the activities logged by hand.
    func hintDays(health: [HealthDay], goal: Goal, daysBack: Int = 60, now: Date = .now,
                  calendar: Calendar = .current) -> [HealthDay] {
        let today = calendar.startOfDay(for: now)
        let healthByDate = Dictionary(health.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        let answers = Dictionary(snapshot.dailyAnswers.filter { $0.goal == goal }.map { ($0.day, Double($0.value)) },
                                 uniquingKeysWith: { _, latest in latest })
        let days = (0...daysBack).reversed().compactMap { offset -> HealthDay? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            var day = healthByDate[date] ?? HealthDay(date: date)
            day.answer = answers[date]
            return day
        }
        return HealthConnections.addingActivities(snapshot.activities, to: days, calendar: calendar)
    }

    // MARK: - Home

    /// Moments that ended today (sleep counts for the day it ends), oldest first.
    func todayMoments(now: Date = .now, calendar: Calendar = .current) -> [TodayMoment] {
        snapshot.activities
            .filter { calendar.isDate($0.endDate, inSameDayAs: now) && $0.date <= now }
            .sorted { $0.date < $1.date }
            .map { activity in
                let area = area(id: activity.areaID)
                let value = activity.durationMinutes.map(formatMinutes) ?? activity.date.formatted(date: .omitted, time: .shortened)
                return TodayMoment(activity: activity, mood: BrainMood(areaID: activity.areaID),
                                   symbol: activity.symbol(area: area), shortValue: value)
            }
    }

    /// Days since the companion started getting to know the user.
    func daysTogether(now: Date = .now, calendar: Calendar = .current) -> Int {
        let first = snapshot.sensingStartDate ?? snapshot.activities.map(\.date).min() ?? now
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: first), to: calendar.startOfDay(for: now)).day ?? 0
        return max(days, 0) + 1
    }

    /// One card. If there's no new evidence, no novelty is invented.
    func homeCard(now: Date = .now) -> HomeCard {
        let candidates = report.discoveries.filter { snapshot.feedback[$0.id]?.notRepresentative != true }
        if let d = candidates.first(where: { isUnseen($0) }) { return .newDiscovery(d) }
        if let d = candidates.first(where: { hasChangedSinceSeen($0) }) { return .changedDiscovery(d) }
        if let pending = pendingCheckIn(now: now) { return .checkIn(pending) }
        if let e = openExperiment, e.status == .active {
            return .experiment(e, logged: snapshot.activities.filter { $0.experimentID == e.id }.count)
        }
        if report.isEarlyStage {
            return .gettingToKnowYou(daysLeftHint: max(1, InsightThresholds.minimumActivitiesForPatterns - report.usableCount))
        }
        return .allQuiet
    }

    /// The latest moment from today without a feeling, if it isn't sleep (we don't ask about sleep).
    func pendingCheckIn(now: Date = .now) -> Activity? {
        todayMoments(now: now).map(\.activity).reversed().first {
            $0.enjoyment == nil && $0.areaID != LifeArea.rest.id && !skippedCheckIns.contains($0.id)
        }
    }

    /// The brain mirrors something real: what's happening now, a fresh discovery, or the last moment.
    func companionState(now: Date = .now) -> CompanionState {
        let stage = companionStage
        let ongoing = snapshot.activities.first { $0.date <= now && now < $0.endDate }
        if let ongoing {
            return CompanionState(mood: BrainMood(areaID: ongoing.areaID), reason: describe(ongoing, prefix: "Now"), stage: stage)
        }
        if case .newDiscovery = homeCard(now: now) {
            return CompanionState(mood: .celebrating, reason: "Your buddy spotted something new about you", stage: stage)
        }
        if let recent = todayMoments(now: now).last, now.timeIntervalSince(recent.activity.endDate) < 90 * 60 {
            let mood: BrainMood = recent.mood == .resting ? .idle : recent.mood // Awake now: don't keep it sleeping.
            return CompanionState(mood: mood, reason: describe(recent.activity, prefix: nil), stage: stage)
        }
        let count = todayMoments(now: now).count
        let reason = count == 0 ? "Nothing detected yet today" : "\(countLabel(count, "moment", "moments")) today"
        return CompanionState(mood: .idle, reason: reason, stage: stage)
    }

    /// "Slept 7h 40m · detected" / "Walk · 35m · detected".
    func describe(_ activity: Activity, prefix: String?) -> String {
        var parts: [String] = []
        if activity.areaID == LifeArea.rest.id, let minutes = activity.durationMinutes {
            parts.append("Slept \(formatMinutes(minutes))")
        } else {
            parts.append(activity.title)
            if let minutes = activity.durationMinutes { parts.append(formatMinutes(minutes)) }
        }
        if activity.isDetected { parts.append("detected") }
        let text = parts.joined(separator: " · ")
        return prefix.map { "\($0): \(text)" } ?? text
    }
}
