import Foundation

/// A personal experiment: compare two conditions with one short measure over an agreed period.
/// It can be paused or abandoned at any time.
struct Experiment: Identifiable, Codable, Hashable, Sendable {
    enum Status: String, Codable, Sendable {
        case active, paused, finished, abandoned

        var label: String {
            switch self {
            case .active: return "In progress"
            case .paused: return "Paused"
            case .finished: return "Finished"
            case .abandoned: return "Abandoned"
            }
        }
    }

    enum Arm: String, Codable, CaseIterable, Identifiable, Sendable {
        case a, b
        var id: String { rawValue }
    }

    var id: UUID
    var question: String
    var conditionA: String
    var conditionB: String
    var measure: Measure
    var plannedDays: Int
    var startDate: Date
    var status: Status
    var endDate: Date?
    var reflection: String
    var isDemo: Bool

    init(
        id: UUID = UUID(),
        question: String,
        conditionA: String,
        conditionB: String,
        measure: Measure,
        plannedDays: Int,
        startDate: Date = .now,
        status: Status = .active,
        endDate: Date? = nil,
        reflection: String = "",
        isDemo: Bool = false
    ) {
        self.id = id
        self.question = question
        self.conditionA = conditionA
        self.conditionB = conditionB
        self.measure = measure
        self.plannedDays = plannedDays
        self.startDate = startDate
        self.status = status
        self.endDate = endDate
        self.reflection = reflection
        self.isDemo = isDemo
    }

    func label(for arm: Arm) -> String { arm == .a ? conditionA : conditionB }

    var isOpen: Bool { status == .active || status == .paused }
}

/// Starting point for an experiment (from the ideas list or from a discovery).
struct ExperimentTemplate: Hashable, Identifiable, Sendable {
    var id: String { question }
    let question: String
    let conditionA: String
    let conditionB: String
    let measure: Measure
    let plannedDays: Int

    static let all: [ExperimentTemplate] = [
        ExperimentTemplate(question: "Do I focus better in the morning or in the afternoon?",
                           conditionA: "Morning session", conditionB: "Afternoon session",
                           measure: .focus, plannedDays: 10),
        ExperimentTemplate(question: "Do I have more energy on days I move?",
                           conditionA: "Day with movement", conditionB: "Day without movement",
                           measure: .energy, plannedDays: 10),
        ExperimentTemplate(question: "Do I enjoy studying more with others or alone?",
                           conditionA: "With others", conditionB: "Alone",
                           measure: .enjoyment, plannedDays: 14)
    ]
}
