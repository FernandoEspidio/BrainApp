import Foundation
import HealthKit

/// Reads the user's Health history, read-only. The real counterpart of `PhoneSensingSimulator`.
/// SPIKE: for now only the Health probe in Lab uses it, to see which connections real data supports
/// before it replaces the simulator. Follows the notes in `DeviceDataSource`.
final class HealthKitDataSource: DeviceDataSource {
    let kind = DataSource.healthKit
    let displayName = "Health"

    private let store = HKHealthStore()
    private let calendar = Calendar.current

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Read-only: the app never writes to Health.
    private static let readTypes: Set<HKObjectType> = [
        HKCategoryType(.sleepAnalysis),
        HKObjectType.workoutType(),
        HKQuantityType(.stepCount),
        HKQuantityType(.appleExerciseTime),
        HKCategoryType(.mindfulSession),
        HKObjectType.stateOfMindType()
    ]

    /// Shows the system sheet the first time; afterwards it returns at once.
    /// HealthKit never says whether reading was declined: declined types just come back empty.
    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    func availability() async -> DeviceSourceAvailability {
        guard Self.isAvailable else { return .notConfigured }
        let latest = try? await samples(.quantitySample(type: HKQuantityType(.stepCount), predicate: nil), limit: 1, newestFirst: true).first
        return latest.map { .available(lastSample: $0.endDate) } ?? .noDataAvailable
    }

    /// Nights and workouts as moments. Steps, exercise minutes and mood stay daily numbers (`dailySummaries`).
    func fetchActivities(since start: Date) async throws -> [Activity] {
        let nights = try await sleepNights(since: start).map { night in
            Activity(id: night.id, title: "Sleep", areaID: LifeArea.rest.id, date: night.start,
                     durationMinutes: night.asleepMinutes, source: .healthKit, detection: .sleep)
        }
        let workouts = try await samples(.workout(datePredicate(since: start))).map { workout in
            let walking = workout.workoutActivityType == .walking || workout.workoutActivityType == .hiking
            return Activity(id: workout.uuid, title: walking ? "Walk" : "Workout", areaID: LifeArea.movement.id,
                            date: workout.startDate, durationMinutes: Int(workout.duration / 60),
                            source: .healthKit, detection: walking ? .walk : .workout)
        }
        return nights + workouts
    }

    /// One row per day since `start`: the numbers the Health connections compare.
    func dailySummaries(since start: Date) async throws -> [HealthDay] {
        let first = calendar.startOfDay(for: start)
        var days: [Date: HealthDay] = [:]
        var day = first
        while day <= .now {
            days[day] = HealthDay(date: day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        // The first night starts the evening before.
        for night in try await sleepNights(since: first.addingTimeInterval(-Self.nightShift)) {
            days[night.day]?.sleepMinutes = night.asleepMinutes
            days[night.day]?.sleepIsTimeInBed = night.isTimeInBed
        }
        for statistics in try await dailySums(.stepCount, since: first) {
            days[statistics.startDate]?.steps = statistics.sumQuantity().map { Int($0.doubleValue(for: .count())) }
        }
        for statistics in try await dailySums(.appleExerciseTime, since: first) {
            days[statistics.startDate]?.exerciseMinutes = statistics.sumQuantity().map { Int($0.doubleValue(for: .minute())) }
        }
        for workout in try await samples(.workout(datePredicate(since: first))) {
            days[calendar.startOfDay(for: workout.startDate)]?.workoutMinutes += Int(workout.duration / 60)
        }
        let mindful = try await samples(.categorySample(type: HKCategoryType(.mindfulSession), predicate: datePredicate(since: first)))
        for session in mindful {
            days[calendar.startOfDay(for: session.startDate)]?.mindfulMinutes += Int(session.endDate.timeIntervalSince(session.startDate) / 60)
        }
        let moods = try await samples(.sample(type: HKObjectType.stateOfMindType(), predicate: datePredicate(since: first)))
            .compactMap { $0 as? HKStateOfMind }
        for (date, logged) in Dictionary(grouping: moods, by: { calendar.startOfDay(for: $0.startDate) }) {
            days[date]?.valence = logged.map(\.valence).reduce(0, +) / Double(logged.count)
        }
        return days.values.sorted { $0.date < $1.date }
    }

    // MARK: - Sleep

    struct SleepNight {
        let id: UUID
        /// The day the night ends on (a night counts for that morning).
        let day: Date
        let start: Date
        let asleepMinutes: Int
        /// No asleep data that night, only time in bed: an overestimate of sleep.
        let isTimeInBed: Bool
    }

    /// Asleep time ending between 6 pm and 6 pm counts for the second day's night.
    private static let nightShift: TimeInterval = 6 * 3600

    /// Watch, iPhone and other apps often record the same night, and the Watch splits it into
    /// stages, so overlapping intervals are merged before they are added up.
    /// Without a Watch, iOS only records time in bed (from the Sleep Schedule); it is used when nothing else exists.
    func sleepNights(since start: Date) async throws -> [SleepNight] {
        let asleep = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        let inBed = HKCategoryValueSleepAnalysis.inBed.rawValue
        let segments = try await samples(.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: datePredicate(since: start)))
            .filter { asleep.contains($0.value) || $0.value == inBed }
        let byNight = Dictionary(grouping: segments) { calendar.startOfDay(for: $0.endDate.addingTimeInterval(Self.nightShift)) }
        return byNight.compactMap { day, segments -> SleepNight? in
            let asleepSegments = segments.filter { asleep.contains($0.value) }
            let used = asleepSegments.isEmpty ? segments : asleepSegments
            let merged = Self.merge(used.map { DateInterval(start: $0.startDate, end: $0.endDate) })
            guard let first = merged.first else { return nil }
            let minutes = merged.reduce(0) { $0 + $1.duration } / 60
            return SleepNight(id: Self.stableID(night: day), day: day, start: first.start, asleepMinutes: Int(minutes),
                              isTimeInBed: asleepSegments.isEmpty)
        }
        .sorted { $0.day < $1.day }
    }

    private static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
        var result: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, interval.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                result.append(interval)
            }
        }
        return result
    }

    /// Same night ⇒ same ID, so reading again never duplicates.
    private static func stableID(night: Date) -> UUID {
        let day = UInt32(truncatingIfNeeded: Int(night.timeIntervalSinceReferenceDate / 86_400))
        return UUID(uuidString: String(format: "%08X-4EA1-4000-8000-000000000001", day)) ?? UUID()
    }

    // MARK: - Queries

    private func datePredicate(since start: Date) -> NSPredicate {
        HKQuery.predicateForSamples(withStart: start, end: nil)
    }

    private func samples<Sample: HKSample>(_ predicate: HKSamplePredicate<Sample>, limit: Int? = nil,
                                           newestFirst: Bool = false) async throws -> [Sample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\Sample.startDate, order: newestFirst ? .reverse : .forward)],
            limit: limit
        )
        return try await descriptor.result(for: store)
    }

    /// Daily totals with duplicates across sources (Watch + iPhone) already removed by HealthKit.
    private func dailySums(_ identifier: HKQuantityTypeIdentifier, since start: Date) async throws -> [HKStatistics] {
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(identifier), predicate: datePredicate(since: start)),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        return try await descriptor.result(for: store).statistics()
    }
}
