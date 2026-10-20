import SwiftUI
import UIKit

/// The standalone animoji screen was folded into Friends (Mirror me → Record).
/// What remains here is the expressive face drawing shared by every brain.

// MARK: - Puppet drawing (same 200×200 unit box as the character)

extension BrainDrawing {
    static func drawPuppet(_ context: GraphicsContext, size: CGSize, pose: FacePose,
                           variant: Theme.BrainVariant, accessory: CompanionAppearance.Accessory) {
        let base = unitContext(context, size: size)
        let yaw = CGFloat(pose.headYaw)
        let pitch = CGFloat(pose.headPitch)

        base.fill(ellipse(100, 178, 38, 5), with: .color(ink.opacity(0.10)))

        // Legs stay grounded; only follow side-to-side a little.
        var legs = base
        legs.translateBy(x: yaw * 12, y: 0)
        drawLegs(legs, mood: .idle)

        // The body follows the head: shift, tilt (roll), and squash/stretch with mouth and cheeks.
        var body = base
        body.translateBy(x: 100 + yaw * 30, y: 110 + pitch * 24)
        body.rotate(by: .radians(Double(pose.headRoll)))
        body.scaleBy(x: 1 + CGFloat(pose.cheekPuff) * 0.07, y: 1 + CGFloat(pose.jawOpen) * 0.05)
        body.translateBy(x: -100, y: -110)

        drawBody(body, variant: variant)

        // Facial features move a bit more than the body: cheap parallax that reads as 3D.
        var face = body
        face.translateBy(x: yaw * 14, y: pitch * 10)
        drawPuppetFace(face, pose: pose)

        let excited = pose.smile > 0.6 || (pose.browUp > 0.6 && pose.jawOpen > 0.35)
        drawArms(body, mood: excited ? .celebrating : .idle, variant: variant)
        drawAccessory(body, accessory: accessory, mood: .idle)
    }

    static func drawPuppetFace(_ ctx: GraphicsContext, pose: FacePose) {
        let browLift = CGFloat(pose.browUp) * 7 - CGFloat(pose.browDown) * 3
        let eyeY: CGFloat = 100 - CGFloat(pose.browUp) * 2

        // Eyes: height follows how open each eye is; closed eyes become arcs.
        for (x, openness) in [(CGFloat(84), pose.leftEyeOpen), (CGFloat(116), pose.rightEyeOpen)] {
            let open = CGFloat(min(max(openness, 0), 1))
            if open < 0.3 {
                stroke(ctx, "M\(x - 6),\(eyeY) C\(x - 3),\(eyeY + 5) \(x + 3),\(eyeY + 5) \(x + 6),\(eyeY)", ink, width: 3)
            } else {
                let height = 13 * (0.35 + 0.65 * open) * (1 + CGFloat(pose.browUp) * 0.2)
                ctx.fill(Path(ellipseIn: CGRect(x: x - 6.5, y: eyeY - height / 2, width: 13, height: height)), with: .color(ink))
                if open > 0.6 {
                    ctx.fill(circle(x + 2, eyeY - height / 4, 2.2), with: .color(white))
                }
            }
        }

        // Brows appear when they're doing something.
        let browStrength = min(1, Double(pose.browUp + pose.browDown) * 2.5)
        if browStrength > 0.05 {
            let y = 87 - browLift
            let tilt = CGFloat(pose.browDown) * 6 - CGFloat(pose.browUp) * 3
            let color = ink.opacity(browStrength)
            stroke(ctx, "M76,\(y) L90,\(y + tilt)", color, width: 3)
            stroke(ctx, "M124,\(y) L110,\(y + tilt)", color, width: 3)
        }

        // Cheeks: blush grows with smiles and puffs.
        let blushSize = 7 + CGFloat(pose.cheekPuff) * 5 + CGFloat(pose.smile) * 2
        let blushAlpha = 0.45 + Double(pose.smile) * 0.35 + Double(pose.cheekPuff) * 0.2
        ctx.fill(ellipse(71, 110, blushSize, 4 + CGFloat(pose.cheekPuff) * 2), with: .color(Theme.blush.opacity(min(blushAlpha, 0.95))))
        ctx.fill(ellipse(129, 110, blushSize, 4 + CGFloat(pose.cheekPuff) * 2), with: .color(Theme.blush.opacity(min(blushAlpha, 0.95))))

        // Mouth: width from smile/pucker, curve from smile, opening from jaw.
        let cy: CGFloat = 111
        let pucker = CGFloat(pose.pucker)
        let halfWidth = max(3, 7 + CGFloat(pose.smile) * 7 + CGFloat(pose.jawOpen) * 3 - pucker * 5)
        let curve = CGFloat(pose.smile) * 6 + 2 // resting face: a slight smile
        let open = CGFloat(pose.jawOpen) * 22

        if pucker > 0.55 && open < 4 {
            ctx.stroke(circle(100, cy + 1, 3 + pucker * 2), with: .color(ink), lineWidth: 3)
        } else if open > 2.5 {
            let mouth = UnitPath.parse(
                "M\(100 - halfWidth),\(cy - curve * 0.3) C\(100 - halfWidth * 0.4),\(cy + curve * 0.4) \(100 + halfWidth * 0.4),\(cy + curve * 0.4) \(100 + halfWidth),\(cy - curve * 0.3) " +
                "C\(100 + halfWidth * 0.8),\(cy + curve + open) \(100 - halfWidth * 0.8),\(cy + curve + open) \(100 - halfWidth),\(cy - curve * 0.3) Z"
            )
            ctx.fill(mouth, with: .color(ink))
            if pose.tongueOut > 0.2 {
                let tongue = CGFloat(pose.tongueOut)
                ctx.fill(ellipse(100, cy + curve * 0.5 + open * 0.75 + tongue * 4, halfWidth * 0.55, 3 + tongue * 5),
                         with: .color(Theme.blush))
            }
        } else {
            stroke(ctx, "M\(100 - halfWidth),\(cy - curve * 0.3) C\(100 - halfWidth * 0.4),\(cy + curve) \(100 + halfWidth * 0.4),\(cy + curve) \(100 + halfWidth),\(cy - curve * 0.3)", ink, width: 3)
            if pose.tongueOut > 0.3 {
                ctx.fill(ellipse(100, cy + curve * 0.6 + 4, 4, 3 + CGFloat(pose.tongueOut) * 4), with: .color(Theme.blush))
            }
        }
    }
}
