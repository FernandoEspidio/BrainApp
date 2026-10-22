import ARKit
import AVFoundation
import Foundation
import Observation

/// Runs ARKit face tracking (front camera, on device, no Internet) and publishes a FacePose.
/// The camera image is never shown or stored. Requires NSCameraUsageDescription.
/// Works on iPhones with Face ID (TrueDepth) or an A12 chip or later.
///
/// Performance: the pose changes ~60 times a second, so it is NOT observable (`livePose`):
/// brains read it at draw time inside their own TimelineView. Only `isTracking`/`status` notify views,
/// and only when they actually change. The session runs at the lowest video format available.
@MainActor
@Observable
final class FaceTracker {
    static var isSupported: Bool { ARFaceTrackingConfiguration.isSupported }

    enum Access { case allowed, notAsked, denied, unsupported }

    static var access: Access {
        guard isSupported else { return .unsupported }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .allowed
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }

    /// Latest smoothed pose (read at draw time; not observed on purpose).
    @ObservationIgnored private(set) var livePose = FacePose()
    var pose: FacePose { livePose }
    private(set) var isTracking = false
    private(set) var isRunning = false
    private(set) var status = "Not started"
    /// Light smoothing here; the brain adds frame-rate-independent smoothing when it draws.
    var smoothing: Float = 0.2
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
            self?.setTracking(false)
        }
        session.delegate = relay
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = false
        configuration.maximumNumberOfTrackedFaces = 1
        configuration.isWorldTrackingEnabled = false
        // Smallest frames, but never below 60 fps: a low frame rate is what makes the mirror feel choppy.
        // (We only need blend shapes, never the image, so resolution is the part we can drop.)
        let formats = ARFaceTrackingConfiguration.supportedVideoFormats
        let fluid = formats.filter { $0.framesPerSecond >= 60 }
        if let cheapest = (fluid.isEmpty ? formats : fluid).min(by: {
            $0.imageResolution.width * $0.imageResolution.height < $1.imageResolution.width * $1.imageResolution.height
        }) {
            configuration.videoFormat = cheapest
        }
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
        status = "Looking for your face…"
    }

    func stop() {
        guard isRunning else { return }
        session.pause()
        isRunning = false
        setTracking(false)
        status = "Paused"
    }

    private func setTracking(_ value: Bool) {
        if isTracking != value { isTracking = value }
    }

    /// Use the current head position as "straight ahead".
    func calibrate() {
        neutralYaw = raw.headYaw
        neutralPitch = raw.headPitch
        neutralRoll = raw.headRoll
    }

    private func update(with face: ARFaceAnchor) {
        guard face.isTracked else {
            if isTracking {
                setTracking(false)
                status = "Face lost — look at the screen"
            }
            return
        }
        if !isTracking {
            setTracking(true)
            status = "Tracking"
        }

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

        // Gaze: how much both eyes look toward the user's left/right, up/down.
        let towardUserLeft = (value(.eyeLookOutLeft) + value(.eyeLookInRight)) / 2
        let towardUserRight = (value(.eyeLookInLeft) + value(.eyeLookOutRight)) / 2
        let lookUp = (value(.eyeLookUpLeft) + value(.eyeLookUpRight)) / 2
        let lookDown = (value(.eyeLookDownLeft) + value(.eyeLookDownRight)) / 2
        // Same side convention as the eyes above: as a mirror, the user's left is the screen's right.
        let gazeUser = towardUserRight - towardUserLeft
        let userLeftBrow = value(.browOuterUpLeft)
        let userRightBrow = value(.browOuterUpRight)
        let mouthTowardUserLeft = value(.mouthLeft)
        let mouthTowardUserRight = value(.mouthRight)
        let mouthUser = mouthTowardUserRight - mouthTowardUserLeft

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
            headPitch: pitch,
            gazeX: min(max((mirrored ? -gazeUser : gazeUser) * 1.6, -1), 1),
            gazeY: min(max((lookDown - lookUp) * 1.6, -1), 1),
            leftBrowRaise: mirrored ? userRightBrow : userLeftBrow,
            rightBrowRaise: mirrored ? userLeftBrow : userRightBrow,
            squint: (value(.eyeSquintLeft) + value(.eyeSquintRight)) / 2,
            eyeWide: (value(.eyeWideLeft) + value(.eyeWideRight)) / 2,
            frown: (value(.mouthFrownLeft) + value(.mouthFrownRight)) / 2,
            mouthShift: min(max((mirrored ? -mouthUser : mouthUser) * 1.5, -1), 1),
            funnel: value(.mouthFunnel)
        )
        raw = target
        target.headYaw = (mirrored ? -1 : 1) * (yaw - neutralYaw)
        target.headRoll = (mirrored ? -1 : 1) * (roll - neutralRoll)
        target.headPitch = pitch - neutralPitch

        livePose = livePose.blended(toward: target, amount: 1 - smoothing * 0.85).clamped()
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
