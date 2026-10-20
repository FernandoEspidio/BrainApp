import SwiftUI

/// A shared brain: animoji + name, and whatever the owner chose to include
/// (mood, ring percentages, traits). Used for your preview, exported images and friends' cards.
struct BrainCardView: View {
    let card: ShareableBrainCard
    /// false for exported images (draws the first frame).
    var animated = true

    var body: some View {
        VStack(spacing: 14) {
            AnimojiPlayer(appearance: card.appearance, mood: card.brainMood ?? .idle,
                          clip: card.animoji ?? [], animated: animated)
                .frame(width: 150, height: 150)

            VStack(spacing: 2) {
                Text(card.displayName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.ink)
                Text(card.stageName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
            }

            if let mood = card.brainMood {
                MoodChip(mood: mood)
            }

            if let rings = card.rings, !rings.isEmpty {
                SharedRingsRow(rings: rings)
            }

            if !card.highlights.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(card.highlights, id: \.self) { highlight in
                        Label {
                            Text(highlight.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                        } icon: {
                            Image(systemName: highlight.symbol).foregroundStyle(Theme.pinkDeep)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if card.isDemo {
                Text("Fictional example").font(.caption.weight(.bold)).foregroundStyle(Theme.Deep.peach)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct MoodChip: View {
    let mood: BrainMood

    var body: some View {
        Label(mood.title, systemImage: mood.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(mood.halo, in: Capsule())
    }
}

/// Ring without animation state, so it also renders in exported images.
struct StaticRing: View {
    var fraction: Double
    var color: Color
    var lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.0001, min(fraction, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }
}

struct SharedRingsRow: View {
    let rings: [SharedRing]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(rings, id: \.areaID) { ring in
                let area = LifeArea.builtIns.first { $0.id == ring.areaID } ?? .unknown(id: ring.areaID)
                VStack(spacing: 4) {
                    ZStack {
                        StaticRing(fraction: Double(ring.percent) / 100, color: area.ringColor, lineWidth: 4)
                        Image(systemName: area.symbol)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(area.ringColor)
                    }
                    .frame(width: 34, height: 34)
                    Text("\(ring.percent)%")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkSoft)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(area.name) \(ring.percent) percent")
            }
        }
    }
}
