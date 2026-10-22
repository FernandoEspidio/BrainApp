import SwiftUI

/// The expressive face shared by every brain (your live mirror, recorded moves, friends' cards),
/// plus the mystery silhouette used by the trade scene.
/// Everything is drawn in the same 200×200 unit box as the character.

// MARK: - Puppet drawing

extension BrainDrawing {
    static func drawPuppetFace(_ ctx: GraphicsContext, pose: FacePose) {
        let eyeY: CGFloat = 100 - CGFloat(pose.browUp) * 2
        let gazeX = CGFloat(pose.gazeX)
        let gazeY = CGFloat(pose.gazeY)
        let wide = 1 + CGFloat(pose.eyeWide) * 0.25
        let happyEyes = pose.smile > 0.45 && pose.squint > 0.35

        // Eyes: height follows how open each eye is; closed eyes become arcs, smiling eyes become ^ ^.
        for (x, openness) in [(CGFloat(84), pose.leftEyeOpen), (CGFloat(116), pose.rightEyeOpen)] {
            let open = CGFloat(min(max(openness, 0), 1)) * (1 - CGFloat(pose.squint) * 0.35)
            if happyEyes && openness > 0.3 {
                stroke(ctx, "M\(x - 6),\(eyeY + 2) C\(x - 3),\(eyeY - 5) \(x + 3),\(eyeY - 5) \(x + 6),\(eyeY + 2)", ink, width: 3)
            } else if open < 0.3 {
                stroke(ctx, "M\(x - 6),\(eyeY) C\(x - 3),\(eyeY + 5) \(x + 3),\(eyeY + 5) \(x + 6),\(eyeY)", ink, width: 3)
            } else {
                let width = 13 * wide
                let height = 13 * (0.35 + 0.65 * open) * (1 + CGFloat(pose.browUp) * 0.2) * wide
                let cx = x + gazeX * 2.6
                let cy = eyeY + gazeY * 2
                ctx.fill(Path(ellipseIn: CGRect(x: cx - width / 2, y: cy - height / 2, width: width, height: height)), with: .color(ink))
                if open > 0.6 {
                    ctx.fill(circle(cx + 2 + gazeX * 1.2, cy - height / 4 + gazeY * 0.8, 2.2 * wide), with: .color(white))
                }
            }
        }

        // Brows appear when they're doing something. Each side can rise on its own.
        let activity = pose.browUp + pose.browDown + max(pose.leftBrowRaise, pose.rightBrowRaise)
        let browStrength = min(1, Double(activity) * 2.5)
        if browStrength > 0.05 {
            let color = ink.opacity(browStrength)
            for (outer, inner, raise) in [(CGFloat(76), CGFloat(90), pose.leftBrowRaise), (CGFloat(124), CGFloat(110), pose.rightBrowRaise)] {
                let up = CGFloat(pose.browUp)
                let down = CGFloat(pose.browDown)
                let r = CGFloat(raise)
                let yOuter = 87 - (up * 5 + r * 9) + down * 1
                let yInner = 87 - (up * 8 + r * 3) + down * 5
                let mid = (outer + inner) / 2
                stroke(ctx, "M\(outer),\(yOuter) C\(mid),\(min(yOuter, yInner) - 2.5) \(mid),\(min(yOuter, yInner) - 2.5) \(inner),\(yInner)", color, width: 3)
            }
        }

        // Cheeks: blush grows with smiles and puffs.
        let blushSize = 7 + CGFloat(pose.cheekPuff) * 5 + CGFloat(pose.smile) * 2
        let blushAlpha = 0.45 + Double(pose.smile) * 0.35 + Double(pose.cheekPuff) * 0.2
        ctx.fill(ellipse(71, 110, blushSize, 4 + CGFloat(pose.cheekPuff) * 2), with: .color(Theme.blush.opacity(min(blushAlpha, 0.95))))
        ctx.fill(ellipse(129, 110, blushSize, 4 + CGFloat(pose.cheekPuff) * 2), with: .color(Theme.blush.opacity(min(blushAlpha, 0.95))))

        // Mouth: width from smile/pucker, curve from smile/frown, opening from jaw, side pull from mouthShift.
        let cx: CGFloat = 100 + CGFloat(pose.mouthShift) * 6
        let cy: CGFloat = 111 + CGFloat(pose.frown) * 2
        let pucker = CGFloat(pose.pucker)
        let funnel = CGFloat(pose.funnel)
        let halfWidth = max(3, 7 + CGFloat(pose.smile) * 7 + CGFloat(pose.jawOpen) * 3 - pucker * 5 - funnel * 3)
        let curve = CGFloat(pose.smile) * 6 + 2 - CGFloat(pose.frown) * 9 // resting face: a slight smile
        let open = CGFloat(pose.jawOpen) * 22

        if funnel > 0.4 {
            // "Ooh"
            ctx.fill(ellipse(cx, cy + 2 + open * 0.2, 3 + funnel * 3, 3 + funnel * 2 + open * 0.3), with: .color(ink))
        } else if pucker > 0.55 && open < 4 {
            ctx.stroke(circle(cx, cy + 1, 3 + pucker * 2), with: .color(ink), lineWidth: 3)
        } else if open > 2.5 {
            let mouth = UnitPath.parse(
                "M\(cx - halfWidth),\(cy - curve * 0.3) C\(cx - halfWidth * 0.4),\(cy + curve * 0.4) \(cx + halfWidth * 0.4),\(cy + curve * 0.4) \(cx + halfWidth),\(cy - curve * 0.3) " +
                "C\(cx + halfWidth * 0.8),\(cy + max(curve, 0) + open) \(cx - halfWidth * 0.8),\(cy + max(curve, 0) + open) \(cx - halfWidth),\(cy - curve * 0.3) Z"
            )
            ctx.fill(mouth, with: .color(ink))
            if pose.tongueOut > 0.2 {
                let tongue = CGFloat(pose.tongueOut)
                ctx.fill(ellipse(cx, cy + max(curve, 0) * 0.5 + open * 0.75 + tongue * 4, halfWidth * 0.55, 3 + tongue * 5),
                         with: .color(Theme.blush))
            }
        } else {
            stroke(ctx, "M\(cx - halfWidth),\(cy - curve * 0.3) C\(cx - halfWidth * 0.4),\(cy + curve) \(cx + halfWidth * 0.4),\(cy + curve) \(cx + halfWidth),\(cy - curve * 0.3)", ink, width: 3)
            if pose.tongueOut > 0.3 {
                ctx.fill(ellipse(cx, cy + max(curve, 0) * 0.6 + 4, 4, 3 + CGFloat(pose.tongueOut) * 4), with: .color(Theme.blush))
            }
        }
    }

