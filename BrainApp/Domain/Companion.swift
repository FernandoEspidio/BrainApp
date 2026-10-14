import Foundation

/// Simple customization of the brain companion.
struct CompanionAppearance: Codable, Hashable, Sendable {
    enum Accessory: String, Codable, CaseIterable, Identifiable, Sendable {
        case none, glasses, headphones, leaf, star

        var id: String { rawValue }

        var label: String {
            switch self {
            case .none: return "None"
            case .glasses: return "Glasses"
            case .headphones: return "Headphones"
            case .leaf: return "Leaf"
            case .star: return "Star"
            }
        }
    }

    var name: String = "Buddy"
    /// Index into `Theme.brainVariants` (brain color).
    var colorIndex: Int = 0
    var accessory: Accessory = .none
}

/// What the brain is "doing" right now. It mirrors a real detected or logged moment,
/// never an invented one, and always comes with its origin (`CompanionState.reason`).
enum BrainMood: String, CaseIterable, Sendable {
    case idle, moving, learning, focused, social, resting, celebrating

    /// Short status line under the brain.
    var title: String {
        switch self {
        case .idle: return "What are we up to?"
        case .moving: return "Pumped!"
        case .learning: return "Lost in a story"
        case .focused: return "In the zone"
        case .social: return "Social battery: full"
        case .resting: return "Recharging…"
        case .celebrating: return "Ooh, something new!"
        }
    }

    var symbol: String {
        switch self {
        case .idle: return "face.smiling"
        case .moving: return "figure.walk"
        case .learning: return "book"
        case .focused: return "pencil"
        case .social: return "bubble.left.and.bubble.right"
        case .resting: return "moon.zzz"
        case .celebrating: return "sparkles"
        }
    }

    init(areaID: String) {
        switch areaID {
        case LifeArea.rest.id: self = .resting
        case LifeArea.learning.id: self = .learning
        case LifeArea.movement.id: self = .moving
        case LifeArea.creativity.id: self = .focused
        case LifeArea.social.id: self = .social
        default: self = .idle
        }
    }
}

struct CompanionState {
    let mood: BrainMood
    /// Explains where the current pose comes from.
    let reason: String
    let stage: Int
}

/// Visual evolution represents accumulated understanding, not activity.
/// It uses a high-water mark so resting or not logging never reduces it.
enum CompanionStage {
    static let names = ["Just arrived", "Getting to know you", "Spotting patterns", "Broad understanding"]
    /// Understanding points needed for each stage (provisional, to validate with users).
    static let thresholds = [0, 3, 7, 12]

    static func stage(forUnderstanding points: Int) -> Int {
        thresholds.lastIndex(where: { points >= $0 }) ?? 0
    }

    static func name(_ stage: Int) -> String {
        names[min(max(stage, 0), names.count - 1)]
    }

    static let explanation = "Your buddy grows with what it understands about you, not with how much you do. Resting or skipping days never makes it decline or feel sad."
}
