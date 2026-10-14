import Foundation

/// Extension point for device sources (HealthKit). Nothing is imported in this first scope:
/// the base document marks it as "initial optional", after validating the core flow.
///
/// When implementing `HealthKitDataSource`:
/// - Request authorization per type (steps, workouts, sleep) only when the source is turned on.
/// - No samples → show "No data available"; don't read it as inactivity or denial
///   (HealthKit doesn't always let you tell whether the user declined read access).
/// - Don't assume a universal measure of sleep quality.
/// - Avoid duplicating manual and imported sessions (see `isLikelyDuplicate`).
/// - Add the HealthKit capability and `NSHealthShareUsageDescription` only at that point.
protocol DeviceDataSource {
    var kind: DataSource { get }
    var displayName: String { get }
    func availability() async -> DeviceSourceAvailability
    func fetchActivities(since: Date) async throws -> [Activity]
}

enum DeviceSourceAvailability: Equatable {
    case notConfigured
    case noDataAvailable
    case available(lastSample: Date)
}

enum DuplicateDetection {
    /// Two entries count as the same if they share an area and overlap by more than half of the shorter one.
    static func isLikelyDuplicate(_ a: Activity, _ b: Activity) -> Bool {
        guard a.areaID == b.areaID, a.source != b.source else { return false }
        let overlapStart = max(a.date, b.date)
        let overlapEnd = min(a.endDate, b.endDate)
        let overlap = overlapEnd.timeIntervalSince(overlapStart)
        let shortest = min(a.endDate.timeIntervalSince(a.date), b.endDate.timeIntervalSince(b.date))
        return shortest > 0 && overlap > shortest / 2
    }
}
