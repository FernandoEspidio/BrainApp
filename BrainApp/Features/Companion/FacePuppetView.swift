import SwiftUI
import UIKit

/// TEST: "Brain animoji". Your face (ARKit) drives the 2D brain live: blinks, mouth, smile, brows,
/// cheeks, tongue and head tilt. Nothing is recorded. If it looks right on screen it can be captured
/// later by recording the FacePose stream (tiny) and rendering it to video/GIF.
struct FacePuppetView: View {
    @Environment(AppModel.self) private var model
    @State private var tracker = FaceTracker()
    @State private var showValues = false

    var body: some View {
        let companion = model.repository.snapshot.companion
        let pose = tracker.pose
        let variant = Theme.brainVariant(companion.colorIndex)

        ScrollView {
            VStack(spacing: 16) {
                Canvas { context, size in
                    BrainDrawing.drawHalo(context, size: size, mood: .idle, stage: nil)
                    BrainDrawing.drawPuppet(context, size: size, pose: pose, variant: variant, accessory: companion.accessory)
                }
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal)
                .accessibilityLabel("Your brain buddy copying your face")

                Label(tracker.status, systemImage: tracker.isTracking ? "face.smiling" : "faceid")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tracker.isTracking ? Theme.Deep.mint : Theme.inkSoft)

                if FaceTracker.isSupported {
                    HStack(spacing: 10) {
                        Button("Center my head") { tracker.calibrate() }
                            .buttonStyle(SoftButtonStyle())
                        Toggle("Mirror", isOn: Binding(get: { tracker.mirrored }, set: { tracker.mirrored = $0 }))
                            .fixedSize()
                    }
                    VStack(alignment: .leading) {
                        Text("Smoothing").font(.caption).foregroundStyle(Theme.inkSoft)
                        Slider(value: Binding(get: { Double(tracker.smoothing) }, set: { tracker.smoothing = Float($0) }), in: 0...0.9)
                    }
                    .padding(.horizontal)

                    DisclosureGroup("Live values", isExpanded: $showValues) {
                        valueBars(pose)
                    }
                    .tint(Theme.ink)
                    .padding(.horizontal)
                } else {
                    Text("This iPhone doesn't support face tracking (needs Face ID or an A12 chip or later).")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                }

                Text("Try: blink, wink, open your mouth, smile big, raise or frown your brows, puff your cheeks, stick your tongue out, tilt your head. The camera image is never shown or saved.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Theme.cream.ignoresSafeArea())
        .navigationTitle("Brain animoji (test)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            tracker.start()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            tracker.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func valueBars(_ pose: FacePose) -> some View {
        let rows: [(String, Float)] = [
            ("Left eye open", pose.leftEyeOpen), ("Right eye open", pose.rightEyeOpen),
            ("Jaw open", pose.jawOpen), ("Smile", pose.smile), ("Brows up", pose.browUp),
            ("Brows down", pose.browDown), ("Cheek puff", pose.cheekPuff), ("Tongue", pose.tongueOut),
            ("Pucker", pose.pucker),
            ("Head roll", abs(pose.headRoll) / 0.8), ("Head yaw", abs(pose.headYaw) / 0.8), ("Head pitch", abs(pose.headPitch) / 0.8)
        ]
        return VStack(spacing: 6) {
            ForEach(rows, id: \.0) { row in
                HStack {
                    Text(row.0).font(.caption).frame(width: 110, alignment: .leading)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.ink.opacity(0.06))
                            Capsule().fill(Theme.pink)
                                .frame(width: geometry.size.width * CGFloat(min(max(row.1, 0), 1)))
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
        .padding(.top, 8)
    }
}

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
