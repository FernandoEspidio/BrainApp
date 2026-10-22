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
/// Sample profiles shown in Demo mode.
enum DemoProfile: String, CaseIterable, Identifiable {
    /// Six weeks of moments, several traits, hunches in every state, a recorded move and friends.
    case full
    /// One week in: a first pattern or two, one hunch being tested, one friend.
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: return "Full profile (6 weeks)"
        case .light: return "Light profile (1 week)"
        }
    }
}

enum DemoData {
    static let friendID = UUID(uuidString: "00000000-0000-4000-8000-00000000A1E5")!

    static func makeSnapshot(profile: DemoProfile = .full, now: Date = .now, calendar: Calendar = .current) -> AppSnapshot {
        let full = profile == .full
        let simulator = PhoneSensingSimulator(calendar: calendar, source: .demo, simulateFeelings: true, seed: 2026)
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: full ? -41 : -6, to: today) ?? today
        var activities = simulator.moments(from: start, through: now)

        // A few things the phone can't detect, added by hand.
        var rng = SeededGenerator(seed: 99)
        let creative = ["Draw", "Play guitar", "Write a short story"]
        for offset in stride(from: full ? 40 : 5, through: 2, by: full ? -4 : -3) {
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
        snapshot.companion = full ? CompanionAppearance(name: "Buddy", colorIndex: 0, headwear: .sprout) : CompanionAppearance(name: "Buddy")
        snapshot.friends = demoFriends.prefix(full ? 2 : 1).enumerated().map { index, friend in
            Friend(card: demoFriendCard(friend), receivedAt: now.addingTimeInterval(-Double(3 + index * 4) * 86_400), via: .demo)
        }
        snapshot.hunches = hunches(full: full, today: today, calendar: calendar)
        if full { snapshot.animoji = AnimojiClip.clip(for: .giggle) }
        snapshot.hasCompletedOnboarding = true
        snapshot.simulateSensing = false // Demo data is already complete.
        snapshot.sensingStartDate = start
        return snapshot
    }

    /// Hunches in every state, so the whole loop can be shown.
    private static func hunches(full: Bool, today: Date, calendar: Calendar) -> [Hunch] {
        func days(_ answers: [Hunch.Answer], endingDaysAgo end: Int) -> [Hunch.CheckIn] {
            answers.enumerated().compactMap { index, answer in
                let back = end + answers.count - 1 - index
                return calendar.date(byAdding: .day, value: -back, to: today).map { Hunch.CheckIn(day: $0, answer: answer) }
            }
        }
        let templates = Dictionary(uniqueKeysWithValues: HunchTemplate.all.map { ($0.statement, $0) })
        func make(_ statement: String, _ answers: [Hunch.Answer], endingDaysAgo end: Int = 1,
                  status: Hunch.Status = .testing) -> Hunch? {
            guard var hunch = templates[statement]?.make(isDemo: true) else { return nil }
            hunch.checkIns = days(answers, endingDaysAgo: end)
            hunch.status = status
            hunch.createdAt = hunch.checkIns.first?.day ?? today
            return hunch
        }
        if !full {
            return [make("I learn better after I move", [.yes, .unsure], endingDaysAgo: 1)].compactMap { $0 }
        }
        return [
            make("I learn better after I move", [.yes, .no, .yes], endingDaysAgo: 1),
            make("Good sleep makes me more social", [.yes, .yes, .no, .yes, .yes], endingDaysAgo: 1),
            make("Music helps me focus", [.yes, .yes, .unsure, .yes, .yes, .yes], endingDaysAgo: 8, status: .confirmed),
            make("Walks spark my ideas", [.yes, .no, .yes, .yes, .yes], endingDaysAgo: 15, status: .confirmed),
            make("Friends recharge me", [.yes, .yes, .yes, .no, .yes], endingDaysAgo: 20, status: .confirmed)
        ].compactMap { $0 }
    }

