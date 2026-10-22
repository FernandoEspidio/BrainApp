import SwiftUI

/// One small palette for the whole app, to avoid color overload:
/// - Brand: brain pink. Text and primary actions: ink. Background: cream.
/// - Each life area owns ONE soft tint (halo, map, chips) and one deeper shade for small marks.
/// Color is never the only cue: icons and labels always accompany it.
enum Theme {
    static let ink = Color(hex: 0x2B2540)
    static let inkSoft = Color(hex: 0x6E6880)
    static let cream = Color(hex: 0xFBF7F2)
    static let card = Color.white
    static let hairline = Color(hex: 0xECE6EE)

    static let pink = Color(hex: 0xF49AC1)
    static let pinkDeep = Color(hex: 0xDE6F9F)
    static let blush = Color(hex: 0xF27BA3)
    static let sun = Color(hex: 0xF5C451)
    static let lavender = Color(hex: 0x8F87E6)

    static let night = Color(hex: 0x2B2540)
    static let nightHalo = Color(hex: 0x3A3360)

    enum Tint {
        static let peach = Color(hex: 0xFDE7D6)
        static let mint = Color(hex: 0xDDF3E8)
        static let sky = Color(hex: 0xE1EAFB)
        static let butter = Color(hex: 0xFCF0C8)
        static let rose = Color(hex: 0xFBE1EC)
        static let lilac = Color(hex: 0xE6E3FA)
    }

    enum Deep {
        static let peach = Color(hex: 0xE59A6B)
        static let mint = Color(hex: 0x4DBB8F)
        static let sky = Color(hex: 0x6E9BEA)
        static let butter = Color(hex: 0xE2AE2F)
        static let rose = Color(hex: 0xE8719F)
        static let lilac = Color(hex: 0x8F87E6)
    }

    /// Brain body colors the user can pick: a closed, curated set of pastels that all sit well on cream,
    /// keep the ink face readable and never clash with the area tints. Pink is the brand default.
    /// Only ever append (the index is stored and shared).
    struct BrainVariant {
        let name: String
        let fill: Color
        let shade: Color
        let light: Color
    }

    static let brainVariants: [BrainVariant] = [
        BrainVariant(name: "Pink", fill: Color(hex: 0xF49AC1), shade: Color(hex: 0xDE6F9F), light: Color(hex: 0xFBC6DD)),
        BrainVariant(name: "Lilac", fill: Color(hex: 0xC4B5F4), shade: Color(hex: 0x9C89E0), light: Color(hex: 0xE2DAFB)),
        BrainVariant(name: "Peach", fill: Color(hex: 0xF8B79A), shade: Color(hex: 0xE08E6C), light: Color(hex: 0xFCD7C5)),
        BrainVariant(name: "Mint", fill: Color(hex: 0x9FDCC2), shade: Color(hex: 0x6CBF9E), light: Color(hex: 0xCBEFDF)),
        BrainVariant(name: "Sky", fill: Color(hex: 0xA9C8F5), shade: Color(hex: 0x7BA3E2), light: Color(hex: 0xD4E4FB)),
        BrainVariant(name: "Butter", fill: Color(hex: 0xF6D57E), shade: Color(hex: 0xDDB04A), light: Color(hex: 0xFBEAB8)),
        BrainVariant(name: "Coral", fill: Color(hex: 0xF7A4A0), shade: Color(hex: 0xE07672), light: Color(hex: 0xFBCFCB)),
        BrainVariant(name: "Aqua", fill: Color(hex: 0x98D9DD), shade: Color(hex: 0x62BBC2), light: Color(hex: 0xCAEEF0))
    ]

    /// An unknown brain (not met yet): flat, colorless silhouette.
    static let mystery = BrainVariant(name: "Unknown", fill: Color(hex: 0xC9C3D3), shade: Color(hex: 0xB3ACC0), light: Color(hex: 0xC9C3D3))

    static func brainVariant(_ index: Int) -> BrainVariant {
        brainVariants[((index % brainVariants.count) + brainVariants.count) % brainVariants.count]
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension LifeArea {
    /// Soft tint: halo, map circles, chips.
    var tint: Color {
        switch id {
        case LifeArea.rest.id: return Theme.Tint.lilac
        case LifeArea.learning.id: return Theme.Tint.sky
        case LifeArea.movement.id: return Theme.Tint.mint
        case LifeArea.creativity.id: return Theme.Tint.butter
        case LifeArea.social.id: return Theme.Tint.rose
        default: return Theme.Tint.peach
        }
    }

    /// Deeper shade for small marks (chart bars, icons on tints).
    var color: Color {
        switch id {
        case LifeArea.rest.id: return Theme.Deep.lilac
        case LifeArea.learning.id: return Theme.Deep.sky
        case LifeArea.movement.id: return Theme.Deep.mint
        case LifeArea.creativity.id: return Theme.Deep.butter
        case LifeArea.social.id: return Theme.Deep.rose
        default: return Theme.Deep.peach
        }
    }
}

extension BrainMood {
    /// Halo behind the brain.
    var halo: Color {
        switch self {
        case .idle, .celebrating: return Theme.Tint.peach
        case .moving: return Theme.Tint.mint
        case .learning: return Theme.Tint.sky
        case .focused: return Theme.Tint.butter
        case .social: return Theme.Tint.rose
        case .resting: return Theme.nightHalo
        }
    }

    /// Only "resting" switches the screen to night.
    var isNight: Bool { self == .resting }
}

// MARK: - Reusable styles

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Theme.ink.opacity(0.06), radius: 12, y: 4)
    }
}

extension View {
    func cardStyle(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }
}

/// Primary button: ink capsule with white text.
struct InkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Theme.ink, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Secondary: soft capsule.
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.ink.opacity(0.06), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// "7h 40m", "45m".
func formatMinutes(_ minutes: Int) -> String {
    let h = minutes / 60
    let m = minutes % 60
    if h == 0 { return "\(m)m" }
    return m == 0 ? "\(h)h" : "\(h)h \(m)m"
}
