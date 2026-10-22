import SwiftUI

/// A friend's brain with its traits orbiting around it like an atom (no orbit lines),
/// playing the move its owner recorded. Bubbles behind the brain shrink and dim, bubbles in front grow:
/// cheap 3D without any 3D engine.
struct BrainOrbitView: View {
    var appearance: CompanionAppearance
    var clip: BrainClip
    var traits: [SharedHighlight]
    /// When the move starts (nil = loop). Change it to replay.
    var playStart: Date?
    /// When the bubbles start popping out of the brain (nil = already out).
    var revealStart: Date?
    var brainSize: CGFloat = 160

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let now = timeline.date
            let t = reduceMotion ? 0 : now.timeIntervalSinceReferenceDate
            let base = BrainExpressions.base(mood: .idle, overallProgress: 0.5, anyRingClosed: false)
            let idle = reduceMotion ? base : BrainExpressions.idle(base, time: t, sleepy: false)
            let pose = reduceMotion ? (clip.frames.first ?? base) : clip.playback(at: now, start: playStart, rest: idle)
            let orbits = traits.indices.map { orbit(index: $0, count: traits.count, time: t, now: now) }

            ZStack {
                ForEach(traits.indices, id: \.self) { index in
                    let o = orbits[index]
                    TraitBubble(trait: traits[index])
                        .scaleEffect(o.scale)
                        .opacity(o.opacity)
                        .offset(x: o.point.x, y: o.point.y)
                        .zIndex(o.depth >= 0 ? 1 : -1)
                }
                BrainPoseView(appearance: appearance, mood: .idle, pose: pose)
                    .frame(width: brainSize, height: brainSize)
                    .zIndex(0)
            }
            .frame(width: brainSize * 2.2, height: brainSize * 1.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let list = traits.map(\.title).joined(separator: ", ")
        return traits.isEmpty ? "\(appearance.name)'s brain" : "\(appearance.name)'s brain. Traits: \(list)"
    }

    private struct Orbit {
        var point: CGPoint
        var depth: Double
        var scale: Double
        var opacity: Double
    }

    private func orbit(index: Int, count: Int, time t: Double, now: Date) -> Orbit {
        // Up to three gently tilted orbits, like an atom's. With more than 3 traits, bubbles share an orbit,
        // evenly spaced, so they never bump into each other. The front of every orbit passes below the face,
        // so bubbles never cover the move being played.
        // 1–2 traits share one orbit, 3–4 use two, 5 use three. Every orbit turns at the same speed,
        // so bubbles keep their spacing and rarely meet where orbits cross.
        let ringCount = count <= 2 ? 1 : (count <= 4 ? 2 : 3)
        let ring = index % ringCount
        let onRing = (count - ring + ringCount - 1) / ringCount
        let slot = index / ringCount
        let tilts = [-0.5, 0.5, 0.0]
        let widths = [0.84, 0.88, 0.74]
        let heights = [0.40, 0.38, 0.30]
        let speed = 0.34
        let tilt = tilts[ring]
        let angle = t * speed + Double(ring) * .pi / Double(ringCount) + Double(slot) * 2 * .pi / Double(max(onRing, 1))
        let rx = Double(brainSize) * widths[ring]
        let ry = Double(brainSize) * heights[ring]
        let local = CGPoint(x: rx * cos(angle), y: ry * sin(angle) + Double(brainSize) * 0.08)
        let rotated = CGPoint(x: local.x * cos(tilt) - local.y * sin(tilt),
                              y: local.x * sin(tilt) + local.y * cos(tilt))
        let depth = sin(angle)

        // Pop out of the brain one by one, with a little overshoot.
        var grow = 1.0
        if let revealStart {
            let p = min(max((now.timeIntervalSince(revealStart) - Double(index) * 0.32) / 0.55, 0), 1)
            grow = easeOutBack(p)
        }
        return Orbit(point: CGPoint(x: rotated.x * grow, y: rotated.y * grow),
                     depth: depth,
                     scale: (0.82 + 0.18 * depth) * max(grow, 0),
                     opacity: min(1, max(grow, 0)) * (0.7 + 0.3 * (depth + 1) / 2))
    }

    private func easeOutBack(_ x: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1
        return x <= 0 ? 0 : 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }
}

/// One trait as a soft bubble.
struct TraitBubble: View {
    let trait: SharedHighlight

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: trait.symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.pinkDeep)
            Text(trait.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: 124)
        .fixedSize(horizontal: false, vertical: true)
        .background(.white, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.Tint.rose, lineWidth: 1.5))
        .shadow(color: Theme.ink.opacity(0.10), radius: 8, y: 3)
    }
}

/// Small static brain for grids (no timers at all: cheap even with many friends).
struct BrainThumbnail: View {
    var appearance: CompanionAppearance
    var pose: FacePose = {
        var p = FacePose()
        p.smile = 0.45
        return p
    }()

    var body: some View {
        BrainPoseView(appearance: appearance, mood: .idle, pose: pose)
    }
}

/// A "not met yet" slot, like an empty page in a collection.
struct MysteryThumbnail: View {
    var body: some View {
        Canvas { context, size in
            BrainDrawing.drawMystery(context, size: size, time: nil)
        }
        .aspectRatio(1, contentMode: .fit)
        .opacity(0.5)
        .accessibilityHidden(true)
    }
}
