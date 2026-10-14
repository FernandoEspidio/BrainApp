import Foundation

/// A life area shown around the companion on the map.
/// The five base areas are fixed; users can add their own ("Other areas").
struct LifeArea: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var symbol: String
    var isBuiltIn: Bool
    var paletteIndex: Int

    static let rest = LifeArea(id: "rest", name: "Rest", symbol: "moon.zzz", isBuiltIn: true, paletteIndex: 0)
    static let learning = LifeArea(id: "learning", name: "Learning", symbol: "book", isBuiltIn: true, paletteIndex: 1)
    static let movement = LifeArea(id: "movement", name: "Movement", symbol: "figure.walk", isBuiltIn: true, paletteIndex: 2)
    static let creativity = LifeArea(id: "creativity", name: "Creativity", symbol: "paintpalette", isBuiltIn: true, paletteIndex: 3)
    static let social = LifeArea(id: "social", name: "Social", symbol: "person.2", isBuiltIn: true, paletteIndex: 4)

    static let builtIns: [LifeArea] = [.rest, .learning, .movement, .creativity, .social]

    /// Used if an entry points to an area that no longer exists.
    static func unknown(id: String) -> LifeArea {
        LifeArea(id: id, name: "Other area", symbol: "circle.dashed", isBuiltIn: false, paletteIndex: 7)
    }

    /// Icons offered for custom areas.
    static let customSymbols = ["star", "leaf", "heart", "briefcase", "house", "gamecontroller", "music.note", "fork.knife", "globe.americas", "hammer"]
}

/// How much an area matters to the user right now. Balance is read against this,
/// never against a universal ratio.
enum Priority: Int, Codable, CaseIterable, Identifiable, Sendable {
    case notNow = 0, some, important, veryImportant

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .notNow: return "Not a priority now"
        case .some: return "Somewhat"
        case .important: return "Important"
        case .veryImportant: return "Very important"
        }
    }
}

/// "1 entry" / "3 entries".
func countLabel(_ n: Int, _ one: String, _ many: String) -> String {
    "\(n) \(n == 1 ? one : many)"
}
