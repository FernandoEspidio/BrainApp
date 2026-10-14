import SceneKit
import SwiftUI
import UIKit

/// EARLY PREVIEW of a 3D buddy, built procedurally (no 3D assets): two soft hemispheres covered in
/// "gyri" bumps, a face, legs, and a few mood animations. Drag to orbit, tap to make it jump.
///
/// Purpose: explore how a 3D companion could feel before investing in a modeled/rigged character.
/// Note: SceneKit is soft-deprecated by Apple; a production version should move to RealityKit
/// (`RealityView`) with a proper USDZ model and skeletal animations.
struct Brain3DPreviewView: View {
    @State private var model = Brain3DScene()
    @State private var mood: Brain3DScene.Mood = .idle

    var body: some View {
        VStack(spacing: 16) {
            SceneView(scene: model.scene, pointOfView: model.camera, options: [.allowsCameraControl])
                .frame(maxWidth: .infinity)
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .onTapGesture { model.jump() }
                .accessibilityLabel("3D brain buddy. Drag to rotate, tap to make it jump.")

            Picker("Mood", selection: $mood) {
                ForEach(Brain3DScene.Mood.allCases) { mood in
                    Text(mood.label).tag(mood)
                }
            }
            .pickerStyle(.segmented)

            Text("Preview only: a simple procedural model to try out size, motion and personality. Drag to rotate, tap to jump.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .padding()
        .background(Theme.cream.ignoresSafeArea())
        .navigationTitle("3D buddy")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: mood) { _, newValue in model.apply(newValue) }
        .onAppear { model.apply(mood) }
    }
}

/// Used from the main thread only (SwiftUI); SceneKit renders on its own thread.
final class Brain3DScene {
    enum Mood: String, CaseIterable, Identifiable {
        case idle, sleepy, pumped, happy

        var id: String { rawValue }

        var label: String {
            switch self {
            case .idle: return "Idle"
            case .sleepy: return "Sleepy"
            case .pumped: return "Pumped"
            case .happy: return "Happy"
            }
        }

        var background: Color {
            switch self {
            case .idle: return Theme.Tint.peach
            case .sleepy: return Theme.nightHalo
            case .pumped: return Theme.Tint.mint
            case .happy: return Theme.Tint.rose
            }
        }
    }

    let scene = SCNScene()
    let camera = SCNNode()
    private let character = SCNNode()   // moves (bob, jump)
    private let body = SCNNode()        // the brain itself (breathing, wiggle)
    private var eyes: [SCNNode] = []
    private let mouth = SCNNode()
    private let zzz = SCNNode()

    private let pink = UIColor(Theme.pink)
    private let pinkDeep = UIColor(Theme.pinkDeep)
    private let ink = UIColor(Theme.ink)

    init() {
        buildLights()
        buildCharacter()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 38
        camera.position = SCNVector3(0, 0.1, 6.2)
        scene.rootNode.addChildNode(camera)
    }

    // MARK: - Build

    private func material(_ color: UIColor, roughness: CGFloat = 0.55) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.roughness.contents = roughness
        material.metalness.contents = 0.0
        return material
    }

    private func buildLights() {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 550
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 1100
        key.eulerAngles = SCNVector3(-0.6, 0.5, 0)
        scene.rootNode.addChildNode(key)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = 450
        rim.eulerAngles = SCNVector3(0.3, .pi + 0.6, 0)
        scene.rootNode.addChildNode(rim)
    }

