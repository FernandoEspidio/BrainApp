import SwiftUI

// The three scenes of a brain trade, all drawn with Canvas + TimelineView (no assets, no video):
// 1. Search: your brain and an unknown silhouette look for each other around a bush.
// 2. Portal: an air vortex at the top; swipe your brain into it, it rumbles more the closer it gets.
// 3. Arrival: their brain drops out of the portal and its traits start orbiting.

// MARK: - 1. Search

struct SearchScene: View {
    var appearance: CompanionAppearance
    /// The other brain was found: it pops out from behind the bush.
    var found: Bool
    /// A friend you already know shows their real colors instead of the gray silhouette.
    var foundAppearance: CompanionAppearance? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var foundAt: Date?

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let bush = CGPoint(x: w / 2, y: h * 0.56)
            let size = min(w * 0.42, 170)

            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let t = reduceMotion ? 1.2 : timeline.date.timeIntervalSinceReferenceDate
                let me = myPeek(time: t, now: timeline.date)
                let them = theirPeek(time: t, now: timeline.date)
                ZStack {
                    // Ground
                    Ellipse()
                        .fill(Theme.Deep.mint.opacity(0.14))
                        .frame(width: w * 0.9, height: 46)
                        .position(x: bush.x, y: bush.y + size * 0.48)

                    // Unknown brain (behind the bush until found); a known friend appears in color.
                    Group {
                        if let foundAppearance, foundAt != nil {
                            BrainPoseView(appearance: foundAppearance, mood: .idle, pose: friendPose(time: t), showsHalo: false)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        } else {
                            Canvas { context, canvasSize in
                                BrainDrawing.drawMystery(context, size: canvasSize, time: reduceMotion ? nil : t, lookX: -1)
                            }
                        }
                    }
                    .frame(width: size * 0.92, height: size * 0.92)
                    .rotationEffect(.degrees(them.tilt))
                    .position(x: bush.x + them.dx * size, y: bush.y + them.dy * size)
                    .zIndex(them.inFront ? 2 : 0)

                    // You (behind the bush, peeking)
                    BrainPoseView(appearance: appearance, mood: .idle, pose: me.pose, showsHalo: false)
                        .frame(width: size, height: size)
                        .rotationEffect(.degrees(me.tilt))
                        .position(x: bush.x + me.dx * size, y: bush.y + me.dy * size)
                        .zIndex(me.inFront ? 2 : 0)

                    Canvas { context, canvasSize in
                        BushDrawing.draw(context, size: canvasSize, rustle: rustle(time: t, me: me, them: them))
                    }
                    .frame(width: size * 1.6, height: size * 1.05)
                    .position(x: bush.x, y: bush.y + size * 0.18)
                    .zIndex(1)

                    if foundAt != nil {
                        Text("!")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.pinkDeep)
                            .position(x: bush.x + me.dx * size, y: bush.y + me.dy * size - size * 0.62)
                            .transition(.scale.combined(with: .opacity))
                            .zIndex(3)
                    }
                }
            }
        }
        .onChange(of: found, initial: true) { _, isFound in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { foundAt = isFound ? .now : nil }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(found ? "Found a brain" : "Your brain is looking for nearby brains")
    }

    private struct Peek {
        var dx: CGFloat
        var dy: CGFloat
        var tilt: Double
        var pose: FacePose
        var inFront = false
    }

    /// Your brain loops: peek left → duck → pop over the top looking around → back.
    private func myPeek(time t: Double, now: Date) -> Peek {
        let searching = searchPeek(time: t)
        guard let foundAt else { return searching }
        // Found: jump out from behind the bush, surprised and happy.
        let p = ease(min(now.timeIntervalSince(foundAt) / 0.5, 1))
        var pose = FacePose()
        pose.smile = 0.9
        pose.eyeWide = 0.6
        pose.browUp = 0.5
        pose.gazeX = 0.8
        pose.jawOpen = 0.25
        return Peek(dx: searching.dx + (-0.62 - searching.dx) * p,
                    dy: searching.dy + (-0.02 - searching.dy) * p,
                    tilt: searching.tilt + (6 - searching.tilt) * p,
                    pose: FacePose.mix(searching.pose, pose, Float(p)),
                    inFront: p > 0.5)
    }

    private func searchPeek(time t: Double) -> Peek {
        var pose = FacePose()
        pose.smile = 0.35
        let cycle = 6.4
        let c = t.truncatingRemainder(dividingBy: cycle)
        let blink = t.truncatingRemainder(dividingBy: 3.1) < 0.13
        if blink { pose.leftEyeOpen = 0.1; pose.rightEyeOpen = 0.1 }
        switch c {
        case ..<2.2: // peek from the left side, looking right
            let p = ease(min(c / 0.5, 1)) * (c > 1.8 ? ease(max(0, (2.2 - c) / 0.4)) : 1)
            pose.gazeX = 1
            pose.headYaw = 0.25
            pose.rightBrowRaise = 0.6 * Float(p)
            return Peek(dx: -0.38 - 0.22 * p, dy: 0.06, tilt: 10 * p, pose: pose)
        case ..<3.0: // duck
            return Peek(dx: -0.25, dy: 0.32, tilt: 0, pose: pose)
        default: // pop over the top, looking left and right
            let local = c - 3.0
            let up = ease(min(local / 0.5, 1)) * (local > 3.0 ? ease(max(0, (3.4 - local) / 0.4)) : 1)
            pose.gazeX = Float(sin(local * 2.4))
            pose.headYaw = Float(sin(local * 2.4)) * 0.2
            pose.eyeWide = 0.3
            return Peek(dx: -0.12, dy: 0.32 - 0.42 * up, tilt: sin(local * 2.4) * 4, pose: pose)
        }
    }

    /// The unknown brain peeks from the right, out of sync with yours (they keep missing each other).
    private func theirPeek(time t: Double, now: Date) -> Peek {
        if let foundAt {
            let p = ease(min(now.timeIntervalSince(foundAt) / 0.6, 1))
            return Peek(dx: 0.3 + 0.32 * p, dy: 0.22 - 0.22 * p, tilt: -6 * p, pose: FacePose(), inFront: p > 0.5)
        }
        let c = (t + 2.6).truncatingRemainder(dividingBy: 6.4)
        if c < 2.0 {
            let p = ease(min(c / 0.5, 1)) * (c > 1.6 ? ease(max(0, (2.0 - c) / 0.4)) : 1)
            return Peek(dx: 0.36 + 0.2 * p, dy: 0.1, tilt: -9 * p, pose: FacePose())
        }
        return Peek(dx: 0.25, dy: 0.34, tilt: 0, pose: FacePose())
    }

    private func friendPose(time t: Double) -> FacePose {
        var pose = FacePose()
        pose.smile = 0.9
        pose.squint = 0.6
        pose.gazeX = -0.8
        pose.headRoll = Float(sin(t * 3)) * 0.08
        return pose
    }

    private func rustle(time t: Double, me: Peek, them: Peek) -> Double {
        // The bush shakes while someone moves behind it.
        let moving = (me.dy > 0.25 ? 1.0 : 0.25) + (them.dy > 0.25 ? 0.6 : 0)
        return sin(t * 17) * 0.5 * moving
    }

    private func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
}

