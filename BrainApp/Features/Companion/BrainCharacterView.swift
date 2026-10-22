import SwiftUI

/// The cartoon brain companion, drawn with vector shapes in a 200 × 200 unit box.
/// Geometry was prototyped as SVG first, so the path strings below are copied as-is.
/// Each mood adds a pose and a prop (dumbbell, book, nightcap…). It represents what the
/// app understands about your day, never brain activity or a diagnosis.
struct BrainCharacterView: View {
    var mood: BrainMood = .idle
    var variant: Theme.BrainVariant = Theme.brainVariant(0)
    var outfit: Outfit = .none
    /// Shows the understanding stage as dots around the halo. nil = no dots.
    var stage: Int? = nil
    var showsHalo = true
    var animated = true
    /// Increment to make the brain do a little jump (tap reaction).
    var poke = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldAnimate: Bool { animated && !reduceMotion }

    var body: some View {
        ZStack {
            if showsHalo {
                Canvas { context, size in
                    BrainDrawing.drawHalo(context, size: size, mood: mood, stage: stage)
                }
            }
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !shouldAnimate)) { timeline in
                let time = shouldAnimate ? timeline.date.timeIntervalSinceReferenceDate : nil
                Canvas { context, size in
                    BrainDrawing.drawCharacter(context, size: size, mood: mood, variant: variant,
                                               outfit: outfit, time: time)
                }
            }
            .keyframeAnimator(initialValue: CGFloat(0), trigger: poke) { content, offset in
                content.offset(y: offset)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(-22, duration: 0.16)
                    SpringKeyframe(0, duration: 0.5, spring: .bouncy)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Brain buddy, \(mood.title)")
    }
}

// MARK: - Drawing

enum BrainDrawing {
    /// The unit box is drawn with a 10-unit margin so props can stick out a bit.
    static let box: CGFloat = 220
    static let margin: CGFloat = 10

    static let ink = Theme.ink
    static let white = Color.white

    static let bumps: [(CGFloat, CGFloat, CGFloat)] = [
        (64, 72, 26), (89, 58, 28), (115, 58, 28), (139, 73, 25),
        (47, 99, 23), (153, 99, 23), (70, 98, 30), (100, 94, 32), (130, 98, 30),
        (62, 121, 22), (88, 127, 24), (113, 127, 24), (139, 121, 22)
    ]

    static let folds = [
        "M100,38 C95,52 105,62 100,76",
        "M70,56 C77,63 70,71 78,77", "M130,56 C123,63 130,71 122,77",
        "M45,90 C54,92 56,100 51,106", "M155,90 C146,92 144,100 149,106",
        "M70,118 C77,113 84,117 86,124", "M130,118 C123,113 116,117 114,124"
    ]

    static let arms: [BrainMood: [String]] = [
        .idle: ["M27,112 C16,122 14,132 18,142", "M173,110 C186,104 190,92 186,80"],
        .moving: ["M25,104 C14,96 14,84 22,74", "M175,104 C186,96 186,84 178,74"],
        .learning: ["M30,116 C44,132 60,138 74,136", "M170,116 C156,132 140,138 126,136"],
        .focused: ["M27,112 C20,124 28,132 40,128", "M173,112 C182,118 178,126 168,128"],
        .social: ["M27,112 C16,122 14,132 18,142", "M173,112 C184,120 184,128 176,132"],
        .celebrating: ["M26,106 C14,96 10,84 14,72", "M174,106 C186,96 190,84 186,72"],
        .resting: []
    ]

    static let hands: [BrainMood: [CGPoint]] = [
        .idle: [CGPoint(x: 186, y: 77)],
        .celebrating: [CGPoint(x: 14, y: 69), CGPoint(x: 186, y: 69)]
    ]

    static func unitContext(_ context: GraphicsContext, size: CGSize) -> GraphicsContext {
        var ctx = context
        let scale = min(size.width, size.height) / box
        ctx.translateBy(x: (size.width - box * scale) / 2 + margin * scale,
                        y: (size.height - box * scale) / 2 + margin * scale)
        ctx.scaleBy(x: scale, y: scale)
        return ctx
    }

    // MARK: Halo and stage dots