    private func buildCharacter() {
        let skin = material(pink)

        // Two hemispheres (ellipsoids) + bumps placed on their surface with a Fibonacci spiral.
        let bumps = SCNNode()
        for side: Float in [-1, 1] {
            let radii = SIMD3<Float>(0.66, 0.8, 1.0)
            let center = SIMD3<Float>(side * 0.5, 0.15, 0)

            let core = SCNNode(geometry: SCNSphere(radius: 1))
            core.geometry?.firstMaterial = skin
            core.simdScale = radii
            core.simdPosition = center
            bumps.addChildNode(core)

            let count = 150
            for index in 0..<count {
                let y = 1 - (Float(index) + 0.5) / Float(count) * 2
                let radius = (1 - y * y).squareRoot()
                let theta = Float(index) * 2.399963 // golden angle
                let unit = SIMD3<Float>(cos(theta) * radius, y, sin(theta) * radius)
                if unit.x * side < -0.45 { continue }   // leave the central fissure clear
                if unit.y < -0.75 { continue }          // flatter bottom
                let bump = SCNNode(geometry: SCNSphere(radius: CGFloat(0.2 + 0.05 * abs(sin(Float(index) * 1.7)))))
                bump.geometry?.firstMaterial = skin
                bump.simdPosition = center + unit * radii * 0.93
                bumps.addChildNode(bump)
            }
        }
        // One node instead of hundreds keeps it fast.
        body.addChildNode(bumps.flattenedClone())

        buildFace()
        buildLegs()

        zzz.position = SCNVector3(-1.1, 1.2, 0.4)
        body.addChildNode(zzz)

        character.addChildNode(body)
        scene.rootNode.addChildNode(character)
    }

    private func buildFace() {
        let inkMaterial = material(ink, roughness: 0.3)
        for x: Float in [-0.32, 0.32] {
            let eye = SCNNode(geometry: SCNSphere(radius: 0.12))
            eye.geometry?.firstMaterial = inkMaterial
            eye.simdPosition = SIMD3(x, 0.05, 1.12)
            eye.simdScale = SIMD3(1, 1.15, 0.6)

            let shine = SCNNode(geometry: SCNSphere(radius: 0.04))
            shine.geometry?.firstMaterial = material(.white, roughness: 0.2)
            shine.simdPosition = SIMD3(0.04, 0.05, 0.1)
            eye.addChildNode(shine)

            eyes.append(eye)
            body.addChildNode(eye)

            let cheek = SCNNode(geometry: SCNSphere(radius: 0.14))
            cheek.geometry?.firstMaterial = material(pinkDeep, roughness: 0.8)
            cheek.simdPosition = SIMD3(x * 1.75, -0.2, 1.04)
            cheek.simdScale = SIMD3(1, 0.55, 0.3)
            body.addChildNode(cheek)
        }

        let smile = SCNTorus(ringRadius: 0.13, pipeRadius: 0.025)
        smile.firstMaterial = inkMaterial
        mouth.geometry = smile
        mouth.simdPosition = SIMD3(0, -0.2, 1.14)
        mouth.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        mouth.simdScale = SIMD3(1, 1, 0.55)
        body.addChildNode(mouth)
    }

    private func buildLegs() {
        let inkMaterial = material(ink, roughness: 0.4)
        for x: Float in [-0.3, 0.3] {
            let leg = SCNNode(geometry: SCNCylinder(radius: 0.045, height: 0.55))
            leg.geometry?.firstMaterial = inkMaterial
            leg.simdPosition = SIMD3(x, -0.95, 0.2)
            character.addChildNode(leg)

            let foot = SCNNode(geometry: SCNSphere(radius: 0.14))
            foot.geometry?.firstMaterial = inkMaterial
            foot.simdPosition = SIMD3(x * 1.1, -1.22, 0.3)
            foot.simdScale = SIMD3(1.3, 0.6, 1.6)
            character.addChildNode(foot)
        }
    }

    // MARK: - Moods

