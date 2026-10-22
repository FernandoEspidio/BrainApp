import Foundation

/// A hunch: something you believe about yourself ("Music helps me focus"), checked a little every day.
/// It's the "Test it → Confirm it" half of the loop:
///   Observe (moments) → Discover (patterns) → Test it (hunch) → Confirm it (becomes a trait you can share).
/// The app never decides for you: after enough check-ins it shows how the days went and YOU choose.
struct Hunch: Identifiable, Codable, Hashable, Sendable {
    enum Answer: String, Codable, CaseIterable, Sendable {
        case yes, no, unsure

        var label: String {
            switch self {
            case .yes: return "Yes"
            case .no: return "No"
            case .unsure: return "Not sure"
            }
        }

        var symbol: String {
            switch self {
            case .yes: return "checkmark"
            case .no: return "xmark"
            case .unsure: return "questionmark"
            }
        }
    }

    enum Status: String, Codable, Sendable {
        case testing, confirmed, notReally

        var label: String {
            switch self {
            case .testing: return "Testing"
            case .confirmed: return "Confirmed"
            case .notReally: return "Not really"
            }
        }
    }

    struct CheckIn: Codable, Hashable, Sendable {
        var day: Date
        var answer: Answer
    }

    /// How a finished test leans, shown to the user before they decide.
    enum Leaning: Equatable {
        case holds, doesNotHold, mixed
    }

    static let defaultTarget = 5

    var id: UUID = UUID()
    /// First person, as the user would say it: "Music helps me focus".
    var statement: String
    /// The daily question: "Did music help you focus today?"
    var question: String
    var symbol: String = "lightbulb"
    /// The connection it proposes between areas (0–2 areas).
    var areaIDs: [String] = []
    var createdAt: Date = .now
    var targetCheckIns: Int = Hunch.defaultTarget
    var checkIns: [CheckIn] = []
    var status: Status = .testing
    var isDemo = false

    var answeredCount: Int { checkIns.filter { $0.answer != .unsure }.count }
    var yesCount: Int { checkIns.filter { $0.answer == .yes }.count }
    var progress: Double { min(Double(answeredCount) / Double(max(targetCheckIns, 1)), 1) }
    var isReadyToDecide: Bool { status == .testing && answeredCount >= targetCheckIns }

    var leaning: Leaning? {
        guard answeredCount >= targetCheckIns else { return nil }
        let share = Double(yesCount) / Double(answeredCount)
        if share >= 0.7 { return .holds }
        if share <= 0.3 { return .doesNotHold }
        return .mixed
    }

    func answer(on day: Date, calendar: Calendar = .current) -> Answer? {
        checkIns.last { calendar.isDate($0.day, inSameDayAs: day) }?.answer
    }

    // MARK: Tolerant decoding (new fields never break saved hunches)

    init(id: UUID = UUID(), statement: String, question: String, symbol: String = "lightbulb", areaIDs: [String] = [],
         createdAt: Date = .now, targetCheckIns: Int = Hunch.defaultTarget, checkIns: [CheckIn] = [],
         status: Status = .testing, isDemo: Bool = false) {
        self.id = id
        self.statement = statement
        self.question = question
        self.symbol = symbol
        self.areaIDs = areaIDs
        self.createdAt = createdAt
        self.targetCheckIns = targetCheckIns
        self.checkIns = checkIns
        self.status = status
        self.isDemo = isDemo
    }

    private enum CodingKeys: String, CodingKey {
        case id, statement, question, symbol, areaIDs, createdAt, targetCheckIns, checkIns, status, isDemo
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        statement = try c.decodeIfPresent(String.self, forKey: .statement) ?? ""
        question = try c.decodeIfPresent(String.self, forKey: .question) ?? "Was it true today?"
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "lightbulb"
        areaIDs = try c.decodeIfPresent([String].self, forKey: .areaIDs) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        targetCheckIns = try c.decodeIfPresent(Int.self, forKey: .targetCheckIns) ?? Hunch.defaultTarget
        checkIns = try c.decodeIfPresent([CheckIn].self, forKey: .checkIns) ?? []
        status = (try? c.decodeIfPresent(Status.self, forKey: .status)) ?? .testing
        isDemo = try c.decodeIfPresent(Bool.self, forKey: .isDemo) ?? false
    }
}

/// Ready-made hunches: connections people often suspect between parts of their life.
struct HunchTemplate: Identifiable, Hashable, Sendable {
    var id: String { statement }
    let statement: String
    let question: String
    let symbol: String
    let areaIDs: [String]

    func make(isDemo: Bool = false) -> Hunch {
        Hunch(statement: statement, question: question, symbol: symbol, areaIDs: areaIDs, isDemo: isDemo)
    }

    static let all: [HunchTemplate] = [
        HunchTemplate(statement: "Music helps me focus", question: "Did music help you focus today?",
                      symbol: "music.note", areaIDs: [LifeArea.creativity.id, LifeArea.learning.id]),
        HunchTemplate(statement: "I learn better after I move", question: "Did moving first help you learn today?",
                      symbol: "figure.walk", areaIDs: [LifeArea.movement.id, LifeArea.learning.id]),
        HunchTemplate(statement: "Good sleep makes me more social", question: "After sleeping well, did you feel like seeing people?",
                      symbol: "moon.stars", areaIDs: [LifeArea.rest.id, LifeArea.social.id]),
        HunchTemplate(statement: "Walks spark my ideas", question: "Did a walk bring you an idea today?",
                      symbol: "lightbulb", areaIDs: [LifeArea.movement.id, LifeArea.creativity.id]),
        HunchTemplate(statement: "Friends recharge me", question: "Did seeing someone give you energy today?",
                      symbol: "person.2", areaIDs: [LifeArea.social.id, LifeArea.rest.id])
    ]

    /// "Test it" on a discovery: the pattern the app saw becomes something you check yourself.
    static func from(_ discovery: Discovery) -> HunchTemplate {
        HunchTemplate(statement: discovery.title, question: "Was this true today: “\(discovery.title)”?",
                      symbol: discovery.symbol, areaIDs: Array(discovery.areaIDs.prefix(2)))
    }
}
