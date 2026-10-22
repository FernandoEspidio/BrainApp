import Foundation

/// Customization of the brain companion: a name, a curated color and two accessory slots
/// (something on the head, something on the eyes) so looks can be combined.
struct CompanionAppearance: Hashable, Sendable {
    enum Headwear: String, CaseIterable, Identifiable, Sendable {
        case none, sprout, star, crown, beanie, party, bow, cap, headphones, catEars, flower, wizard

        var id: String { rawValue }

        var label: String {
            switch self {
            case .none: return "None"
            case .sprout: return "Sprout"
            case .star: return "Star"
            case .crown: return "Crown"
            case .beanie: return "Beanie"
            case .party: return "Party hat"
            case .bow: return "Bow"
            case .cap: return "Cap"
            case .headphones: return "Headphones"
            case .catEars: return "Cat ears"
            case .flower: return "Flower"
            case .wizard: return "Wizard hat"
            }
        }
    }

    enum Eyewear: String, CaseIterable, Identifiable, Sendable {
        case none, glasses, shades, hearts, stars

        var id: String { rawValue }

        var label: String {
            switch self {
            case .none: return "None"
            case .glasses: return "Glasses"
            case .shades: return "Shades"
            case .hearts: return "Heart shades"
            case .stars: return "Star shades"
            }
        }
    }

    var name: String = "Buddy"
    /// Index into `Theme.brainVariants` (brain color).
    var colorIndex: Int = 0
    var headwear: Headwear = .none
    var eyewear: Eyewear = .none

    init(name: String = "Buddy", colorIndex: Int = 0, headwear: Headwear = .none, eyewear: Eyewear = .none) {
        self.name = name
        self.colorIndex = colorIndex
        self.headwear = headwear
        self.eyewear = eyewear
    }

    var outfit: Outfit { Outfit(headwear: headwear, eyewear: eyewear) }
}

/// What the brain wears (passed to the drawing code).
struct Outfit: Hashable, Sendable {
    var headwear: CompanionAppearance.Headwear = .none
    var eyewear: CompanionAppearance.Eyewear = .none
    static let none = Outfit()
}

/// Tolerant coding: unknown accessories (from a newer app) become `.none` instead of failing,
/// and the first prototype's single `accessory` field is read into the right slot.
extension CompanionAppearance: Codable {
    private enum CodingKeys: String, CodingKey { case name, colorIndex, headwear, eyewear, accessory }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Buddy"
        colorIndex = try c.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
        headwear = (try? c.decodeIfPresent(String.self, forKey: .headwear)).flatMap(Headwear.init(rawValue:)) ?? .none
        eyewear = (try? c.decodeIfPresent(String.self, forKey: .eyewear)).flatMap(Eyewear.init(rawValue:)) ?? .none
        if let legacy = try? c.decodeIfPresent(String.self, forKey: .accessory) {
            switch legacy {
            case "glasses": if eyewear == .none { eyewear = .glasses }
            case "headphones": if headwear == .none { headwear = .headphones }
            case "leaf": if headwear == .none { headwear = .sprout }
            case "star": if headwear == .none { headwear = .star }
            default: break
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(colorIndex, forKey: .colorIndex)
        try c.encode(headwear.rawValue, forKey: .headwear)
        try c.encode(eyewear.rawValue, forKey: .eyewear)
    }
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