    func apply(_ mood: Mood) {
        scene.background.contents = UIColor(mood.background)
        for node in [character, body, mouth, zzz] + eyes { node.removeAllActions() }
        character.position = SCNVector3Zero
        character.eulerAngles = SCNVector3Zero
        body.scale = SCNVector3(1, 1, 1)
        zzz.childNodes.forEach { $0.removeFromParentNode() }

        switch mood {
        case .idle:
            setEyes(closed: false)
            setMouth(open: false)
            character.runAction(.repeatForever(bob(height: 0.07, duration: 1.3)))
            character.runAction(.repeatForever(.sequence([
                .rotateTo(x: 0, y: 0.18, z: 0, duration: 2.2, usesShortestUnitArc: true),
                .rotateTo(x: 0, y: -0.18, z: 0, duration: 2.2, usesShortestUnitArc: true)
            ])))
            startBlinking()
        case .sleepy:
            setEyes(closed: true)
            setMouth(open: false)
            body.runAction(.repeatForever(.sequence([
                .scale(to: 1.035, duration: 1.8), .scale(to: 1.0, duration: 1.8)
            ])))
            character.runAction(.rotateTo(x: 0.12, y: 0, z: 0.08, duration: 0.6))
            zzz.runAction(.repeatForever(.sequence([.run { [weak self] _ in
                DispatchQueue.main.async { self?.spawnZ() }
            }, .wait(duration: 1.1)])))
        case .pumped:
            setEyes(closed: false)
            setMouth(open: true)
            character.runAction(.repeatForever(bob(height: 0.18, duration: 0.32)))
            body.runAction(.repeatForever(.sequence([
                .rotateTo(x: 0, y: 0, z: 0.08, duration: 0.16), .rotateTo(x: 0, y: 0, z: -0.08, duration: 0.16)
            ])))
            startBlinking()
        case .happy:
            setEyes(closed: false)
            setMouth(open: true)
            character.runAction(.repeatForever(.sequence([
                bob(height: 0.1, duration: 0.6),
                .rotateBy(x: 0, y: .pi * 2, z: 0, duration: 0.9),
                .wait(duration: 1.2)
            ])))
            startBlinking()
        }
    }

    func jump() {
        let up = SCNAction.moveBy(x: 0, y: 0.6, z: 0, duration: 0.18)
        up.timingMode = .easeOut
        let down = SCNAction.moveBy(x: 0, y: -0.6, z: 0, duration: 0.3)
        down.timingMode = .easeIn
        let squash = SCNAction.sequence([.scale(to: 0.92, duration: 0.06), .scale(to: 1.0, duration: 0.12)])
        body.runAction(.sequence([.group([up, .rotateBy(x: 0, y: .pi * 2, z: 0, duration: 0.48)]), down, squash]))
    }

    private func bob(height: CGFloat, duration: TimeInterval) -> SCNAction {
        let up = SCNAction.moveBy(x: 0, y: height, z: 0, duration: duration / 2)
        up.timingMode = .easeInEaseOut
        let down = SCNAction.moveBy(x: 0, y: -height, z: 0, duration: duration / 2)
        down.timingMode = .easeInEaseOut
        return .sequence([up, down])
    }

    private func setEyes(closed: Bool) {
        for eye in eyes { eye.simdScale = SIMD3(1, closed ? 0.12 : 1.15, 0.6) }
    }

    private func setMouth(open: Bool) {
        (mouth.geometry as? SCNTorus)?.ringRadius = open ? 0.11 : 0.13
        mouth.simdScale = open ? SIMD3(1, 1, 1.1) : SIMD3(1, 1, 0.55)
    }

    private func startBlinking() {
        for eye in eyes {
            let blink = SCNAction.sequence([
                .wait(duration: 3.2, withRange: 2.0),
                .customAction(duration: 0.08) { node, _ in node.simdScale = SIMD3(1, 0.12, 0.6) },
                .wait(duration: 0.1),
                .customAction(duration: 0.08) { node, _ in node.simdScale = SIMD3(1, 1.15, 0.6) }
            ])
            eye.runAction(.repeatForever(blink))
        }
    }

    private func spawnZ() {
        let text = SCNText(string: "z", extrusionDepth: 0.5)
        text.font = UIFont.systemFont(ofSize: 10, weight: .heavy)
        text.flatness = 0.2
        text.firstMaterial = material(.white, roughness: 0.4)
        let node = SCNNode(geometry: text)
        node.scale = SCNVector3(0.03, 0.03, 0.03)
        zzz.addChildNode(node)
        node.runAction(.sequence([
            .group([.moveBy(x: -0.3, y: 0.9, z: 0, duration: 2.2), .fadeOut(duration: 2.2),
                    .scale(to: 0.05, duration: 2.2)]),
            .removeFromParentNode()
        ]))
    }
}
