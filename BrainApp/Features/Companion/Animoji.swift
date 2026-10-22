import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// Ready-made moves (no camera needed) built from the brain's tap reactions.
enum AnimojiClip {
    static func clip(for reaction: BrainReaction) -> BrainClip {
        var base = FacePose()
        base.smile = 0.3
        let fps = BrainClip.recordFPS
        let count = max(2, Int(reaction.duration * fps))
        let frames = (0..<count).map { index in
            reaction.apply(to: base, progress: Double(index) / Double(count - 1))
        }
        return BrainClip(fps: fps, frames: frames)
    }
}

extension BrainReaction {
    /// Face used on the move picker.
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
        case .suspicious: return "🤨"
        case .kiss: return "😘"
        case .lookAround: return "👀"
        }
    }

    var label: String {
        switch self {
        case .lookAround: return "Look around"
        default: return rawValue.capitalized
        }
    }
}

/// The brain drawn in one fixed pose (no timers): thumbnails, exported images and GIF frames.
struct BrainPoseView: View {
    var appearance: CompanionAppearance
    var mood: BrainMood = .idle
    var pose: FacePose
    var showsHalo = true

    var body: some View {
        Canvas { context, size in
            if showsHalo { BrainDrawing.drawHalo(context, size: size, mood: mood, stage: nil) }
            BrainDrawing.drawBuddy(context, size: size, pose: pose, mood: mood, armsMood: mood,
                                   variant: Theme.brainVariant(appearance.colorIndex), outfit: appearance.outfit,
                                   time: nil, bob: 0)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Plays a move. `loops`: repeat with a short rest between plays; otherwise play once from `start`
/// and settle into the idle face. With no clip, the brain just idles (blinks, breathes).
struct AnimojiPlayer: View {
    var appearance: CompanionAppearance
    var mood: BrainMood = .idle
    var clip: BrainClip
    var animated = true
    var loops = true
    var showsHalo = true
    /// Changing it restarts the move (used for "Replay").
    var start: Date = .distantPast

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let base = BrainExpressions.base(mood: mood, overallProgress: 0.4, anyRingClosed: false)
        if animated && !reduceMotion {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let idle = BrainExpressions.idle(base, time: t, sleepy: mood == .resting)
                BrainPoseView(appearance: appearance, mood: mood, pose: pose(at: timeline.date, idle: idle),
                              showsHalo: showsHalo)
            }
        } else {
            BrainPoseView(appearance: appearance, mood: mood, pose: clip.frames.first ?? base, showsHalo: showsHalo)
        }
    }

    private func pose(at date: Date, idle: FacePose) -> FacePose {
        clip.playback(at: date, start: loops ? nil : start, rest: idle)
    }
}

/// Turns a move into an animated GIF that any app can show (Messages, WhatsApp…). Made on device.
@MainActor
enum AnimojiExporter {
    static func gif(clip: BrainClip, appearance: CompanionAppearance, mood: BrainMood, side: CGFloat = 300) -> URL? {
        // 15 fps is plenty for a GIF and keeps the file small.
        let fps = 15.0
        let count = max(1, Int(clip.duration * fps))
        let frames = clip.isEmpty ? [FacePose()] : (0..<count).compactMap { clip.pose(at: Double($0) / fps) }
        let name = appearance.name.filter { $0.isLetter || $0.isNumber }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name.isEmpty ? "Brain" : name)-move.gif")
        try? FileManager.default.removeItem(at: url)

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString,
                                                                frames.count, nil) else { return nil }
        let fileProperties = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        let frameProperties = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: 1.0 / fps]]

        for pose in frames {
            // One frame at a time: each rendered image is released before the next one is made.
            autoreleasepool {
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
        }
        return CGImageDestinationFinalize(destination) ? url : nil
    }
}
