import Foundation

/// SPIKE (Lab): six made-up weeks for someone with an Apple Watch, to judge how hints read before
/// real Watch data arrives. Planted on purpose: sleep helps studying and energy, steps and workouts
/// help how days feel, a workout adds sleep that night. The same seed always gives the same days
/// (`SeededGenerator` is in `DemoData`).
enum SampleHealthDays {
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
        }
        // A workout adds about 25 minutes to that night, which counts for the next morning.
        for i in days.indices.dropLast() where days[i].workoutMinutes > 0 {
            days[i + 1].sleepMinutes = (days[i + 1].sleepMinutes ?? 0) + 25
        }

        guard goal != .exercise else { return days }
        for i in days.indices {
            let day = days[i]
            let sleepHours = Double(day.sleepMinutes ?? 420) / 60 - 7
            let steps = (Double(day.steps ?? 7_500) - 7_500) / 4_000
            let worked = day.workoutMinutes > 0 ? 1.0 : 0
            let noise = Double.random(in: -1.2...1.2, using: &random)
            let score: Double
            switch goal {
            case .feel: score = 3.2 + 0.5 * steps + 0.6 * worked + noise
            case .focus: score = 2.6 + 0.9 * sleepHours + noise
            case .energy: score = 3.0 + 0.6 * sleepHours + 0.4 * worked + noise
            case .sleep, .exercise: score = 3.0 + 0.8 * sleepHours + noise
            }
            days[i].answer = min(max(score.rounded(), 1), Double(goal.answers.count))
        }
        return days
    }
}