    /// Fictional friends for Demo mode (each with its own look, move and traits).
    struct DemoFriend {
        let id: UUID
        let name: String
        let appearance: CompanionAppearance
        let move: BrainReaction
        let traits: [SharedHighlight]
        let stage: Int
    }

    static let demoFriends: [DemoFriend] = [
        DemoFriend(id: UUID(uuidString: "5A3E0C4B-0000-4000-8000-00000000A001")!, name: "Sam",
                   appearance: CompanionAppearance(name: "Sam", colorIndex: 1, headwear: .sprout),
                   move: .wink,
                   traits: [SharedHighlight(title: "Creativity lights them up", symbol: "paintpalette", levelLabel: "Possible strength"),
                            SharedHighlight(title: "Moves every morning", symbol: "figure.walk", levelLabel: "Provisional pattern")],
                   stage: 2),
        DemoFriend(id: UUID(uuidString: "5A3E0C4B-0000-4000-8000-00000000A002")!, name: "Lu",
                   appearance: CompanionAppearance(name: "Lu", colorIndex: 5, headwear: .crown, eyewear: .shades),
                   move: .proud,
                   traits: [SharedHighlight(title: "Learning lights them up", symbol: "book", levelLabel: "Possible strength"),
                            SharedHighlight(title: "Night owl focus", symbol: "moon.stars", levelLabel: "Provisional pattern"),
                            SharedHighlight(title: "Friends recharge me", symbol: "person.2", levelLabel: "Confirmed hunch"),
                            SharedHighlight(title: "Music helps me focus", symbol: "music.note", levelLabel: "Confirmed hunch"),
                            SharedHighlight(title: "Movement lights them up", symbol: "figure.walk", levelLabel: "Possible strength")],
                   stage: 3),
        DemoFriend(id: UUID(uuidString: "5A3E0C4B-0000-4000-8000-00000000A003")!, name: "Noa",
                   appearance: CompanionAppearance(name: "Noa", colorIndex: 7, headwear: .catEars, eyewear: .hearts),
                   move: .cheeky,
                   traits: [SharedHighlight(title: "Social butterfly", symbol: "bubble.left.and.bubble.right", levelLabel: "Possible strength")],
                   stage: 1),
        DemoFriend(id: UUID(uuidString: "5A3E0C4B-0000-4000-8000-00000000A004")!, name: "Rafa",
                   appearance: CompanionAppearance(name: "Rafa", colorIndex: 4, headwear: .wizard, eyewear: .glasses),
                   move: .suspicious,
                   traits: [SharedHighlight(title: "Morning focus", symbol: "sunrise", levelLabel: "Provisional pattern"),
                            SharedHighlight(title: "Creativity lights them up", symbol: "paintpalette", levelLabel: "Possible strength"),
                            SharedHighlight(title: "Walks spark my ideas", symbol: "lightbulb", levelLabel: "Confirmed hunch"),
                            SharedHighlight(title: "Board games night", symbol: "dice", levelLabel: "Observation")],
                   stage: 2)
    ]

    static func demoFriendCard(_ friend: DemoFriend, id: UUID? = nil) -> ShareableBrainCard {
        ShareableBrainCard(
            id: id ?? friend.id,
            protocolVersion: ShareableBrainCard.currentVersion,
            displayName: friend.name,
            appearance: friend.appearance,
            stage: friend.stage,
            stageName: CompanionStage.name(friend.stage),
            highlights: friend.traits,
            createdAt: .now,
            isDemo: true,
            mood: nil,
            rings: nil,
            animoji: AnimojiClip.clip(for: friend.move)
        )
    }

    static func demoFriendCard(name: String, id: UUID) -> ShareableBrainCard {
        var friend = demoFriends.first { $0.name == name } ?? demoFriends[0]
        friend = DemoFriend(id: id, name: name, appearance: friend.appearance, move: friend.move,
                            traits: friend.traits, stage: friend.stage)
        return demoFriendCard(friend)
    }
}