    // MARK: - Mystery brain (not met yet)

    /// Flat gray silhouette with two glinting eyes. `time` drives blinks and a little sway.
    static func drawMystery(_ context: GraphicsContext, size: CGSize, time: TimeInterval?, lookX: CGFloat = 0) {
        let base = unitContext(context, size: size)
        base.fill(ellipse(100, 178, 38, 5), with: .color(ink.opacity(0.08)))
        var ctx = base
        if let time { ctx.translateBy(x: 0, y: CGFloat(sin(time * 2.4) * 2)) }
        let shade = Theme.mystery.shade
        stroke(ctx, "M90,148 L88,170", shade, width: 3.5)
        stroke(ctx, "M110,148 L112,170", shade, width: 3.5)
        ctx.fill(ellipse(84, 173, 9, 5), with: .color(shade))
        ctx.fill(ellipse(116, 173, 9, 5), with: .color(shade))
        for (x, y, r) in bumps { ctx.fill(circle(x, y, r + 3.5), with: .color(shade)) }
        for (x, y, r) in bumps { ctx.fill(circle(x, y, r), with: .color(Theme.mystery.fill)) }
        for d in folds { stroke(ctx, d, shade, width: 3) }

        let blink = (time ?? 1).truncatingRemainder(dividingBy: 3.3) < 0.14
        for x: CGFloat in [84, 116] {
            let cx = x + lookX * 4
            if blink {
                stroke(ctx, "M\(cx - 5),100 L\(cx + 5),100", .white, width: 3)
            } else {
                ctx.fill(ellipse(cx, 100, 5, 6.5), with: .color(.white))
            }
        }
    }
}

// MARK: - Accessories

extension BrainDrawing {
    /// Accessories drawn on the body context (they follow head roll and squash).
    static func drawOutfit(body: GraphicsContext, face: GraphicsContext, outfit: Outfit,
                           variant: Theme.BrainVariant, mood: BrainMood) {
        drawEyewear(face, eyewear: outfit.eyewear, mood: mood)
        drawHeadwear(body, headwear: outfit.headwear, variant: variant, mood: mood)
    }

