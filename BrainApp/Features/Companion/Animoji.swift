import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// A brain animoji is a short list of facial poses played at a fixed rate.
/// It comes from your face (Mirror me → Record) or from a preset expression.
enum AnimojiClip {
    static let fps: Double = 15
    static let maxFrames = 60          // 4 seconds
    static let recordSeconds: Double = 3

    /// A preset expression as a clip (reuses the brain's tap reactions).
    static func frames(for reaction: BrainReaction) -> [FacePose] {
        var base = FacePose()
        base.smile = 0.3
        let count = max(2, Int(reaction.duration * fps))
        return (0..<count).map { index in
            reaction.apply(to: base, progress: Double(index) / Double(count - 1))
        }
    }

    static func frame(in clip: [FacePose], at time: TimeInterval) -> FacePose? {
        guard !clip.isEmpty else { return nil }
        let index = Int((time * fps).rounded(.down)) % clip.count
        return clip[max(0, index)]
    }
}

extension BrainReaction {
    /// Face used on the expression picker.
    var emoji: String {
        switch self {
        case .giggle: return "😆"
        case .wink: return "😉"
        case .surprised: return "😮"
        case .proud: return "😎"
        case .cheeky: return "😛"
        case .puff: return "🐡"
        case .yawn: return "🥱"
        case .nod: return "🙂"
        case .wiggle: return "🤪"
        }
    }
}

extension FacePose {
    /// Received poses are untrusted: keep every value in its valid range.
    func clamped() -> FacePose {
        func unit(_ v: Float) -> Float { v.isFinite ? min(max(v, 0), 1) : 0 }
        func angle(_ v: Float) -> Float { v.isFinite ? min(max(v, -1), 1) : 0 }
        return FacePose(leftEyeOpen: unit(leftEyeOpen), rightEyeOpen: unit(rightEyeOpen), jawOpen: unit(jawOpen),
                        smile: unit(smile), browUp: unit(browUp), browDown: unit(browDown), cheekPuff: unit(cheekPuff),
                        tongueOut: unit(tongueOut), pucker: unit(pucker), headRoll: angle(headRoll),
                        headYaw: angle(headYaw), headPitch: angle(headPitch))
    }
}

/// The brain drawn in one fixed pose (no timers): used for exported images and GIF frames.
struct BrainPoseView: View {
    var appearance: CompanionAppearance
    var mood: BrainMood = .idle
    var pose: FacePose
    var showsHalo = true

    var body: some View {
        Canvas { context, size in
            if showsHalo { BrainDrawing.drawHalo(context, size: size, mood: mood, stage: nil) }
            BrainDrawing.drawBuddy(context, size: size, pose: pose, mood: mood, armsMood: mood,
                                   variant: Theme.brainVariant(appearance.colorIndex), accessory: appearance.accessory,
                                   time: nil, bob: 0)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Plays a clip on loop; with no clip, the brain just idles (blinks, breathes).
struct AnimojiPlayer: View {
    var appearance: CompanionAppearance
    var mood: BrainMood = .idle
    var clip: [FacePose]
    var animated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let base = BrainExpressions.base(mood: mood, overallProgress: 0.4, anyRingClosed: false)
        if animated && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / AnimojiClip.fps)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                BrainPoseView(appearance: appearance, mood: mood,
                              pose: AnimojiClip.frame(in: clip, at: t) ?? BrainExpressions.idle(base, time: t, sleepy: mood == .resting))
            }
        } else {
            BrainPoseView(appearance: appearance, mood: mood, pose: clip.first ?? base)
        }
    }
}

/// Turns a clip into an animated GIF that any app can show (Messages, WhatsApp…). Made on device.
@MainActor
enum AnimojiExporter {
    static func gif(clip: [FacePose], appearance: CompanionAppearance, mood: BrainMood, side: CGFloat = 300) -> URL? {
        let frames = clip.isEmpty ? [FacePose()] : clip
        let name = appearance.name.filter { $0.isLetter || $0.isNumber }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name.isEmpty ? "Brain" : name)-animoji.gif")
        try? FileManager.default.removeItem(at: url)

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString,
                                                                frames.count, nil) else { return nil }
        let fileProperties = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        let frameProperties = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: 1.0 / AnimojiClip.fps]]

        for pose in frames {
            let content = BrainPoseView(appearance: appearance, mood: mood, pose: pose)
                .frame(width: side, height: side)
                .padding(12)
                .background(Theme.cream)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            if let image = renderer.cgImage {
                CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
            }
        }
        return CGImageDestinationFinalize(destination) ? url : nil
    }
}
