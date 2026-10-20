import Foundation

/// Deterministic generator (SplitMix64) so the demo is always the same.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// FICTIONAL data for demo mode. Lives only in memory, is tagged `source = .demo`
/// and is never mixed with real entries. Built with the same sensing simulator,
/// so the demo shows what six weeks of passive detection could look like.
enum DemoData {
    static let friendID = UUID(uuidString: "00000000-0000-4000-8000-00000000A1E5")!

    static func makeSnapshot(now: Date = .now, calendar: Calendar = .current) -> AppSnapshot {
        let simulator = PhoneSensingSimulator(calendar: calendar, source: .demo, simulateFeelings: true, seed: 2026)
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -41, to: today) ?? today
        var activities = simulator.moments(from: start, through: now)

        // A few things the phone can't detect, added by hand.
        var rng = SeededGenerator(seed: 99)
        let creative = ["Draw", "Play guitar", "Write a short story"]
        for offset in stride(from: 40, through: 2, by: -4) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let date = calendar.date(bySettingHour: 20, minute: 30, second: 0, of: day) else { continue }
            activities.append(Activity(title: creative[Int.random(in: 0...2, using: &rng)], areaID: LifeArea.creativity.id,
                                       date: date, durationMinutes: 40, enjoyment: Int.random(in: 3...5, using: &rng),
                                       source: .demo))
        }

        // Ongoing experiment: morning vs afternoon, using the focus sessions from the last few days.
        let experimentStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let experiment = Experiment(question: "Do I focus better in the morning or in the afternoon?",
                                    conditionA: "Morning session", conditionB: "Afternoon session",
                                    measure: .focus, plannedDays: 10, startDate: experimentStart, isDemo: true)
        for index in activities.indices {
            guard activities[index].detection == .focusSession, activities[index].date >= experimentStart else { continue }
            activities[index].experimentID = experiment.id
            activities[index].experimentArm = TimeBand(date: activities[index].date, calendar: calendar) == .morning ? .a : .b
        }

        var snapshot = AppSnapshot()
        snapshot.activities = activities
        snapshot.experiments = [experiment]
        snapshot.priorities = [
            LifeArea.learning.id: .veryImportant,
            LifeArea.creativity.id: .important,
            LifeArea.movement.id: .important,
            LifeArea.rest.id: .important,
            LifeArea.social.id: .some
        ]
        snapshot.userName = "Alex"
        snapshot.companion = CompanionAppearance(name: "Buddy", colorIndex: 0, accessory: .none)
        snapshot.friends = [Friend(card: demoFriendCard(name: "Sam", id: friendID),
                                   receivedAt: now.addingTimeInterval(-3 * 86_400), via: .demo)]
        snapshot.hasCompletedOnboarding = true
        // Today's hints come from `SampleHealthDays`, which answer the daily question for any goal.
        snapshot.goal = .focus
        snapshot.simulateSensing = false // Demo data is already complete.
        snapshot.sensingStartDate = start
        return snapshot
    }

    static func demoFriendCard(name: String, id: UUID) -> ShareableBrainCard {
        ShareableBrainCard(
            id: id,
            protocolVersion: ShareableBrainCard.currentVersion,
            displayName: "\(name) (fictional)",
            appearance: CompanionAppearance(name: name, colorIndex: 1, accessory: .leaf),
            stage: 2,
            stageName: CompanionStage.name(2),
            highlights: [
                SharedHighlight(title: "Possible strength: creativity", symbol: "paintpalette", levelLabel: "Possible strength"),
                SharedHighlight(title: "Possible strength: movement", symbol: "figure.walk", levelLabel: "Possible strength")
            ],
            createdAt: .now,
            isDemo: true
        )
    }
}
