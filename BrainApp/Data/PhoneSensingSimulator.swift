import Foundation

/// PROTOTYPE STAND-IN for passive sensing. The product assumes the phone can notice sleep,
/// walks, workouts, reading time, focus sessions and calls (HealthKit, Core Motion,
/// Screen Time…). None of that is implemented yet, so this generator produces plausible,
/// deterministic moments per day. Everything it creates is tagged with a `Detection`
/// and labeled as simulated in the UI.
///
/// To replace it, implement `DeviceDataSource` with the real frameworks and keep the same output.
struct PhoneSensingSimulator {
    var calendar: Calendar = .current
    var source: DataSource = .phone
    /// Demo data also simulates quick "how did it feel?" answers; real mode leaves them to the user.
    var simulateFeelings = false
    var seed: UInt64 = 7

    /// Moments for one day that have already ended at `now`.
    func moments(on day: Date, now: Date) -> [Activity] {
        let start = calendar.startOfDay(for: day)
        let dayIndex = Int(start.timeIntervalSinceReferenceDate / 86_400)
        var rng = SeededGenerator(seed: seed &+ UInt64(bitPattern: Int64(dayIndex)) &* 1_000_003)

        func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &rng) < p }
        func roll(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &rng) }
        func at(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: start) ?? start
        }
        func clamp(_ value: Int) -> Int { min(5, max(1, value)) }

        var items: [Activity] = []
        func add(_ kind: Detection, _ title: String, area: LifeArea, start: Date, minutes: Int,
                 focus: Int? = nil, enjoyment: Int? = nil) {
            items.append(Activity(
                id: Self.stableID(dayIndex: dayIndex, kind: kind),
                title: title, areaID: area.id, date: start, durationMinutes: minutes,
                focus: focus, enjoyment: simulateFeelings ? enjoyment : nil,
                source: source, detection: kind
            ))
        }

        // Sleep that ends this morning (counts for this day).
        let longSleep = chance(0.55)
        let sleepMinutes = longSleep ? roll(430...510) : roll(320...400)
        let wake = at(7, roll(0...45))
        add(.sleep, "Sleep", area: .rest, start: wake.addingTimeInterval(-Double(sleepMinutes) * 60), minutes: sleepMinutes)

        // Focus session: estimated focus (fewer phone pickups ⇒ higher). Mornings and long sleep help a bit.
        if chance(0.8) {
            let morning = chance(0.5)
            var focus = (morning ? 4 : 3) + (longSleep ? 1 : -1) + roll(-1...0)
            focus = clamp(focus)
            add(.focusSession, "Focus session", area: .learning,
                start: at(morning ? roll(8...10) : roll(15...17), 0), minutes: [45, 60, 90][roll(0...2)],
                focus: focus, enjoyment: clamp(3 + roll(-1...1)))
        }
        if chance(0.65) {
            add(.walk, "Walk", area: .movement, start: at(roll(12...18), 30), minutes: roll(20...50),
                enjoyment: clamp(3 + roll(0...1)))
        }
        if chance(0.3) {
            add(.workout, "Workout", area: .movement, start: at(chance(0.5) ? 7 : 18, 45), minutes: roll(30...60),
                enjoyment: clamp(4 + roll(-1...1)))
        }
        if chance(0.5) {
            add(.reading, "Reading", area: .learning, start: at(21, roll(0...40)), minutes: roll(15...45),
                enjoyment: clamp(4 + roll(-1...0)))
        }
        if chance(0.35) {
            add(.call, "Call with a friend", area: .social, start: at(19, roll(0...50)), minutes: roll(15...60),
                enjoyment: chance(0.85) ? roll(4...5) : 3)
        }

        return items.filter { $0.endDate <= now }
    }

    func moments(from startDay: Date, through now: Date) -> [Activity] {
        var result: [Activity] = []
        var day = calendar.startOfDay(for: startDay)
        let last = calendar.startOfDay(for: now)
        while day <= last {
            result += moments(on: day, now: now)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// Same day + same kind ⇒ same ID, so re-syncing never duplicates.
    static func stableID(dayIndex: Int, kind: Detection) -> UUID {
        let kindIndex = Detection.allCases.firstIndex(of: kind) ?? 0
        let day = UInt32(truncatingIfNeeded: dayIndex)
        let text = String(format: "%08X-5E45-4000-8000-%012X", day, kindIndex)
        return UUID(uuidString: text) ?? UUID()
    }
}
