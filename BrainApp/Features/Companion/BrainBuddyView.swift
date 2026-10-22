import SwiftUI

/// A short facial performance played when the brain is tapped.
enum BrainReaction: String, CaseIterable, Sendable {
    case giggle, wink, surprised, proud, cheeky, puff, yawn, nod, wiggle, suspicious, kiss, lookAround

    var duration: Double {
        switch self {
        case .yawn, .lookAround: return 2.0
        case .suspicious: return 1.8
        default: return 1.4
        }
    }

    /// Arms switch pose for the bigger reactions.
    var armsMood: BrainMood? {
        switch self {
        case .proud, .giggle: return .celebrating
        case .surprised: return .moving
        default: return nil
        }
    }

    /// Layers the reaction on top of the current pose. `progress` goes 0 → 1.
    func apply(to pose: FacePose, progress: Double) -> FacePose {
        let p = min(max(progress, 0), 1)
        let e = Float(sin(Double.pi * p))                     // envelope 0 → 1 → 0
        let wave: (Double) -> Float = { frequency in Float(sin(p * Double.pi * frequency)) }
        var q = pose
        switch self {
        case .giggle:
            q.smile = max(q.smile, e)
            q.squint = max(q.squint, e)
            q.jawOpen = max(q.jawOpen, 0.35 * e * abs(wave(10)))
            q.headRoll += 0.18 * e * wave(6)
        case .wink:
            q.rightEyeOpen *= 1 - e
            q.smile = max(q.smile, 0.7 * e)
            q.headRoll += 0.15 * e
        case .surprised:
            q.browUp = max(q.browUp, e)
            q.eyeWide = max(q.eyeWide, e)
            q.jawOpen = max(q.jawOpen, 0.6 * e)
            q.leftEyeOpen = max(q.leftEyeOpen, e)
            q.rightEyeOpen = max(q.rightEyeOpen, e)
            q.headPitch -= 0.1 * e
        case .proud:
            q.smile = max(q.smile, e)
            q.browUp = max(q.browUp, 0.5 * e)
            q.headPitch -= 0.18 * e
        case .cheeky:
            q.tongueOut = max(q.tongueOut, e)
            q.jawOpen = max(q.jawOpen, 0.3 * e)
            q.leftEyeOpen *= 1 - 0.8 * e
            q.smile = max(q.smile, 0.4 * e)
        case .puff:
            q.cheekPuff = max(q.cheekPuff, e)
            q.pucker = max(q.pucker, 0.4 * e)
            q.headYaw += 0.2 * e * wave(4)
        case .yawn:
            q.jawOpen = max(q.jawOpen, 0.95 * e)
            q.leftEyeOpen *= 1 - 0.9 * e
            q.rightEyeOpen *= 1 - 0.9 * e
            q.browUp = max(q.browUp, 0.4 * e)
        case .nod:
            q.headPitch += 0.22 * e * wave(4)
            q.smile = max(q.smile, 0.6 * e)
        case .wiggle:
            q.headRoll += 0.3 * e * wave(8)
            q.smile = max(q.smile, 0.5 * e)
        case .suspicious:
            q.rightBrowRaise = max(q.rightBrowRaise, e)
            q.leftEyeOpen *= 1 - 0.45 * e
            q.mouthShift += 0.8 * e
            q.smile = max(q.smile, 0.25 * e)
            q.gazeX += 0.9 * e
            q.headRoll -= 0.1 * e
        case .kiss:
            q.pucker = max(q.pucker, e)
            q.smile = 0
            q.rightEyeOpen *= 1 - e
            q.headRoll += 0.12 * e
        case .lookAround:
            q.gazeX += 0.95 * e * wave(2)
            q.headYaw += 0.25 * e * wave(2)
            q.eyeWide = max(q.eyeWide, 0.4 * e)
        }
        return q
    }
}

struct ActiveReaction: Equatable {
    let kind: BrainReaction
    let start: Date
}

