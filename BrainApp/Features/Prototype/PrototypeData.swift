import SwiftUI

/// LOOK-ONLY PROTOTYPE of "Test your hunch" (issue #1), so the team can see the design before Thursday.
/// Every word and number lives here and is made up: nothing reads Health, saves or runs an engine.
/// Types are nested so they never clash with the real `Guess` and `Verdict`.
enum PrototypeData {
    static let daysNeeded = 10

    /// The three moments of the two weeks the demo jumps between.
    enum Day: Int, CaseIterable, Identifiable {
        case one = 1, seven = 7, fourteen = 14

        var id: Int { rawValue }
        var label: String { "Day \(rawValue)" }
    }

    /// A guess about what helps you study. Health counts some; the student logs the rest.
    struct Guess: Identifiable, Hashable {
        let id: String
        let label: String
        /// "Sleep", for progress lines.
        let short: String
        let symbol: String
        let tint: Color
        let isLogged: Bool
        /// Offered when the days are too alike to tell.
        let experiment: String

        var source: String { isLogged ? "You log it" : "Health counts it" }
        var sourceSymbol: String { isLogged ? "hand.tap" : "heart" }
    }

    static let sleep = Guess(id: "sleep", label: "More sleep", short: "Sleep", symbol: "moon.zzz",
                             tint: Theme.Tint.lilac, isLogged: false,
                             experiment: "For a week, go to bed 30 minutes earlier every other night.")
    static let walking = Guess(id: "walking", label: "Walking", short: "Walking", symbol: "figure.walk",
                               tint: Theme.Tint.mint, isLogged: false,
                               experiment: "For a week, take a 20-minute walk every other day.")
    static let workouts = Guess(id: "workouts", label: "Workouts", short: "Workouts", symbol: "dumbbell",
                                tint: Theme.Tint.peach, isLogged: false,
                                experiment: "For a week, work out every other day.")
    static let library = Guess(id: "library", label: "Studying at the library", short: "Library", symbol: "building.columns",
                               tint: Theme.Tint.sky, isLogged: true,
                               experiment: "For a week, study at the library every other day.")
    static let coffee = Guess(id: "coffee", label: "Afternoon coffee", short: "Coffee", symbol: "cup.and.saucer",
                              tint: Theme.Tint.butter, isLogged: true,
                              experiment: "For a week, have coffee after 4 pm every other day.")
    static let music = Guess(id: "music", label: "Music while studying", short: "Music", symbol: "headphones",
                             tint: Theme.Tint.rose, isLogged: true,
                             experiment: "For a week, put music on every other study session.")

    static let guesses = [sleep, walking, workouts, library, coffee, music]
    /// The demo student's three guesses.
    static let demoPicks = [sleep, library, coffee]

    /// Where a guess stands. Leans are never answers; settled ones free their slot.
    enum Status: Equatable {
        case watching, leaningYes, leaningNo, right, noDifference, opposite, cantTell

        var label: String {
            switch self {
            case .watching: return "Watching"
            case .leaningYes: return "Leaning yes"
            case .leaningNo: return "Leaning no"
            case .right: return "You're right"
            case .noDifference: return "Doesn't seem to matter"
            case .opposite: return "The opposite"
            case .cantTell: return "Can't tell yet"
            }
        }

        var symbol: String {
            switch self {
            case .watching: return "eye"
            case .leaningYes: return "arrow.up.right"
            case .leaningNo: return "arrow.down.right"
            case .right: return "checkmark"
            case .noDifference: return "equal"
            case .opposite: return "arrow.uturn.down"
            case .cantTell: return "questionmark"
            }
        }

        var isSettled: Bool { self == .right || self == .noDifference || self == .opposite }
    }

    /// One guess on one demo day.
    struct Standing {
        let status: Status
        /// Days with both the guess and an answer. Today is left out.
        let counted: Int
        /// One quiet line once settled.
        var line: String?
    }

