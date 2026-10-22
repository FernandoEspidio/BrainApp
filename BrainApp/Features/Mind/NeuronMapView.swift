import SwiftUI

/// Your traits as one neuron, at night:
/// - Your brain is the cell body, glowing in the middle.
/// - Each trait sits at the tip of a dendrite (a warm, branching line) as a glowing node.
/// - Thin cool threads join traits that share a part of your life. That's the only thing a thread means.
/// Tap a node: its branch and threads light up and a short line explains it; tap "See why" for the detail.
///
/// Kept deliberately simple: one branch per trait, two small twigs per branch, straight threads.
struct NeuronMapView: View {
    let appearance: CompanionAppearance
    let neurons: [MindNeuron]
    var areaName: (String) -> String = { $0 }
    var onOpen: (MindNeuron) -> Void

    @State private var selectedID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let background = LinearGradient(colors: [Color(hex: 0x2B2540), Color(hex: 0x3A3360)],
                                           startPoint: .top, endPoint: .bottom)
    /// Warm dendrites (brand pink → peach), cool threads (lilac/sky): the two colors of the analogy.
    private static let dendrite = Color(hex: 0xF7A4A0)
    private static let dendriteGlow = Theme.pink
    private static let thread = Color(hex: 0xA9C8F5)

    private let height: CGFloat = 360

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                let size = CGSize(width: geometry.size.width, height: height)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let tips = positions(in: size, center: center)