enum BushDrawing {
    /// (x, y, radius) as fractions of the canvas width/height; top puffs sway more than the ones on the ground.
    static let puffs: [(CGFloat, CGFloat, CGFloat, UInt32)] = [
        (0.13, 0.74, 0.17, 0x6CBF9E), (0.87, 0.74, 0.17, 0x6CBF9E),
        (0.20, 0.60, 0.24, 0x6CBF9E), (0.80, 0.60, 0.24, 0x6CBF9E),
        (0.35, 0.42, 0.25, 0x7FCFA9), (0.65, 0.40, 0.26, 0x7FCFA9),
        (0.50, 0.28, 0.25, 0x8FD8B5),
        (0.31, 0.70, 0.23, 0x8FD8B5), (0.69, 0.70, 0.23, 0x8FD8B5),
        (0.50, 0.64, 0.28, 0x7FCFA9)
    ]

    static func draw(_ context: GraphicsContext, size: CGSize, rustle: Double) {
        let w = size.width, h = size.height
        // A solid base first, so swaying puffs never open gaps.
        let base = Path(roundedRect: CGRect(x: w * 0.07, y: h * 0.45, width: w * 0.86, height: h * 0.47),
                        cornerRadius: h * 0.22)
        context.fill(base, with: .color(Color(hex: 0x6CBF9E)))
        for (index, puff) in puffs.enumerated() {
            let sway = (1 - puff.1) * 1.6
            let wobble = CGFloat(rustle) * (index.isMultiple(of: 2) ? 1 : -1) * 2.2 * sway
            let r = puff.2 * w * 0.5
            let rect = CGRect(x: puff.0 * w - r + wobble, y: puff.1 * h - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: rect), with: .color(Color(hex: puff.3)))
        }
        // Highlights and a few berries.
        for (x, y) in [(0.38, 0.30), (0.58, 0.24), (0.72, 0.48)] {
            context.fill(Path(ellipseIn: CGRect(x: x * w, y: y * h, width: w * 0.07, height: w * 0.045)),
                         with: .color(.white.opacity(0.35)))
        }
        for (x, y) in [(0.30, 0.56), (0.62, 0.62), (0.47, 0.46), (0.78, 0.66), (0.18, 0.72)] {
            context.fill(Path(ellipseIn: CGRect(x: x * w, y: y * h, width: 7, height: 7)), with: .color(Theme.blush))
        }
    }
}

