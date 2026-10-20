import SwiftUI

/// A short facial performance played when the brain is tapped.
enum BrainReaction: String, CaseIterable, Sendable {
    case giggle, wink, surprised, proud, cheeky, puff, yawn, nod, wiggle

    var duration: Double { self == .yawn ? 2.0 : 1.4 }

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
            q.leftEyeOpen *= 1 - 0.85 * e
            q.rightEyeOpen *= 1 - 0.85 * e
            q.jawOpen = max(q.jawOpen, 0.35 * e * abs(wave(10)))
            q.headRoll += 0.18 * e * wave(6)
        case .wink:
            q.rightEyeOpen *= 1 - e
            q.smile = max(q.smile, 0.7 * e)
            q.headRoll += 0.15 * e
        case .surprised:
            q.browUp = max(q.browUp, e)
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
    /// A recorded/preset animoji to loop instead of the idle face.
    var clip: [FacePose]? = nil
    var reaction: ActiveReaction?
    var stage: Int?
    var poke: Int
    var onTap: () -> Void

    @State private var look: CGSize = .zero
    @State private var releasedLook: CGSize = .zero
    @State private var releaseDate: Date = .distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let variant = Theme.brainVariant(appearance.colorIndex)
        let paused = reduceMotion && livePose == nil && reaction == nil && (clip ?? []).isEmpty

        ZStack {
            Canvas { context, size in
                BrainDrawing.drawHalo(context, size: size, mood: mood, stage: stage)
            }
            TimelineView(.animation(minimumInterval: 1.0 / 45.0, paused: paused)) { timeline in
                let now = timeline.date
                let t = now.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    var pose = livePose
                        ?? AnimojiClip.frame(in: clip ?? [], at: t)
                        ?? (reduceMotion ? basePose : BrainExpressions.idle(basePose, time: t, sleepy: mood == .resting))
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
                                           variant: variant, accessory: appearance.accessory,
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
        .accessibilityHint("Tap for a quick insight")
    }
}

extension BrainDrawing {
    /// Puppet brain (expressive face) + the current mood's arms, props and accessory.
    static func drawBuddy(_ context: GraphicsContext, size: CGSize, pose: FacePose, mood: BrainMood, armsMood: BrainMood,
                          variant: Theme.BrainVariant, accessory: CompanionAppearance.Accessory,
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
        drawProps(body, mood: mood, time: time)
        drawAccessory(body, accessory: accessory, mood: mood)
        if mood == .resting { drawBlanketFront(root) }
    }
}