/// Resting expression + idle life (blinks, breathing, glancing around).
enum BrainExpressions {
    /// The face reflects the current state: sleepy when resting, focused when learning,
    /// and happier as the rings fill up. It never looks sad.
    static func base(mood: BrainMood, overallProgress: Double, anyRingClosed: Bool) -> FacePose {
        var p = FacePose()
        switch mood {
        case .resting: p.leftEyeOpen = 0.2; p.rightEyeOpen = 0.2; p.smile = 0.2
        case .celebrating: p.smile = 1; p.browUp = 0.4
        case .focused, .learning: p.browDown = 0.25; p.smile = 0.15
        case .moving: p.smile = 0.6; p.jawOpen = 0.12
        case .social: p.smile = 0.8
        case .idle: p.smile = 0.25
        }
        p.smile = max(p.smile, Float(min(max(overallProgress, 0), 1)) * 0.8)
        if anyRingClosed && mood != .resting {
            p.smile = max(p.smile, 0.7)
            p.browUp = max(p.browUp, 0.2)
        }
        return p
    }

    static func idle(_ base: FacePose, time t: Double, sleepy: Bool) -> FacePose {
        var p = base
        let cycle = t.truncatingRemainder(dividingBy: 4.2)
        if !sleepy && cycle < 0.16 {
            let closed = Float(1 - abs(cycle - 0.08) / 0.08)
            p.leftEyeOpen = min(p.leftEyeOpen, 1 - closed)
            p.rightEyeOpen = min(p.rightEyeOpen, 1 - closed)
        }
        p.headRoll += Float(sin(t * 0.9)) * 0.05
        p.headYaw += Float(sin(t * 0.37)) * (sleepy ? 0.03 : 0.12)
        p.headPitch += Float(sin(t * 1.6)) * 0.03
        return p
    }
}

/// The brain animoji as the living centerpiece of Today.
/// - Idle: breathes, blinks, glances around; its face shows the current state.
/// - Tap: plays a reaction (the parent decides which, based on real progress).
/// - Drag: it looks where your finger goes, then springs back.
/// - `livePose`: when set (camera mirror mode), your face drives it.
struct BrainBuddyView: View {
    var appearance: CompanionAppearance
    var mood: BrainMood
    var basePose: FacePose
    var livePose: FacePose?
    /// Live camera mirror, read at draw time so the parent view doesn't re-render on every face update.
    var liveSource: FaceTracker? = nil
    /// A recorded/preset move to loop instead of the idle face.
    var clip: BrainClip? = nil
    /// When set, `clip` plays once from this moment instead of looping.
    var clipStart: Date? = nil
    var reaction: ActiveReaction?
    var stage: Int?
    var poke: Int
    var onTap: () -> Void

    @State private var smoother = PoseSmoother()
    @State private var look: CGSize = .zero
    @State private var releasedLook: CGSize = .zero
    @State private var releaseDate: Date = .distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let variant = Theme.brainVariant(appearance.colorIndex)
        let paused = reduceMotion && livePose == nil && liveSource == nil && reaction == nil && (clip ?? .empty).isEmpty