// MARK: - 2. Portal

/// Air vortex. `intensity` 0…1 makes it spin faster, glow brighter, grow and shake.
struct PortalView: View {
    var intensity: Double
    var time: Double

    var body: some View {
        Canvas { context, size in
            PortalDrawing.draw(context, size: size, intensity: intensity, time: time)
        }
        .allowsHitTesting(false)
    }
}

enum PortalDrawing {
    static func draw(_ context: GraphicsContext, size: CGSize, intensity i: Double, time t: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 * (0.78 + 0.22 * i)
        let spin = t * (1.4 + 5 * i)

        // Glow
        let glow = Path(ellipseIn: CGRect(x: center.x - radius * 1.25, y: center.y - radius * 1.25 * 0.62,
                                          width: radius * 2.5, height: radius * 2.5 * 0.62))
        context.fill(glow, with: .radialGradient(
            Gradient(colors: [Theme.lavender.opacity(0.35 + 0.4 * i), Theme.Tint.sky.opacity(0.0)]),
            center: center, startRadius: 0, endRadius: radius * 1.25))

        // Tunnel rings in perspective (an ellipse squashed vertically), shrinking toward the core.
        var tunnel = context
        tunnel.translateBy(x: center.x, y: center.y)
        tunnel.scaleBy(x: 1, y: 0.58)
        for ring in 0..<7 {
            let f = Double(ring) / 7
            // Rings flow inward over time (an endless tunnel).
            let phase = (f + t * (0.25 + 0.9 * i)).truncatingRemainder(dividingBy: 1)
            let r = radius * (1 - phase * 0.85)
            let alpha = 0.15 + 0.5 * (1 - phase) * (0.5 + 0.5 * i)
            tunnel.stroke(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)),
                          with: .color(.white.opacity(alpha)), lineWidth: 2 + 3 * (1 - phase))
        }

        // Spiral arms
        for arm in 0..<4 {
            var path = Path()
            let start = Double(arm) / 4 * 2 * .pi + spin
            for step in 0...28 {
                let s = Double(step) / 28
                let r = radius * (1 - s * 0.88)
                let angle = start + s * 4.2
                let point = CGPoint(x: r * cos(angle), y: r * sin(angle))
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            let color = arm.isMultiple(of: 2) ? Theme.lavender : Theme.Deep.sky
            tunnel.stroke(path, with: .color(color.opacity(0.55 + 0.35 * i)),
                          style: StrokeStyle(lineWidth: 4 + 3 * i, lineCap: .round))
        }

        // Particles sucked inward
        for index in 0..<26 {
            let seed = Double(index) * 0.618
            let life = (seed + t * (0.35 + 1.2 * i)).truncatingRemainder(dividingBy: 1)
            let r = radius * 1.5 * (1 - life)
            let angle = seed * 2 * .pi * 3 + life * 5 + spin * 0.3
            let p = CGPoint(x: r * cos(angle), y: r * sin(angle))
            let dot = 2 + 3 * (1 - life)
            tunnel.fill(Path(ellipseIn: CGRect(x: p.x - dot, y: p.y - dot, width: dot * 2, height: dot * 2)),
                        with: .color(.white.opacity(0.4 + 0.5 * life)))
        }

        // Core
        let core = radius * (0.2 + 0.08 * i + 0.02 * sin(t * 9))
        tunnel.fill(Path(ellipseIn: CGRect(x: -core, y: -core, width: core * 2, height: core * 2)),
                    with: .radialGradient(Gradient(colors: [Theme.ink.opacity(0.85), Theme.lavender.opacity(0.6)]),
                                          center: .zero, startRadius: 0, endRadius: core))
    }
}

/// Wind lines flowing from the brain up into the portal.
struct WindStreaks: View {
    var from: CGPoint
    var to: CGPoint
    var intensity: Double
    var time: Double

    var body: some View {
        Canvas { context, _ in
            guard intensity > 0.05 else { return }
            for index in 0..<9 {
                let lane = (Double(index) - 4) / 4
                let progress = (Double(index) * 0.37 + time * (0.6 + 1.8 * intensity)).truncatingRemainder(dividingBy: 1)
                let spread = 70.0 * (1 - progress)
                let x = from.x + (to.x - from.x) * progress + lane * spread
                let y = from.y + (to.y - from.y) * progress
                let length = 18 + 30 * intensity
                var line = Path()
                line.move(to: CGPoint(x: x, y: y))
                line.addLine(to: CGPoint(x: x - lane * 6, y: y + length))
                context.stroke(line, with: .color(Theme.lavender.opacity(intensity * 0.6 * (1 - progress))),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }
}