    static func drawEyewear(_ ctx: GraphicsContext, eyewear: CompanionAppearance.Eyewear, mood: BrainMood) {
        switch eyewear {
        case .none:
            break
        case .glasses:
            drawGlasses(ctx)
        case .shades:
            for x: CGFloat in [84, 116] {
                let lens = Path(roundedRect: CGRect(x: x - 12, y: 92, width: 24, height: 15), cornerRadius: 6)
                ctx.fill(lens, with: .color(ink))
                stroke(ctx, "M\(x - 7),96 L\(x - 2),96", .white.opacity(0.55), width: 2)
            }
            stroke(ctx, "M96,96 C98,93 102,93 104,96", ink, width: 3)
            stroke(ctx, "M72,96 L64,94", ink, width: 3)
            stroke(ctx, "M128,96 L136,94", ink, width: 3)
        case .hearts:
            for x: CGFloat in [84, 116] {
                let heart = heartPath(x: x, y: 99, size: 13)
                ctx.fill(heart, with: .color(Theme.blush))
                ctx.stroke(heart, with: .color(ink), lineWidth: 2)
            }
            stroke(ctx, "M96,96 C98,93 102,93 104,96", ink, width: 2.5)
        case .stars:
            for x: CGFloat in [84, 116] {
                let star = starPath(x: x, y: 99, outer: 13, inner: 6)
                ctx.fill(star, with: .color(Theme.sun))
                ctx.stroke(star, with: .color(ink), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
            stroke(ctx, "M96,97 C98,94 102,94 104,97", ink, width: 2.5)
        }
    }

    static func drawHeadwear(_ ctx: GraphicsContext, headwear: CompanionAppearance.Headwear,
                             variant: Theme.BrainVariant, mood: BrainMood) {
        // The nightcap prop owns the head while resting.
        guard mood != .resting || headwear == .none else { return }
        let outline = StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
        switch headwear {
        case .none:
            break
        case .sprout:
            stroke(ctx, "M100,34 C100,26 101,20 103,14", Theme.Deep.mint, width: 3)
            ctx.fill(UnitPath.parse("M103,16 C110,4 126,6 128,8 C124,20 112,22 103,16 Z"), with: .color(Theme.Deep.mint))
            ctx.fill(UnitPath.parse("M101,20 C94,10 80,12 78,14 C82,24 94,26 101,20 Z"), with: .color(Color(hex: 0x7FCFA9)))
        case .star:
            ctx.fill(starPath(x: 142, y: 32, outer: 12, inner: 5), with: .color(Theme.sun))
            ctx.stroke(starPath(x: 142, y: 32, outer: 12, inner: 5), with: .color(Theme.Deep.butter), style: outline)
        case .crown:
            let crown = UnitPath.parse("M74,38 L76,12 L89,25 L100,6 L111,25 L124,12 L126,38 Z")
            ctx.fill(crown, with: .color(Theme.sun))
            ctx.stroke(crown, with: .color(Theme.Deep.butter), style: outline)
            ctx.fill(circle(100, 28, 4), with: .color(Theme.blush))
            ctx.fill(circle(84, 31, 3), with: .color(Theme.Deep.sky))
            ctx.fill(circle(116, 31, 3), with: .color(Theme.Deep.mint))
        case .beanie:
            let dome = UnitPath.parse("M42,60 C40,8 160,8 158,60 Z")
            ctx.fill(dome, with: .color(Color(hex: 0x8F87E6)))
            for x: CGFloat in [70, 100, 130] { stroke(ctx, "M\(x),22 L\(x),52", Color(hex: 0x7A72D6), width: 3) }
            let rim = UnitPath.parse("M38,56 C70,46 130,46 162,56 L162,70 C130,60 70,60 38,70 Z")
            ctx.fill(rim, with: .color(Color(hex: 0x6F67C9)))
            ctx.fill(circle(100, 10, 10), with: .color(Theme.Tint.lilac))
        case .party:
            let cone = UnitPath.parse("M80,40 L108,-4 L124,34 Z")
            ctx.fill(cone, with: .color(Theme.Deep.sky))
            stroke(ctx, "M88,28 L116,20", Theme.sun, width: 4)
            stroke(ctx, "M97,14 L112,10", Theme.blush, width: 4)
            ctx.stroke(cone, with: .color(ink.opacity(0.25)), style: outline)
            ctx.fill(circle(108, -4, 7), with: .color(Theme.sun))
        case .bow:
            var bow = ctx
            bow.translateBy(x: 136, y: 34)
            bow.rotate(by: .degrees(-18))
            for side: CGFloat in [-1, 1] {
                let loop = UnitPath.parse("M0,0 C\(side * 10),-16 \(side * 26),-12 \(side * 24),0 C\(side * 26),12 \(side * 10),16 0,0 Z")
                bow.fill(loop, with: .color(Theme.blush))
                bow.stroke(loop, with: .color(Theme.Deep.rose), style: outline)
            }
            bow.fill(circle(0, 0, 5), with: .color(Theme.Deep.rose))
        case .cap:
            let dome = UnitPath.parse("M50,54 C48,12 152,12 150,54 Z")
            ctx.fill(dome, with: .color(Theme.Deep.sky))
            stroke(ctx, "M100,16 L100,54", Color(hex: 0x5A86D6), width: 2.5)
            let brim = UnitPath.parse("M138,48 C160,44 180,50 186,58 C168,62 150,60 136,56 Z")
            ctx.fill(brim, with: .color(Color(hex: 0x5A86D6)))
            ctx.fill(circle(100, 15, 5), with: .color(Color(hex: 0x5A86D6)))
        case .headphones:
            stroke(ctx, "M30,84 C34,22 166,22 170,84", ink, width: 5)
            ctx.fill(Path(roundedRect: CGRect(x: 20, y: 76, width: 16, height: 28), cornerRadius: 6), with: .color(ink))
            ctx.fill(Path(roundedRect: CGRect(x: 164, y: 76, width: 16, height: 28), cornerRadius: 6), with: .color(ink))
            ctx.fill(Path(roundedRect: CGRect(x: 24, y: 82, width: 6, height: 16), cornerRadius: 3), with: .color(Theme.pink))
            ctx.fill(Path(roundedRect: CGRect(x: 170, y: 82, width: 6, height: 16), cornerRadius: 3), with: .color(Theme.pink))
        case .catEars:
            for (outer, tip, inner) in [((CGFloat(52), CGFloat(56)), (CGFloat(58), CGFloat(14)), (CGFloat(88), CGFloat(36))),
                                         ((148, 56), (142, 14), (112, 36))] {
                let ear = UnitPath.parse("M\(outer.0),\(outer.1) L\(tip.0),\(tip.1) L\(inner.0),\(inner.1) Z")
                ctx.fill(ear, with: .color(variant.fill))
                ctx.stroke(ear, with: .color(variant.shade), style: StrokeStyle(lineWidth: 3.5, lineJoin: .round))
                let midX = (outer.0 + tip.0 + inner.0) / 3
                let innerEar = UnitPath.parse("M\((outer.0 + midX) / 2),\(outer.1 - 10) L\(tip.0 + (midX - tip.0) * 0.3),\(tip.1 + 10) L\((inner.0 + midX) / 2),\(inner.1 + 2) Z")
                ctx.fill(innerEar, with: .color(Theme.blush.opacity(0.6)))
            }
        case .flower:
            let (fx, fy): (CGFloat, CGFloat) = (62, 40)
            for index in 0..<5 {
                let angle = Double(index) / 5 * 2 * .pi - .pi / 2
                ctx.fill(circle(fx + 9 * CGFloat(cos(angle)), fy + 9 * CGFloat(sin(angle)), 7), with: .color(.white))
                ctx.stroke(circle(fx + 9 * CGFloat(cos(angle)), fy + 9 * CGFloat(sin(angle)), 7), with: .color(Theme.blush.opacity(0.5)), lineWidth: 1.5)
            }
            ctx.fill(circle(fx, fy, 6), with: .color(Theme.sun))
        case .wizard:
            ctx.fill(ellipse(100, 36, 50, 9), with: .color(Color(hex: 0x5D55B8)))
            let cone = UnitPath.parse("M68,36 C80,20 92,0 112,-8 C110,6 124,22 132,36 Z")
            ctx.fill(cone, with: .color(Color(hex: 0x6F67C9)))
            ctx.fill(starPath(x: 100, y: 20, outer: 6, inner: 2.6), with: .color(Theme.sun))
            ctx.fill(starPath(x: 116, y: 8, outer: 4, inner: 1.8), with: .color(Theme.sun))
            ctx.fill(circle(86, 30, 2), with: .color(Theme.sun))
        }
    }

    static func starPath(x: CGFloat, y: CGFloat, outer: CGFloat, inner: CGFloat) -> Path {
        var path = Path()
        for index in 0..<10 {
            let radius = index.isMultiple(of: 2) ? outer : inner
            let angle = Double(index) / 10 * 2 * .pi - .pi / 2
            let point = CGPoint(x: x + radius * CGFloat(cos(angle)), y: y + radius * CGFloat(sin(angle)))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    static func heartPath(x: CGFloat, y: CGFloat, size s: CGFloat) -> Path {
        UnitPath.parse(
            "M\(x),\(y + s * 0.55) C\(x - s * 1.1),\(y - s * 0.1) \(x - s * 0.55),\(y - s * 0.85) \(x),\(y - s * 0.3) " +
            "C\(x + s * 0.55),\(y - s * 0.85) \(x + s * 1.1),\(y - s * 0.1) \(x),\(y + s * 0.55) Z"
        )
    }
}
