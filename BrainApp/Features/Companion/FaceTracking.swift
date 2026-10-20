import ARKit
import Foundation
import Observation

/// The few facial values the brain uses (0…1, angles in radians). ~50 bytes per frame:
/// recording these instead of video is what makes sharing "brain animojis" cheap later.
struct FacePose: Hashable, Codable, Sendable {
    /// Eyes as they appear ON SCREEN (mirrored like a selfie): left = screen left.
    var leftEyeOpen: Float = 1
    var rightEyeOpen: Float = 1
    var jawOpen: Float = 0
    var smile: Float = 0
    var browUp: Float = 0
    var browDown: Float = 0
    var cheekPuff: Float = 0
    var tongueOut: Float = 0
    var pucker: Float = 0
    var headRoll: Float = 0
    var headYaw: Float = 0
    var headPitch: Float = 0

    /// Exponential smoothing to remove jitter.
    func blended(toward target: FacePose, amount t: Float) -> FacePose {
        func mix(_ a: Float, _ b: Float) -> Float { a + (b - a) * t }
        return FacePose(
            leftEyeOpen: mix(leftEyeOpen, target.leftEyeOpen), rightEyeOpen: mix(rightEyeOpen, target.rightEyeOpen),
            jawOpen: mix(jawOpen, target.jawOpen), smile: mix(smile, target.smile),
            browUp: mix(browUp, target.browUp), browDown: mix(browDown, target.browDown),
            cheekPuff: mix(cheekPuff, target.cheekPuff), tongueOut: mix(tongueOut, target.tongueOut),
            pucker: mix(pucker, target.pucker), headRoll: mix(headRoll, target.headRoll),
            headYaw: mix(headYaw, target.headYaw), headPitch: mix(headPitch, target.headPitch)
        )
    }
}

/// TEST: runs ARKit face tracking (front camera, on device, no Internet) and publishes a FacePose.
/// The camera image is never shown or stored. Requires NSCameraUsageDescription.
/// Works on iPhones with Face ID (TrueDepth) or an A12 chip or later.
@MainActor
@Observable
final class FaceTracker {
    static var isSupported: Bool { ARFaceTrackingConfiguration.isSupported }

    private(set) var pose = FacePose()
    private(set) var isTracking = false
    private(set) var status = "Not started"
    var smoothing: Float = 0.5
    var mirrored = true

    @ObservationIgnored private let session = ARSession()
    @ObservationIgnored private let relay = ARDelegateRelay()
    @ObservationIgnored private var neutralYaw: Float = 0
    @ObservationIgnored private var neutralPitch: Float = 0
    @ObservationIgnored private var neutralRoll: Float = 0
    @ObservationIgnored private var raw = FacePose()

    func start() {
        guard Self.isSupported else {
            status = "Face tracking isn't supported on this device"
            return
        }
        relay.onFace = { [weak self] face in self?.update(with: face) }
        relay.onStatus = { [weak self] text in
            self?.status = text
            self?.isTracking = false
        }
        session.delegate = relay
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = false
        configuration.maximumNumberOfTrackedFaces = 1
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        status = "Looking for your face…"
    }

    func stop() {
        session.pause()
        isTracking = false
        status = "Paused"
    }

    /// Use the current head position as "straight ahead".
    func calibrate() {
        neutralYaw = raw.headYaw
        neutralPitch = raw.headPitch
        neutralRoll = raw.headRoll
    }

    private func update(with face: ARFaceAnchor) {
        guard face.isTracked else {
            isTracking = false
            status = "Face lost — look at the screen"
            return
        }
        isTracking = true
        status = "Tracking"

        let shapes = face.blendShapes
        func value(_ key: ARFaceAnchor.BlendShapeLocation) -> Float { shapes[key]?.floatValue ?? 0 }

        // ARKit's "left" is the user's left. As a mirror, the user's left eye is on the screen's right.
        let userLeftOpen = 1 - value(.eyeBlinkLeft)
        let userRightOpen = 1 - value(.eyeBlinkRight)

        // Head angles from the face transform (face +Z points toward the camera).
        let m = face.transform
        let forward = SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z)
        let up = SIMD3<Float>(m.columns.1.x, m.columns.1.y, m.columns.1.z)
        let side = SIMD3<Float>(m.columns.0.x, m.columns.0.y, m.columns.0.z)
        let yaw = atan2(forward.x, forward.z)
        let pitch = asin(max(-1, min(1, -forward.y)))
        let roll = atan2(side.y, up.y)

        var target = FacePose(
            leftEyeOpen: mirrored ? userRightOpen : userLeftOpen,
            rightEyeOpen: mirrored ? userLeftOpen : userRightOpen,
            jawOpen: value(.jawOpen),
            smile: (value(.mouthSmileLeft) + value(.mouthSmileRight)) / 2,
            browUp: value(.browInnerUp),
            browDown: (value(.browDownLeft) + value(.browDownRight)) / 2,
            cheekPuff: value(.cheekPuff),
            tongueOut: value(.tongueOut),
            pucker: value(.mouthPucker),
            headRoll: roll,
            headYaw: yaw,
            headPitch: pitch
        )
        raw = target
        target.headYaw = (mirrored ? -1 : 1) * (yaw - neutralYaw)
        target.headRoll = (mirrored ? -1 : 1) * (roll - neutralRoll)
        target.headPitch = pitch - neutralPitch

        pose = pose.blended(toward: target, amount: 1 - smoothing * 0.85)
    }
}

/// Small NSObject bridge for ARSessionDelegate (keeps the observable model a plain class).
/// ARKit delivers these callbacks on the main queue by default.
@MainActor
final class ARDelegateRelay: NSObject, ARSessionDelegate {
    var onFace: ((ARFaceAnchor) -> Void)?
    var onStatus: ((String) -> Void)?

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        MainActor.assumeIsolated {
            guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
            self.onFace?(face)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        MainActor.assumeIsolated { self.onStatus?("Error: \(error.localizedDescription)") }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        MainActor.assumeIsolated { self.onStatus?("Interrupted") }
    }
}