    static func drawHalo(_ context: GraphicsContext, size: CGSize, mood: BrainMood, stage: Int?) {
        let ctx = unitContext(context, size: size)
        ctx.fill(Path(ellipseIn: CGRect(x: 4, y: 4, width: 192, height: 192)), with: .color(mood.halo))
        guard let stage else { return }
        // 8 dots around the halo; lit dots grow with understanding (stage 0–3 → 2, 4, 6, 8 dots).
        let lit = (min(max(stage, 0), 3) + 1) * 2
        for index in 0..<8 {
            let angle = -Double.pi / 2 + Double(index) * Double.pi / 4
            let center = CGPoint(x: 100 + 104 * cos(angle), y: 100 + 104 * sin(angle))
            let color = index < lit ? Theme.pink : (mood.isNight ? Color.white.opacity(0.25) : Theme.hairline)
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)), with: .color(color))
        }
    }

    // MARK: Character

    static func drawCharacter(_ context: GraphicsContext, size: CGSize, mood: BrainMood,
                              variant: Theme.BrainVariant, outfit: Outfit,
                              time: TimeInterval?) {
        var ctx = unitContext(context, size: size)

        // Ground shadow stays put; the body bobs.
        if mood != .resting {
            ctx.fill(Path(ellipseIn: CGRect(x: 62, y: 173, width: 76, height: 10)), with: .color(ink.opacity(0.10)))
        }

        var blink = false
        if let time {
            let speed: Double = mood == .moving || mood == .celebrating ? 5 : (mood == .resting ? 1.2 : 2.2)
            let amplitude: Double = mood == .resting ? 1.5 : 2.5
            ctx.translateBy(x: 0, y: CGFloat(sin(time * speed) * amplitude))
            blink = time.truncatingRemainder(dividingBy: 4.2) < 0.14
        }

        if mood == .resting { drawBlanketBack(ctx) }
        drawLegs(ctx, mood: mood)
        drawBody(ctx, variant: variant)
        drawFace(ctx, mood: mood, blink: blink)
        drawArms(ctx, mood: mood, variant: variant)
        drawProps(ctx, mood: mood, time: time, wearsEyewear: outfit.eyewear != .none)
        drawOutfit(body: ctx, face: ctx, outfit: outfit, variant: variant, mood: mood)
        if mood == .resting { drawBlanketFront(ctx) }
    }

    static func stroke(_ ctx: GraphicsContext, _ d: String, _ color: Color, width: CGFloat) {
        ctx.stroke(UnitPath.parse(d), with: .color(color),
                   style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    static func ellipse(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2))
    }

    static func drawBody(_ ctx: GraphicsContext, variant: Theme.BrainVariant) {
        // Outline trick: bigger circles in the shade color, then the fill on top.
        for (x, y, r) in bumps { ctx.fill(circle(x, y, r + 3.5), with: .color(variant.shade)) }
        for (x, y, r) in bumps { ctx.fill(circle(x, y, r), with: .color(variant.fill)) }
        ctx.fill(circle(80, 52, 9), with: .color(variant.light))
        ctx.fill(circle(58, 70, 7), with: .color(variant.light))
        for d in folds { stroke(ctx, d, variant.shade, width: 3) }
    }

    static func drawLegs(_ ctx: GraphicsContext, mood: BrainMood) {
        guard mood != .resting else { return }
        stroke(ctx, "M90,148 L88,170", ink, width: 3.5)
        stroke(ctx, "M110,148 L112,170", ink, width: 3.5)
        ctx.fill(ellipse(84, 173, 9, 5), with: .color(ink))
        ctx.fill(ellipse(116, 173, 9, 5), with: .color(ink))
    }

    static func drawArms(_ ctx: GraphicsContext, mood: BrainMood, variant: Theme.BrainVariant) {
        for d in arms[mood] ?? [] { stroke(ctx, d, ink, width: 3.5) }
        for hand in hands[mood] ?? [] {
            ctx.fill(circle(hand.x, hand.y, 5), with: .color(variant.fill))
            ctx.stroke(circle(hand.x, hand.y, 5), with: .color(variant.shade), lineWidth: 2)
        }
    }

    static func drawFace(_ ctx: GraphicsContext, mood: BrainMood, blink: Bool) {
        let eyeY: CGFloat = 100
        if mood == .resting || blink {
            for x: CGFloat in [84, 116] {
                stroke(ctx, "M\(x - 6),\(eyeY) C\(x - 3),\(eyeY + 5) \(x + 3),\(eyeY + 5) \(x + 6),\(eyeY)", ink, width: 3)
            }
        } else {
            for x: CGFloat in [84, 116] {
                ctx.fill(circle(x, eyeY, 6.5), with: .color(ink))
                ctx.fill(circle(x + 2, eyeY - 2.5, 2.2), with: .color(white))
            }
            if mood == .focused || mood == .moving {
                stroke(ctx, "M76,88 L90,92", ink, width: 3)
                stroke(ctx, "M124,88 L110,92", ink, width: 3)
            }
        }
        ctx.fill(ellipse(71, 110, 7, 4), with: .color(Theme.blush.opacity(0.55)))
        ctx.fill(ellipse(129, 110, 7, 4), with: .color(Theme.blush.opacity(0.55)))

        switch mood {
        case .resting:
            ctx.fill(ellipse(100, 112, 3, 3.5), with: .color(ink))
        case .moving, .celebrating:
            ctx.fill(UnitPath.parse("M92,108 C94,118 106,118 108,108 Z"), with: .color(ink))
        case .focused:
            stroke(ctx, "M94,112 L106,111", ink, width: 3)
        default:
            stroke(ctx, "M93,108 C96,114 104,114 107,108", ink, width: 3)
        }
    }

    static func drawProps(_ ctx: GraphicsContext, mood: BrainMood, time: TimeInterval?, wearsEyewear: Bool = false) {
        switch mood {
        case .resting:
            ctx.fill(UnitPath.parse("M58,66 C70,40 110,28 150,36 L132,64 Z"), with: .color(Theme.lavender))
            stroke(ctx, "M56,68 C80,58 118,56 140,66", white, width: 7)
            ctx.fill(circle(152, 34, 7), with: .color(white))
            // Floating z's drift upward when animated.
            let drift = CGFloat((time ?? 0).truncatingRemainder(dividingBy: 3) / 3)
            for (index, size) in [CGFloat(16), 12, 9].enumerated() {
                let y = 70 - CGFloat(index) * 17 - drift * 6
                ctx.draw(Text("z").font(.system(size: size, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.8 - Double(index) * 0.15)),
                         at: CGPoint(x: 36 - CGFloat(index) * 4, y: y))
            }
        case .moving:
            stroke(ctx, "M48,76 C70,68 130,68 152,76", Theme.blush, width: 7)
            ctx.fill(Path(roundedRect: CGRect(x: 12, y: 68, width: 176, height: 5), cornerRadius: 2.5), with: .color(ink))
            for x: CGFloat in [6, 182] {
                ctx.fill(Path(roundedRect: CGRect(x: x, y: 60, width: 12, height: 21), cornerRadius: 3), with: .color(ink))
            }
        case .learning:
            if !wearsEyewear { drawGlasses(ctx) }
            let book = UnitPath.parse("M72,122 L100,128 L128,122 L128,148 L100,154 L72,148 Z")
            ctx.fill(book, with: .color(white))
            ctx.stroke(book, with: .color(ink), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            stroke(ctx, "M100,128 L100,154", ink, width: 2)
            let lines = Color(hex: 0xC9C4D6)
            for dy: CGFloat in [134, 140] {
                stroke(ctx, "M78,\(dy) L94,\(dy + 3)", lines, width: 2)
                stroke(ctx, "M106,\(dy + 3) L122,\(dy)", lines, width: 2)
            }
        case .focused:
            var pencil = ctx
            pencil.translateBy(x: 160, y: 110)
            pencil.rotate(by: .degrees(30))
            pencil.translateBy(x: -160, y: -110)
            let body = Path(roundedRect: CGRect(x: 156, y: 86, width: 9, height: 40), cornerRadius: 2)
            pencil.fill(body, with: .color(Theme.sun))
            pencil.stroke(body, with: .color(ink), lineWidth: 2)
            pencil.fill(UnitPath.parse("M156,126 L160.5,136 L165,126 Z"), with: .color(ink))
        case .social:
            ctx.fill(Path(roundedRect: CGRect(x: 164, y: 116, width: 20, height: 32), cornerRadius: 5), with: .color(ink))
            ctx.fill(Path(roundedRect: CGRect(x: 167, y: 120, width: 14, height: 22), cornerRadius: 2), with: .color(Theme.Tint.sky))
            ctx.fill(circle(158, 52, 13), with: .color(white))
            ctx.fill(UnitPath.parse("M152,52 C152,46 158,46 158,50 C158,46 164,46 164,52 C164,56 158,60 158,60 C158,60 152,56 152,52 Z"),
                     with: .color(Theme.blush))
        case .celebrating:
            let twinkle = CGFloat(time.map { 0.85 + 0.15 * sin($0 * 6) } ?? 1)
            for (x, y) in [(CGFloat(40), CGFloat(46)), (160, 44), (30, 92), (172, 120)] {
                let r = 7 * twinkle
                let d = "M\(x),\(y - r) L\(x + 2),\(y - 2) L\(x + r),\(y) L\(x + 2),\(y + 2) L\(x),\(y + r) L\(x - 2),\(y + 2) L\(x - r),\(y) L\(x - 2),\(y - 2) Z"
                ctx.fill(UnitPath.parse(d), with: .color(Theme.sun))
            }
        case .idle:
            break
        }
    }

    static func drawGlasses(_ ctx: GraphicsContext) {
        for x: CGFloat in [84, 116] {
            ctx.stroke(circle(x, 100, 11), with: .color(ink), lineWidth: 2.5)
        }
        stroke(ctx, "M95,100 L105,100", ink, width: 2.5)
    }

    static func drawBlanketBack(_ ctx: GraphicsContext) {
        ctx.fill(UnitPath.parse("M30,150 C60,136 140,136 170,150 L176,180 L24,180 Z"), with: .color(Theme.lavender.opacity(0.9)))
    }

    static func drawBlanketFront(_ ctx: GraphicsContext) {
        ctx.fill(UnitPath.parse("M26,150 C60,140 140,140 174,150 L178,176 C140,170 60,170 22,176 Z"), with: .color(Color(hex: 0xA8A1F0)))
    }
}