                ZStack {
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || neurons.isEmpty)) { timeline in
                        let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                        Canvas { context, _ in
                            drawThreads(context, tips: tips)
                            drawDendrites(context, tips: tips, center: center, time: t)
                            drawSoma(context, center: center, time: t)
                        }
                    }
                    .allowsHitTesting(false)

                    BrainPoseView(appearance: appearance, mood: .idle, pose: happyPose, showsHalo: false)
                        .frame(width: 96, height: 96)
                        .position(center)
                        .accessibilityHidden(true)

                    ForEach(Array(neurons.enumerated()), id: \.element.id) { index, neuron in
                        Button {
                            withAnimation(.snappy) { selectedID = selectedID == neuron.id ? nil : neuron.id }
                        } label: {
                            NodeView(neuron: neuron, isSelected: selectedID == neuron.id,
                                     isDimmed: selectedID != nil && !isLinked(neuron, to: selectedID),
                                     labelOnTop: labelOnTop(tips[index], center: center))
                        }
                        .buttonStyle(PressScaleButtonStyle())
                        // Center the sphere (not sphere + label) on the dendrite tip. Labels sit on the far side,
                        // so the branch coming from the brain never crosses them.
                        .position(x: tips[index].x, y: tips[index].y + (labelOnTop(tips[index], center: center) ? -17 : 17))
                        .accessibilityLabel(neuron.title)
                        .accessibilityHint("Shows how it connects")
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.snappy) { selectedID = nil } }
            }
            .frame(height: height)

            if let selected = neurons.first(where: { $0.id == selectedID }) {
                caption(for: selected)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if !neurons.isEmpty {
                legend
            }
        }
        .sensoryFeedback(.selection, trigger: selectedID)
    }

    private var happyPose: FacePose {
        var pose = FacePose()
        pose.smile = 0.7
        pose.squint = 0.4
        return pose
    }

    // MARK: Layout

    /// Evenly around the cell body; with many traits, every other one sits a bit closer (like real dendrites).
    private func positions(in size: CGSize, center: CGPoint) -> [CGPoint] {
        let count = max(neurons.count, 1)
        let rx = size.width / 2 - 50
        let ry = size.height / 2 - 40
        return neurons.indices.map { index in
            let angle = -Double.pi / 2 + Double(index) * 2 * .pi / Double(count) + (count.isMultiple(of: 2) ? .pi / Double(count) : 0)
            let reach: CGFloat = count > 5 && index.isMultiple(of: 2) ? 0.8 : 1
            return CGPoint(x: center.x + rx * reach * CGFloat(cos(angle)), y: center.y + ry * reach * CGFloat(sin(angle)))
        }
    }

    private func labelOnTop(_ tip: CGPoint, center: CGPoint) -> Bool { tip.y < center.y - 20 }

    private func isLinked(_ neuron: MindNeuron, to id: String?) -> Bool {
        guard let id, let other = neurons.first(where: { $0.id == id }) else { return true }
        return neuron.id == id || shared(neuron, other).isEmpty == false
    }

    private func shared(_ a: MindNeuron, _ b: MindNeuron) -> [String] {
        a.areaIDs.filter { b.areaIDs.contains($0) }
    }

    // MARK: Drawing

    private func drawSoma(_ context: GraphicsContext, center: CGPoint, time t: Double) {
        let pulse = 1 + 0.04 * CGFloat(sin(t * 1.8))
        let r = 70 * pulse
        context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                     with: .radialGradient(Gradient(colors: [Self.dendriteGlow.opacity(0.55), Self.dendriteGlow.opacity(0)]),
                                           center: center, startRadius: 20, endRadius: r))
        let core: CGFloat = 50
        context.fill(Path(ellipseIn: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2)),
                     with: .color(Color(hex: 0x4A4170)))
        context.stroke(Path(ellipseIn: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2)),
                       with: .color(Self.dendrite.opacity(0.8)), lineWidth: 3)
    }

    /// One warm branch per trait: thick at the brain, thin at the tip, with two small twigs.
    /// Light impulses travel outward along it.
    private func drawDendrites(_ context: GraphicsContext, tips: [CGPoint], center: CGPoint, time t: Double) {
        for (index, tip) in tips.enumerated() {
            let neuron = neurons[index]
            let active = selectedID == nil || isLinked(neuron, to: selectedID)
            let highlight = selectedID == neuron.id
            let alpha = active ? 1.0 : 0.25

            let dx = tip.x - center.x, dy = tip.y - center.y
            let length = max(sqrt(dx * dx + dy * dy), 1)
            let nx = -dy / length, ny = dx / length          // perpendicular, for the gentle S-curve
            let bend = CGFloat(index.isMultiple(of: 2) ? 16 : -16)
            let start = CGPoint(x: center.x + dx / length * 48, y: center.y + dy / length * 48)
            let end = CGPoint(x: tip.x - dx / length * 26, y: tip.y - dy / length * 26)
            let c1 = CGPoint(x: start.x + (end.x - start.x) * 0.33 + nx * bend, y: start.y + (end.y - start.y) * 0.33 + ny * bend)
            let c2 = CGPoint(x: start.x + (end.x - start.x) * 0.66 - nx * bend, y: start.y + (end.y - start.y) * 0.66 - ny * bend)

            func point(_ s: CGFloat) -> CGPoint {
                let a = 1 - s
                return CGPoint(x: a * a * a * start.x + 3 * a * a * s * c1.x + 3 * a * s * s * c2.x + s * s * s * end.x,
                               y: a * a * a * start.y + 3 * a * a * s * c1.y + 3 * a * s * s * c2.y + s * s * s * end.y)
            }

            // Tapered trunk: three overlapping strokes, widest near the brain.
            for (from, to, width) in [(CGFloat(0), CGFloat(1), CGFloat(2)), (0, 0.6, 3.5), (0, 0.3, 5.5)] {
                var path = Path()
                path.move(to: point(from))
                for step in 1...16 { path.addLine(to: point(from + (to - from) * CGFloat(step) / 16)) }
                context.stroke(path, with: .color(Self.dendriteGlow.opacity((highlight ? 0.5 : 0.25) * alpha)),
                               style: StrokeStyle(lineWidth: width + 5, lineCap: .round, lineJoin: .round))
                context.stroke(path, with: .color(Self.dendrite.opacity(alpha)),
                               style: StrokeStyle(lineWidth: width + (highlight ? 1 : 0), lineCap: .round, lineJoin: .round))
            }

            // Two twigs, each with a tiny fork: enough to read as a neuron, not a diagram.
            for (s, side) in [(CGFloat(0.35), CGFloat(1)), (CGFloat(0.6), CGFloat(-1))] {
                let base = point(s)
                let dir = CGPoint(x: dx / length, y: dy / length)
                let twigEnd = CGPoint(x: base.x + (dir.x * 0.6 + nx * side) * 15, y: base.y + (dir.y * 0.6 + ny * side) * 15)
                var twig = Path()
                twig.move(to: base)
                twig.addQuadCurve(to: twigEnd, control: CGPoint(x: base.x + nx * side * 12, y: base.y + ny * side * 12))
                twig.move(to: twigEnd)
                twig.addLine(to: CGPoint(x: twigEnd.x + (dir.x + nx * side) * 7, y: twigEnd.y + (dir.y + ny * side) * 7))
                twig.move(to: twigEnd)
                twig.addLine(to: CGPoint(x: twigEnd.x + (nx * side * 1.2 - dir.x * 0.2) * 7, y: twigEnd.y + (ny * side * 1.2 - dir.y * 0.2) * 7))
                context.stroke(twig, with: .color(Self.dendrite.opacity(0.75 * alpha)),
                               style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }

            // Impulse: a small spark travelling from the brain to the trait.
            if active {
                let s = CGFloat((t * 0.35 + Double(index) * 0.23).truncatingRemainder(dividingBy: 1))
                let p = point(s)
                let r: CGFloat = 3.5
                context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                             with: .color(.white.opacity(Double(sin(s * .pi)) * 0.9)))
            }
        }
    }

    /// Straight cool threads between traits that share an area (and only then).
    private func drawThreads(_ context: GraphicsContext, tips: [CGPoint]) {
        for i in neurons.indices {
            for j in neurons.indices where j > i {
                guard !shared(neurons[i], neurons[j]).isEmpty else { continue }
                let lit = selectedID == neurons[i].id || selectedID == neurons[j].id
                let alpha = selectedID == nil ? 0.45 : (lit ? 0.95 : 0.12)
                var path = Path()
                path.move(to: tips[i])
                path.addLine(to: tips[j])
                context.stroke(path, with: .color(Self.thread.opacity(alpha * 0.35)), lineWidth: lit ? 7 : 5)
                context.stroke(path, with: .color(Self.thread.opacity(alpha)), lineWidth: lit ? 2 : 1.2)
            }
        }
    }

    // MARK: Text

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(color: Self.dendrite, text: "Learned about you")
            legendItem(color: Self.thread, text: "Share a part of your life")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white.opacity(0.75))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 14, height: 4)
            Text(text)
        }
    }

    private func caption(for neuron: MindNeuron) -> some View {
        let links = neurons.filter { $0.id != neuron.id && !shared($0, neuron).isEmpty }
        let areas = Set(links.flatMap { shared($0, neuron) }).map(areaName).sorted()
        let connection = links.isEmpty
            ? "Not connected to other traits yet."
            : "Connected to \(links.map(\.title).joined(separator: ", ")) through \(areas.joined(separator: " & "))."
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: neuron.symbol)
                Text(neuron.title).font(.subheadline.weight(.bold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            Text(connection)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            Button { onOpen(neuron) } label: {
                Label("See why", systemImage: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white, in: Capsule())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A trait at a dendrite tip: a glowing sphere with its icon, the name underneath.
private struct NodeView: View {
    let neuron: MindNeuron
    let isSelected: Bool
    let isDimmed: Bool
    var labelOnTop = false

    var body: some View {
        let size: CGFloat = neuron.isStrong ? 46 : 40
        let glow: Color = {
            if case .hunch = neuron.source { return Color(hex: 0xC4B5F4) }
            return Color(hex: 0xA9C8F5)
        }()
        VStack(spacing: 4) {
            if labelOnTop { label }
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.white, glow], center: .init(x: 0.35, y: 0.3),
                                         startRadius: 1, endRadius: size * 0.7))
                Image(systemName: neuron.symbol)
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(Color(hex: 0x2B2540))
            }
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(.white.opacity(isSelected ? 1 : 0.5), lineWidth: isSelected ? 3 : 1.5))
            .shadow(color: glow.opacity(isSelected ? 0.9 : 0.6), radius: isSelected ? 14 : 8)
            .scaleEffect(isSelected ? 1.12 : 1)

            if !labelOnTop { label }
        }
        .opacity(isDimmed ? 0.35 : 1)
    }

    private var label: some View {
        Text(neuron.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(hex: 0x2B2540).opacity(0.75), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(width: 100)
    }
}
