import Foundation

/// Six made-up weeks for someone with an Apple Watch: what Today shows in demo mode, and what
/// Lab → Hints uses to judge how hints read before real Watch data arrives. Planted on purpose: sleep helps studying and energy, steps, workouts and
/// guitar help how days feel, the library helps studying, a workout adds sleep that night and late
/// coffee takes some away. Groceries change nothing, to catch hits by luck. The same seed always
/// gives the same days (`SeededGenerator` is in `DemoData`).
enum SampleHealthDays {
    /// Logged activities and how often they happen.
    private static let activities = [("Play guitar", 0.4), ("Study at the library", 0.35),
                                     ("Coffee after 4 pm", 0.25), ("Groceries", 0.3)]

    static func watchOwner(goal: Goal, count: Int = 42, now: Date = .now, calendar: Calendar = .current) -> [HealthDay] {
        var random = SeededGenerator(seed: 42)
        let today = calendar.startOfDay(for: now)
        var days = (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { HealthDay(date: $0) }
        }

        for i in days.indices {
            let workout = Double.random(in: 0...1, using: &random) < 0.35 ? Int.random(in: 25...60, using: &random) : 0
            days[i].sleepMinutes = Int.random(in: 330...510, using: &random)
            days[i].workoutMinutes = workout
            days[i].steps = Int.random(in: 3_000...12_000, using: &random) + workout * 60
            days[i].exerciseMinutes = workout + Int.random(in: 0...20, using: &random)
            days[i].mindfulMinutes = Double.random(in: 0...1, using: &random) < 0.2 ? 10 : 0
            for (name, chance) in activities where Double.random(in: 0...1, using: &random) < chance {
                days[i].activities.insert(name)
            }
        }
        // A workout adds about 25 minutes to that night, late coffee takes 30 away.
        // The night counts for the next morning.
        for i in days.indices.dropLast() {
            var change = days[i].workoutMinutes > 0 ? 25 : 0
            if days[i].activities.contains("Coffee after 4 pm") { change -= 30 }
            days[i + 1].sleepMinutes = (days[i + 1].sleepMinutes ?? 0) + change
        }

        guard goal != .exercise else { return days }
        for i in days.indices {
            let day = days[i]
            let sleepHours = Double(day.sleepMinutes ?? 420) / 60 - 7
            let steps = (Double(day.steps ?? 7_500) - 7_500) / 4_000
            let worked = day.workoutMinutes > 0 ? 1.0 : 0
            let guitar = day.activities.contains("Play guitar") ? 1.0 : 0
            let library = day.activities.contains("Study at the library") ? 1.0 : 0
            let noise = Double.random(in: -1.2...1.2, using: &random)
            let score: Double
            switch goal {
            case .feel: score = 3.0 + 0.5 * steps + 0.6 * worked + 0.8 * guitar + noise
            case .focus: score = 2.3 + 0.9 * sleepHours + 0.8 * library + noise
            case .energy: score = 2.9 + 0.6 * sleepHours + 0.4 * worked + 0.3 * guitar + noise
            case .sleep, .exercise: score = 3.0 + 0.8 * sleepHours + noise
            }
            days[i].answer = min(max(score.rounded(), 1), Double(goal.answers.count))
        }
        return days
    }
}
