import Foundation

/// Ring progress computed from the stored moments. Read-only helpers on the repository.
extension LocalRepository {
    func goal(for areaID: String) -> AreaGoal { snapshot.goals[areaID] ?? .defaultGoal(for: areaID) }

    /// The day or week that contains `date`.
    static func periodInterval(_ period: AreaGoal.Period, containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let component: Calendar.Component = period == .day ? .day : .weekOfYear
        return calendar.dateInterval(of: component, for: date) ?? DateInterval(start: date, duration: 86_400)
    }

    /// Minutes or moments in an area during an interval. A moment counts for the period it ENDS in
    /// (last night's sleep counts for today).
    func progressValue(areaID: String, goal: AreaGoal, in interval: DateInterval) -> Int {
        let items = snapshot.activities.filter {
            $0.areaID == areaID && $0.endDate >= interval.start && $0.endDate < interval.end
        }
        switch goal.unit {
        case .minutes:
            return items.reduce(0) { $0 + ($1.durationMinutes ?? AreaGoal.assumedMinutesWithoutDuration) }
        case .moments:
            return items.count
        }
    }

    func ringProgress(for area: LifeArea, now: Date = .now) -> RingProgress {
        let goal = goal(for: area.id)
        let interval = Self.periodInterval(goal.period, containing: now)
        return RingProgress(area: area, goal: goal,
                            value: progressValue(areaID: area.id, goal: goal, in: interval),
                            periodStart: interval.start)
    }

    /// The five rings, always in the same order.
    func rings(now: Date = .now) -> [RingProgress] {
        LifeArea.builtIns.map { ringProgress(for: $0, now: now) }
    }

    /// Average of the five rings, each capped at 100%.
    func overallProgress(now: Date = .now) -> Double {
        let all = rings(now: now)
        guard !all.isEmpty else { return 0 }
        return all.map { min($0.fraction, 1) }.reduce(0, +) / Double(all.count)
    }

    /// The last `count` periods (oldest first, current last).
    func history(for area: LifeArea, count: Int = 7, now: Date = .now, calendar: Calendar = .current) -> [PeriodResult] {
        let goal = goal(for: area.id)
        let component: Calendar.Component = goal.period == .day ? .day : .weekOfYear
        return (0..<count).reversed().compactMap { back in
            guard let date = calendar.date(byAdding: component, value: -back, to: now) else { return nil }
            let interval = Self.periodInterval(goal.period, containing: date, calendar: calendar)
            let value = progressValue(areaID: area.id, goal: goal, in: interval)
            return PeriodResult(start: interval.start, fraction: goal.target > 0 ? Double(value) / Double(goal.target) : 0)
        }
    }

    /// Moments that count toward the ring right now.
    func ringMoments(for area: LifeArea, now: Date = .now) -> [Activity] {
        let interval = Self.periodInterval(goal(for: area.id).period, containing: now)
        return snapshot.activities
            .filter { $0.areaID == area.id && $0.endDate >= interval.start && $0.endDate < interval.end }
            .sorted { $0.date > $1.date }
    }

    /// A completed ring that hasn't been celebrated yet (the app shows the celebration once).
    func nextCelebration(now: Date = .now) -> RingProgress? {
        guard snapshot.hasCompletedOnboarding || isDemo else { return nil }
        return rings(now: now).first { $0.isComplete && !snapshot.celebratedRings.contains($0.celebrationKey) }
    }
}
