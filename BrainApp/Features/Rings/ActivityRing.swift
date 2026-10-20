import SwiftUI

/// Route to a ring's detail (goal, history, moments).
struct RingRoute: Hashable {
    let id: String
}

/// One animated progress ring. It fills from 0 on appear and springs to new values.
/// A completed ring glows and gently pulses.
struct ActivityRing: View {
    var fraction: Double
    var color: Color
    var lineWidth: CGFloat
    var animateOnAppear = true

    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.0001, min(shown, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .modifier(RingGlow(active: fraction >= 1 && !reduceMotion, color: color, radius: lineWidth * 0.8))
        .onAppear {
            if reduceMotion || !animateOnAppear {
                shown = fraction
            } else {
                withAnimation(.spring(duration: 1.3, bounce: 0.12).delay(0.15)) { shown = fraction }
            }
        }
        .onChange(of: fraction) { _, newValue in
            withAnimation(.spring(duration: 0.9, bounce: 0.15)) { shown = newValue }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}

/// Soft breathing glow for completed rings.
struct RingGlow: ViewModifier {
    var active: Bool
    var color: Color
    var radius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if active {
            content.phaseAnimator([false, true]) { view, phase in
                view.shadow(color: color.opacity(phase ? 0.75 : 0.3), radius: phase ? radius : radius * 0.4)
            } animation: { _ in .easeInOut(duration: 1.4) }
        } else {
            content
        }
    }
}

/// Five concentric rings with the overall percentage in the middle.
struct RingsOverview: View {
    let rings: [RingProgress]
    var size: CGFloat = 250
    var lineWidth: CGFloat = 14
    var gap: CGFloat = 3

    var body: some View {
        let overall = rings.isEmpty ? 0 : rings.map { min($0.fraction, 1) }.reduce(0, +) / Double(rings.count)
        let closed = rings.filter(\.isComplete).count

        ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                let diameter = size - CGFloat(index) * (lineWidth + gap) * 2
                ActivityRing(fraction: ring.fraction, color: ring.area.ringColor, lineWidth: lineWidth)
                    .frame(width: diameter, height: diameter)
            }
            VStack(spacing: 0) {
                Text("\(Int((overall * 100).rounded()))%")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Theme.ink)
                Text("\(closed)/\(rings.count) closed")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Overall \(Int((overall * 100).rounded())) percent, \(closed) of \(rings.count) rings closed")
    }
}

/// Small ring with the area icon inside, percentage and name below. Used in grids and on Today.
struct RingTile: View {
    let ring: RingProgress
    var ringSize: CGFloat = 58
    var showsName = true

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                ActivityRing(fraction: ring.fraction, color: ring.area.ringColor, lineWidth: ringSize * 0.12)
                Image(systemName: ring.isComplete ? "checkmark" : ring.area.symbol)
                    .font(.system(size: ringSize * 0.28, weight: .bold))
                    .foregroundStyle(ring.area.ringColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: ringSize, height: ringSize)
            Text("\(ring.percent)%")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            if showsName {
                Text(ring.area.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ring.area.name), \(ring.percent) percent, \(ring.valueText)")
        .accessibilityAddTraits(.isButton)
    }
}

/// Row of five ring tiles; each pushes the ring's detail.
struct RingTileRow: View {
    let rings: [RingProgress]
    var ringSize: CGFloat = 52
    var showsNames = true

    var body: some View {
        HStack(spacing: 4) {
            ForEach(rings) { ring in
                NavigationLink(value: RingRoute(id: ring.area.id)) {
                    RingTile(ring: ring, ringSize: ringSize, showsName: showsNames)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