/// Minimal SVG path parser for the commands used above: absolute M, L, C and Z.
enum UnitPath {
    /// Parsed paths are reused: the same strings are drawn every frame. Bounded, so strings built
    /// from live values (mouths, brows) can't grow it without limit.
    private static let cache: NSCache<NSString, PathBox> = {
        let cache = NSCache<NSString, PathBox>()
        cache.countLimit = 400
        return cache
    }()

    final class PathBox {
        let path: Path
        init(_ path: Path) { self.path = path }
    }

    static func parse(_ d: String) -> Path {
        if let hit = cache.object(forKey: d as NSString) { return hit.path }
        let path = build(d)
        cache.setObject(PathBox(path), forKey: d as NSString)
        return path
    }

    private static func build(_ d: String) -> Path {
        var path = Path()
        var tokens: [String] = []
        var current = ""
        for character in d {
            if "MLCZ".contains(character) {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(character))
            } else if character == "," || character == " " {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }

        var index = 0
        var command = "M"
        func number() -> CGFloat {
            defer { index += 1 }
            return index < tokens.count ? CGFloat(Double(tokens[index]) ?? 0) : 0
        }
        func point() -> CGPoint {
            let x = number()
            let y = number()
            return CGPoint(x: x, y: y)
        }

        while index < tokens.count {
            let token = tokens[index]
            if "MLCZ".contains(token) {
                command = token
                index += 1
                if command == "Z" { path.closeSubpath(); continue }
            }
            switch command {
            case "M":
                path.move(to: point())
                command = "L" // Extra coordinate pairs after M are implicit L.
            case "L":
                path.addLine(to: point())
            case "C":
                let c1 = point()
                let c2 = point()
                let end = point()
                path.addCurve(to: end, control1: c1, control2: c2)
            default:
                index += 1
            }
        }
        return path
    }
}
