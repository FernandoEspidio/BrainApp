import SwiftUI

/// Shown once when a ring reaches 100%: the ring fills and glows, confetti falls, a success haptic plays.
/// Tap anywhere (or wait) to dismiss; the completion is then recorded so it won't repeat.
struct CelebrationOverlay: View {
    let ring: RingProgress
    var onDone: () -> Void

    @State private var appeared = false
    @State private var start = Date.now

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { onDone() }

            ConfettiView(start: start, colors: [ring.area.ringColor, Theme.pink, Theme.sun, Theme.lavender, Theme.Deep.mint])
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 16) {
                ZStack {
                    ActivityRing(fraction: 1, color: ring.area.ringColor, lineWidth: 22)
                    Image(systemName: ring.area.symbol)
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(ring.area.ringColor)
                        .symbolEffect(.bounce, value: appeared)
                }
                .frame(width: 170, height: 170)

                Text("\(ring.area.name) ring closed")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.ink)
                Text(ring.valueText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)

                Button("Nice!") { onDone() }
                    .buttonStyle(InkButtonStyle())
                    .frame(width: 170)
            }
            .padding(28)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .shadow(color: ring.area.ringColor.opacity(0.35), radius: 30)
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)
        }
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear {
            start = .now
            withAnimation(.spring(duration: 0.6, bounce: 0.35)) { appeared = true }
        }
        .task {
            do {
                try await Task.sleep(for: .seconds(5))
                onDone()
            } catch {}
        }
    }
}

/// Lightweight confetti drawn in a Canvas (no assets). Pieces fall with gravity, sway and spin.
struct ConfettiView: View {
    let start: Date
    let colors: [Color]

    struct Piece {
        let x: Double, delay: Double, speed: Double, sway: Double, spin: Double, size: Double
        let colorIndex: Int, round: Bool

        static func random() -> Piece {
            Piece(x: .random(in: 0...1), delay: .random(in: 0...0.5), speed: .random(in: 0.25...0.6),
                  sway: .random(in: 0...6.28), spin: .random(in: 2...9), size: .random(in: 6...12),
                  colorIndex: .random(in: 0..<100), round: Bool.random())
        }
    }

    @State private var pieces: [Piece] = (0..<100).map { _ in Piece.random() }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                guard t < 6, !colors.isEmpty else { return }
                for piece in pieces {
                    let local = t - piece.delay
                    guard local > 0 else { continue }
                    let y = -20 + local * piece.speed * size.height + 0.5 * 260 * local * local
                    guard y < size.height + 30 else { continue }
                    let x = piece.x * size.width + sin(local * 3 + piece.sway) * 24
                    var ctx = context
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: .radians(local * piece.spin))
                    let rect = CGRect(x: -piece.size / 2, y: -piece.size / 4, width: piece.size, height: piece.size / 2)
                    let path = piece.round ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.5)
                    ctx.fill(path, with: .color(colors[piece.colorIndex % colors.count]))
                }
            }
        }
    }
}