    /// The story: watching on day 1, leaning on sleep by day 7, three verdicts on day 14.
    /// `alikeDays` is the other day 14, where the student went to the library every day.
    static func standing(of guess: Guess, on day: Day, alikeDays: Bool = false) -> Standing {
        switch day {
        case .one:
            return Standing(status: .watching, counted: 0)
        case .seven:
            return Standing(status: guess == sleep ? .leaningYes : .watching, counted: 6)
        case .fourteen:
            switch guess {
            case sleep:
                return Standing(status: .right, counted: 13, line: "Nights over 7h 10m came with better study days.")
            case library where alikeDays:
                return Standing(status: .cantTell, counted: 13)
            case library:
                return Standing(status: .right, counted: 13, line: "Library days came with better study days.")
            case coffee:
                return Standing(status: .noDifference, counted: 13, line: "It came with 30 minutes less sleep.")
            default:
                return Standing(status: .noDifference, counted: 13, line: "It came with about the same study days.")
            }
        }
    }

    /// "You studied at the library on 12 of 13 days."
    static func alikeLine(for guess: Guess) -> String {
        guess.isLogged ? "You logged \(guess.short.lowercased()) on 12 of 13 days." : "Your days were almost all the same."
    }

    /// The reveal: big type, one number, one honest line, and the comparison behind it.
    struct Verdict: Identifiable {
        var id: String { guess.id }
        let guess: Guess
        let status: Status
        let headline: String
        var sideEffect: String?
        /// The one number, big: "5 of 6".
        let number: String
        /// The rest of its sentence: "good study days after …, vs 2 of 7".
        let numberDetail: String
        var sentence: String?
        /// The two bars behind "Why?".
        let bars: [Evidence.Row]
        var barsNote: String?
        let mood: BrainMood
    }

    static func verdict(for guess: Guess) -> Verdict? {
        switch guess {
        case sleep:
            return Verdict(
                guess: sleep, status: .right,
                headline: "You're right about sleep.",
                number: "5 of 6",
                numberDetail: "good study days after nights over 7h 10m, vs 2 of 7",
                sentence: "Nights over 7h 10m came with better study days.",
                bars: [bar("After nights over 7h 10m", good: 5, of: 6), bar("After shorter nights", good: 2, of: 7)],
                mood: .celebrating
            )
        case library:
            return Verdict(
                guess: library, status: .right,
                headline: "You're right about the library.",
                number: "4 of 5",
                numberDetail: "good study days at the library, vs 3 of 8 elsewhere",
                sentence: "Library days came with better study days.",
                bars: [bar("At the library", good: 4, of: 5), bar("Elsewhere", good: 3, of: 8)],
                mood: .celebrating
            )
        case coffee:
            return Verdict(
                guess: coffee, status: .noDifference,
                headline: "Coffee didn't help your studying",
                sideEffect: "and it came with 30 minutes less sleep that night.",
                number: "3 of 5",
                numberDetail: "good study days after afternoon coffee, vs 4 of 8 without",
                bars: [bar("With coffee after 4 pm", good: 3, of: 5), bar("Without", good: 4, of: 8)],
                barsNote: "Sleep those nights: 6h 40m after coffee, vs 7h 10m without.",
                mood: .idle
            )
        default:
            return nil
        }
    }

    private static func bar(_ label: String, good: Int, of total: Int) -> Evidence.Row {
        Evidence.Row(label: label, value: "\(good) of \(total)", count: total, fraction: Double(good) / Double(total))
    }

    /// What the buddy says on Today: the newest verdict, or what it's waiting for.
    static func buddyLine(on day: Day, guesses: [Guess], alikeDays: Bool, answered: Bool) -> String {
        switch day {
        case .one:
            return answered ? "Day one counted. See you tomorrow." : "I'm watching. Tonight's answer is day one."
        case .seven:
            return guesses.contains(sleep) ? "Leaning yes on sleep. Too early to call." : "Six days in. Nothing to call yet."
        case .fourteen:
            guard let verdict = newestVerdict(among: guesses, alikeDays: alikeDays) else {
                return alikeDays && guesses.contains(library) ? "Your days are too alike to tell." : "Two weeks in. Have a look."
            }
            return verdict.sideEffect == nil ? verdict.headline : verdict.headline + "."
        }
    }

    /// The verdict Day 14 opens with: a "right" first.
    static func newestVerdict(among guesses: [Guess], alikeDays: Bool) -> Verdict? {
        let verdicts = guesses
            .filter { standing(of: $0, on: .fourteen, alikeDays: alikeDays).status.isSettled }
            .compactMap { verdict(for: $0) }
        return verdicts.first { $0.status == .right } ?? verdicts.first
    }
}
