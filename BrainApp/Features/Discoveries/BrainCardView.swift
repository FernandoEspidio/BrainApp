import SwiftUI

/// Shareable card: avatar + chosen discoveries. Used in the preview,
/// the exported image and to show a friend's companion.
struct BrainCardView: View {
    let card: ShareableBrainCard

    var body: some View {
        VStack(spacing: 12) {
            BrainAvatarView(appearance: card.appearance, stage: card.stage, size: 100, animated: false)
            Text(card.displayName).font(.title2.bold())
            Text(card.stageName).font(.subheadline).foregroundStyle(.secondary)

            if card.highlights.isEmpty {
                Text("Still exploring").font(.footnote).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(card.highlights, id: \.self) { highlight in
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(highlight.title).font(.subheadline.weight(.semibold))
                                Text(highlight.levelLabel).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: highlight.symbol).foregroundStyle(.tint)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if card.isDemo {
                Text("Fictional example").font(.caption.bold()).foregroundStyle(.orange)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
    }
}