        ZStack {
            Canvas { context, size in
                BrainDrawing.drawHalo(context, size: size, mood: mood, stage: stage)
            }
            // Full display rate (60/120 Hz): the face is smoothed per frame, so it glides between camera updates.
            TimelineView(.animation(minimumInterval: liveSource == nil && livePose == nil ? 1.0 / 45.0 : nil, paused: paused)) { timeline in
                let now = timeline.date
                let t = now.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    let idle = reduceMotion ? basePose : BrainExpressions.idle(basePose, time: t, sleepy: mood == .resting)
                    let target = livePose ?? liveSource?.livePose ?? clipPose(at: now, idle: idle) ?? idle
                    var pose = smoother.next(toward: target, at: t, live: liveSource != nil || livePose != nil)
                    var arms = mood
                    if let reaction {
                        let progress = now.timeIntervalSince(reaction.start) / reaction.kind.duration
                        if progress >= 0 && progress <= 1 {
                            pose = reaction.kind.apply(to: pose, progress: progress)
                            arms = reaction.kind.armsMood ?? mood
                        }
                    }
                    // Follow the finger; after release, ease back to center over ~0.35 s.
                    let decay = max(0, 1 - now.timeIntervalSince(releaseDate) / 0.35)
                    let lookX = look == .zero ? releasedLook.width * decay : look.width
                    let lookY = look == .zero ? releasedLook.height * decay : look.height
                    pose.headYaw += Float(lookX) * 0.6
                    pose.headPitch += Float(lookY) * 0.45

                    let speed: Double = mood == .moving || mood == .celebrating ? 5 : 2.2
                    let bob = reduceMotion ? 0 : CGFloat(sin(t * speed) * 2)
                    BrainDrawing.drawBuddy(context, size: size, pose: pose, mood: mood, armsMood: arms,
                                           variant: variant, outfit: appearance.outfit,
                                           time: reduceMotion ? nil : t, bob: bob)
                }
            }
            .keyframeAnimator(initialValue: CGFloat(0), trigger: poke) { content, offset in
                content.offset(y: offset)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(-24, duration: 0.15)
                    SpringKeyframe(0, duration: 0.55, spring: .bouncy)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Circle())
        .onTapGesture { onTap() }
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    look = CGSize(width: max(-1, min(1, value.translation.width / 120)),
                                  height: max(-1, min(1, value.translation.height / 120)))
                }
                .onEnded { _ in
                    releasedLook = look
                    releaseDate = .now
                    look = .zero
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(appearance.name), \(mood.title)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(accessibilityTapHint)
    }

    var accessibilityTapHint = "Tap for a quick insight"

    private func clipPose(at date: Date, idle: FacePose) -> FacePose? {
        guard let clip, !clip.isEmpty else { return nil }
        return clip.playback(at: date, start: clipStart, rest: idle)
    }
}

/// Frame-rate-independent smoothing of the drawn face. Camera poses arrive at their own pace;
/// easing toward them every display frame removes the "steps" between updates.
/// A reference type on purpose: it's updated while drawing, without re-rendering the view.
final class PoseSmoother {
    private var pose: FacePose?
    private var lastTime: Double = 0

    func next(toward target: FacePose, at time: Double, live: Bool) -> FacePose {
        guard live, let current = pose else {
            pose = target
            lastTime = time
            return target
        }
        let dt = min(max(time - lastTime, 0), 0.1)
        lastTime = time
        // ~70 ms time constant: responsive, but no jitter.
        let amount = Float(1 - exp(-dt / 0.07))
        let next = current.blended(toward: target, amount: amount)
        pose = next
        return next
    }
}

extension BrainDrawing {
    /// Puppet brain (expressive face) + the current mood's arms, props and accessory.
    static func drawBuddy(_ context: GraphicsContext, size: CGSize, pose: FacePose, mood: BrainMood, armsMood: BrainMood,
                          variant: Theme.BrainVariant, outfit: Outfit,
                          time: TimeInterval?, bob: CGFloat) {
        let base = unitContext(context, size: size)
        let yaw = CGFloat(pose.headYaw)
        let pitch = CGFloat(pose.headPitch)

        if mood != .resting {
            base.fill(ellipse(100, 178, 38, 5), with: .color(ink.opacity(0.10)))
        }

        var root = base
        root.translateBy(x: 0, y: bob)
        if mood == .resting { drawBlanketBack(root) }

        var legs = root
        legs.translateBy(x: yaw * 12, y: 0)
        drawLegs(legs, mood: mood)

        var body = root
        body.translateBy(x: 100 + yaw * 30, y: 110 + pitch * 24)
        body.rotate(by: .radians(Double(pose.headRoll)))
        body.scaleBy(x: 1 + CGFloat(pose.cheekPuff) * 0.07, y: 1 + CGFloat(pose.jawOpen) * 0.05)
        body.translateBy(x: -100, y: -110)
        drawBody(body, variant: variant)

        var face = body
        face.translateBy(x: yaw * 14, y: pitch * 10)
        drawPuppetFace(face, pose: pose)

        drawArms(body, mood: armsMood, variant: variant)
        drawProps(body, mood: mood, time: time, wearsEyewear: outfit.eyewear != .none)
        drawOutfit(body: body, face: face, outfit: outfit, variant: variant, mood: mood)
        if mood == .resting { drawBlanketFront(root) }
    }
}
