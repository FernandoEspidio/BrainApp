import SwiftUI
import UIKit

/// Record your "move": 3 seconds of expressions that friends see when they open your brain.
/// Flow (camera-style, per HIG): Ready → 3-2-1 → Recording (ring fills) → Review (loops) → Retake / Use this move.
/// Without a camera (not supported or not allowed) you pick a ready-made move instead.
/// Only face shapes are saved (21 numbers per frame), never images.
struct RecordMoveSheet: View {
    let tracker: FaceTracker
    var onSave: (BrainClip) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private enum Stage: Equatable {
        case ready
        case countdown(Int)
        case recording
        case review(BrainClip, fromCamera: Bool)
    }

    @State private var stage: Stage = .ready
    @State private var progress: Double = 0
    @State private var access = FaceTracker.access
    @State private var recordTask: Task<Void, Never>?
    @State private var tick = 0

    private var canUseCamera: Bool { access == .allowed || access == .notAsked }

    var body: some View {
        let appearance = model.repository.snapshot.companion

        NavigationStack {
            VStack(spacing: 18) {
                Spacer(minLength: 8)
                stageView(appearance: appearance)
                    .frame(width: 260, height: 260)
                captions
                Spacer(minLength: 8)
                controls
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("Your move")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sensoryFeedback(.selection, trigger: tick)
        }
        .interactiveDismissDisabled(stage == .recording)
        .onAppear {
            access = FaceTracker.access
            if canUseCamera { tracker.start() }
        }
        .onDisappear {
            recordTask?.cancel()
            tracker.stop()
        }
    }

    // MARK: - Brain

    @ViewBuilder
    private func stageView(appearance: CompanionAppearance) -> some View {
        switch stage {
        case .review(let clip, _):
            AnimojiPlayer(appearance: appearance, clip: clip)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
        default:
            ZStack {
                BrainBuddyView(
                    appearance: appearance,
                    mood: .idle,
                    basePose: FacePose(),
                    livePose: nil,
                    liveSource: tracker.isTracking ? tracker : nil,
                    reaction: nil,
                    stage: nil,
                    poke: 0,
                    onTap: {}
                )
                if stage == .recording {
                    StaticRing(fraction: progress, color: .red, lineWidth: 6)
                        .padding(-6)
                        .transition(.opacity)
                }
                if case .countdown(let n) = stage {
                    Text("\(n)")
                        .font(.system(size: 96, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: Theme.ink.opacity(0.35), radius: 10)
                        .id(n)
                        .transition(.scale(scale: 1.6).combined(with: .opacity))
                }
            }
        }
    }

    private var captions: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .animation(.snappy, value: stage)
    }

    private var title: String {
        switch stage {
        case .ready: return canUseCamera ? "Make a face!" : "Pick a move"
        case .countdown: return "Get ready…"
        case .recording: return "Recording"
        case .review: return "Looking good!"
        }
    }

    private var subtitle: String {
        switch stage {
        case .ready:
            if !canUseCamera { return "The camera is off, so choose one of these. Friends see it when they open your brain." }
            return tracker.isTracking
                ? "Wink, smile, raise a brow… We keep 3 seconds of face shapes, never video."
                : "Look at the screen so your brain can find you."
        case .countdown: return "Your brain copies you for 3 seconds."
        case .recording: return "Keep going!"
        case .review(_, let fromCamera):
            return fromCamera ? "This is what friends will see." : "A ready-made move. You can record your own anytime."
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        switch stage {
        case .ready:
            VStack(spacing: 20) {
                if canUseCamera {
                    ShutterButton(isEnabled: tracker.isTracking) { startCountdown() }
                } else if access == .denied {
                    Button("Allow camera in Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(SoftButtonStyle())
                }
                presets
            }
        case .countdown, .recording:
            Button("Stop", role: .cancel) { cancelRecording() }
                .buttonStyle(SoftLargeButtonStyle())
                .frame(maxWidth: 200)
        case .review(let clip, let fromCamera):
            HStack(spacing: 12) {
                Button(fromCamera ? "Retake" : "Choose another") {
                    withAnimation(.snappy) { stage = .ready }
                    if canUseCamera { tracker.start() }
                }
                .buttonStyle(SoftLargeButtonStyle())
                Button("Use this move") {
                    onSave(clip)
                    dismiss()
                }
                .buttonStyle(InkButtonStyle())
            }
        }
    }

    private var presets: some View {
        VStack(spacing: 8) {
            if canUseCamera {
                Text("Or pick a ready-made one")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(BrainReaction.allCases, id: \.self) { kind in
                        Button {
                            tick += 1
                            tracker.stop()
                            withAnimation(.snappy) { stage = .review(AnimojiClip.clip(for: kind), fromCamera: false) }
                        } label: {
                            Text(kind.emoji)
                                .font(.system(size: 26))
                                .frame(width: 52, height: 52)
                                .background(.white, in: Circle())
                                .shadow(color: Theme.ink.opacity(0.06), radius: 4, y: 2)
                        }
                        .buttonStyle(PressScaleButtonStyle())
                        .accessibilityLabel(kind.label)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Recording

    private func startCountdown() {
        recordTask?.cancel()
        recordTask = Task {
            for n in [3, 2, 1] {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { stage = .countdown(n) }
                tick += 1
                try? await Task.sleep(for: .seconds(0.8))
                if Task.isCancelled { return }
            }
            await record()
        }
    }

    private func record() async {
        withAnimation(.snappy) { stage = .recording }
        progress = 0
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let total = Int(BrainClip.recordSeconds * BrainClip.recordFPS)
        let interval = Duration.seconds(1.0 / BrainClip.recordFPS)
        let clock = ContinuousClock()
        var next = clock.now
        var frames: [FacePose] = []
        frames.reserveCapacity(total)
        for index in 0..<total {
            frames.append(tracker.livePose)
            progress = Double(index + 1) / Double(total)
            // Sleep until the next tick on a fixed schedule, so the clip's timing doesn't drift.
            next += interval
            try? await Task.sleep(until: next, clock: clock)
            if Task.isCancelled { return }
        }
        tracker.stop()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            stage = .review(BrainClip(fps: BrainClip.recordFPS, frames: frames), fromCamera: true)
        }
    }

    private func cancelRecording() {
        recordTask?.cancel()
        withAnimation(.snappy) { stage = .ready }
    }
}

/// Camera-style record button.
struct ShutterButton: View {
    var isEnabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(Theme.ink.opacity(isEnabled ? 0.9 : 0.25), lineWidth: 5)
                Circle().fill(isEnabled ? Color.red : Color.red.opacity(0.3)).padding(9)
            }
            .frame(width: 76, height: 76)
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel("Record move")
        .accessibilityHint("Starts a 3 second recording after a countdown")
    }
}
