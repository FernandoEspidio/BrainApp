import Foundation

/// What the person protects: picked on day one, changeable any time. It sets the one daily question
/// and the number every hint is about (see `HintEngine`).
enum Goal: String, CaseIterable, Identifiable, Codable, Sendable {
    case feel, focus, energy, sleep, exercise

    var id: String { rawValue }

    var label: String {
        switch self {
        case .feel: return "How my days feel"
        case .focus: return "Focus / study"
        case .energy: return "Energy"
        case .sleep: return "Sleep"
        case .exercise: return "Exercise"
        }
    }

    /// For the buddy's sentences: "compare with your sleep".
    var noun: String {
        switch self {
        case .feel: return "how your days feel"
        case .focus: return "your studying"
        case .energy: return "your energy"
        case .sleep: return "your sleep"
        case .exercise: return "your exercise"
        }
    }

    /// The one daily question. Exercise has none: Health measures it. Sleep skips it when a Watch measures sleep.
    var question: String? {
        switch self {
        case .feel: return "How was today?"
        case .focus: return "How did studying go?"
        case .energy: return "How was your energy?"
        case .sleep: return "How did you sleep?"
        case .exercise: return nil
        }
    }

    /// Answers, worst first. An answer is stored as its position, from 1.
    var answers: [String] {
        switch self {
        case .feel: return ["Awful", "Meh", "OK", "Good", "Great"]
        case .focus: return ["Didn't study", "Badly", "OK", "Well"]
        case .energy: return ["Drained", "Low", "OK", "Good", "Full"]
        case .sleep: return ["Awful", "Poor", "OK", "Good", "Great"]
        case .exercise: return []
        }
    }

    var symbol: String {
        switch self {
        case .feel: return "face.smiling"
        case .focus: return "book"
        case .energy: return "bolt"
        case .sleep: return "moon.zzz"
        case .exercise: return "figure.run"
        }
    }

    /// Sleep asks about the night that just ended, so in the morning. The others ask in the evening.
    var asksInMorning: Bool { self == .sleep }

    /// Today shows the question from this hour: about a day that's mostly done, or a night just ended.
    var questionFromHour: Int { asksInMorning ? 5 : 18 }

    /// The optional daily reminder, at 9 am or 9 pm.
    var reminderHour: Int { asksInMorning ? 9 : 21 }

    /// From this answer up, a day counts as good: "OK" for studying, "Good" for the others.
    var goodAnswer: Double { self == .focus ? 3 : 4 }

    /// "5 of 6 good study days".
    var goodDays: String {
        switch self {
        case .feel: return "good days"
        case .focus: return "good study days"
        case .energy: return "high-energy days"
        case .sleep: return "good nights"
        case .exercise: return "active days"
        }
    }

    /// "came with better study days".
    func change(better: Bool) -> String {
        switch self {
        case .feel: return better ? "better days" : "worse days"
        case .focus: return better ? "better study days" : "worse study days"
        case .energy: return better ? "more energy" : "less energy"
        case .sleep: return better ? "better sleep" : "worse sleep"
        case .exercise: return better ? "more exercise" : "less exercise"
        }
    }
}
