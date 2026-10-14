import SwiftUI

/// The brain with up to three discovery bubbles floating around it.
struct BubbleCloudView: View {
    let discoveries: [Discovery]
    let appearance: CompanionAppearance
    let stage: Int
    let newIDs: Set<String>
    let onSelect: (Discovery) -> Void

    /// Fixed spots for 1–3 bubbles: top-left, top-right, bottom.
    private let spots: [UnitPoint] = [UnitPoint(x: 0.18, y: 0.16), UnitPoint(x: 0.82, y: 0.18), UnitPoint(x: 0.5, y: 0.86)]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                BrainAvatarView(appearance: appearance, stage: stage,
                                mood: newIDs.isEmpty ? .idle : .celebrating, size: 200, showsStage: true)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.38)

                ForEach(Array(discoveries.prefix(spots.count).enumerated()), id: \.element.id) { index, discovery in
                    DiscoveryBubble(discovery: discovery, isNew: newIDs.contains(discovery.id)) { onSelect(discovery) }
                        .position(x: geometry.size.width * spots[index].x, y: geometry.size.height * spots[index].y)
                }
            }
        }
    }
}

struct DiscoveryBubble: View {
    let discovery: Discovery
    let isNew: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: discovery.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.pinkDeep)
                Text(discovery.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
            }
            .padding(12)
            .frame(width: 112, height: 112)
            .background(Circle().fill(Theme.card).shadow(color: Theme.ink.opacity(0.08), radius: 10, y: 4))
            .overlay(alignment: .topTrailing) {
                if isNew {
                    Circle().fill(Theme.pinkDeep).frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .offset(x: -8, y: 8)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(discovery.title)\(isNew ? ", new" : "")")
        .accessibilityHint("Shows why")
        .accessibilityAddTraits(.isButton)
    }
}
