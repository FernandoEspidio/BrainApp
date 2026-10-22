import SwiftUI

/// Today's hub: your brain in the middle, the five life areas around it as small rings,
/// connected by "synapses". Impulses travel from each area that had something today into the brain:
/// your day feeds what your brain learns. Tap an area for its goal and moments.
struct BrainHubView<Brain: View>: View {
    let rings: [RingProgress]
    var size: CGFloat = 360
    @ViewBuilder var brain: () -> Brain

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let nodeSize: CGFloat = 54
    private let brainShare: CGFloat = 0.46

    var body: some View {
        let center = CGPoint(x: size / 2, y: size / 2)
        let radius = size / 2 - nodeSize / 2 - 6
        let points = positions(center: center, radius: radius)

        ZStack {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, _ in
                    for (index, ring) in rings.enumerated() where index < points.count {
                        drawSynapse(context, from: points[index], to: center, ring: ring, index: index, time: t)
                    }
                }
            }
            .allowsHitTesting(false)

            brain()
                .frame(width: size * brainShare, height: size * brainShare)
                .position(center)

            ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                if index < points.count {
                    NavigationLink(value: RingRoute(id: ring.area.id)) {
                        AreaNode(ring: ring, size: nodeSize)
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .position(points[index])
                }
            }
        }
        .frame(width: size, height: size)
    }

    /// A pentagon around the brain, slightly flattened so the ring under the brain stays clear of its feet.
    private func positions(center: CGPoint, radius: CGFloat) -> [CGPoint] {
        rings.indices.map { index in
            let angle = -Double.pi / 2 + Double(index) * 2 * .pi / Double(max(rings.count, 1))
            return CGPoint(x: center.x + radius * CGFloat(cos(angle)),
                           y: center.y + radius * 0.94 * CGFloat(sin(angle)))
        }
    }

    private func drawSynapse(_ context: GraphicsContext, from node: CGPoint, to center: CGPoint,
                             ring: RingProgress, index: Int, time t: Double) {
        let color = ring.area.ringColor
        let progress = min(ring.fraction, 1)
        // Stop at the edges: from the node's rim to the brain's halo.
        let dx = center.x - node.x, dy = center.y - node.y
        let length = max(sqrt(dx * dx + dy * dy), 1)
        let ux = dx / length, uy = dy / length
        let start = CGPoint(x: node.x + ux * nodeSize * 0.55, y: node.y + uy * nodeSize * 0.55)
        // The halo is ~87% of the brain's frame.
        let haloRadius = size * brainShare / 2 * 0.9
        let end = CGPoint(x: center.x - ux * haloRadius, y: center.y - uy * haloRadius)
        // A gentle curve reads more "neural" than a straight line.
        let mid = CGPoint(x: (start.x + end.x) / 2 - uy * 14, y: (start.y + end.y) / 2 + ux * 14)
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: mid)
        context.stroke(path, with: .color(color.opacity(0.18 + 0.45 * progress)),
                       style: StrokeStyle(lineWidth: ring.isComplete ? 4 : 2.5, lineCap: .round, dash: progress > 0 ? [] : [3, 6]))

        // Impulses flow into the brain from areas that had something today.
        guard ring.value > 0 else { return }
        let pulses = ring.isComplete ? 2 : 1
        for pulse in 0..<pulses {
            let s = (t * 0.45 + Double(index) * 0.21 + Double(pulse) * 0.5).truncatingRemainder(dividingBy: 1)
            let a = 1 - s
            let p = CGPoint(x: a * a * start.x + 2 * a * s * mid.x + s * s * end.x,
                            y: a * a * start.y + 2 * a * s * mid.y + s * s * end.y)
            let r: CGFloat = 4.5
            context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(color.opacity(sin(s * .pi))))
        }
    }
}

/// One life area: a ring with its icon, and the name underneath.
struct AreaNode: View {
    let ring: RingProgress
    let size: CGFloat

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().fill(.white)
                ActivityRing(fraction: ring.fraction, color: ring.area.ringColor, lineWidth: 5)
                    .padding(3)
                Image(systemName: ring.isComplete ? "checkmark" : ring.area.symbol)
                    .font(.system(size: size * 0.3, weight: .bold))
                    .foregroundStyle(ring.area.ringColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: size, height: size)
            .shadow(color: Theme.ink.opacity(0.08), radius: 6, y: 2)
            Text(ring.area.name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ring.area.name), \(ring.percent) percent")
        .accessibilityHint("Opens goal and moments")
    }
}

/// The brain's thought, floating above it: what it noticed about you (or what it's learning).
/// Tapping it opens the discovery with "That's me / Not me / Test it".
struct ThoughtBubble: View {
    let eyebrow: String
    let text: String
    var symbol = "sparkles"
    /// 0…1 when the brain is still learning (shows dots instead of a chevron).
    var learning: (count: Int, total: Int)? = nil
    var isTappable = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Label(eyebrow, systemImage: symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.pinkDeep)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(text)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .contentTransition(.opacity)
                    Spacer(minLength: 0)
                    if isTappable && learning == nil {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.pinkDeep)
                    }
                }
                if let learning {
                    HStack(spacing: 5) {
                        ForEach(0..<learning.total, id: \.self) { index in
                            Circle().fill(index < learning.count ? Theme.pink : Theme.hairline).frame(width: 8, height: 8)
                        }
                        Text("\(learning.count)/\(learning.total)")
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Theme.ink.opacity(0.08), radius: 10, y: 4)

            // Thought "trail" toward the brain below.
            HStack(spacing: 0) {
                Spacer()
                VStack(alignment: .leading, spacing: 3) {
                    Circle().fill(.white).frame(width: 13, height: 13)
                    Circle().fill(.white).frame(width: 8, height: 8).offset(x: 10)
                }
                .shadow(color: Theme.ink.opacity(0.06), radius: 3, y: 1)
                Spacer().frame(width: 120)
            }
            .padding(.top, 4)
        }
        .accessibilityElement(children: .combine)
    }
}
