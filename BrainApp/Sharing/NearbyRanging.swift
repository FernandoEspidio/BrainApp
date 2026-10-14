import Foundation
import NearbyInteraction

/// TEST: wraps Nearby Interaction (UWB) to measure distance and, when the hardware allows it,
/// direction to a connected friend. The discovery tokens travel over the existing P2P connection.
///
/// Reality check (Oct 2026):
/// - Distance: iPhone 11 or later with a UWB chip (not iPhone SE / 16e).
/// - Direction: inconsistent. Several iPhone 14+ models report no direction unless camera
///   assistance (ARKit) is on. Treat "aim to throw" as a nice-to-have, never a requirement.
/// Requires Info.plist: NSNearbyInteractionUsageDescription (+ NSCameraUsageDescription for camera assistance).
@MainActor
final class NearbyRanging: NSObject, NISessionDelegate {
    struct Reading: Equatable {
        var distance: Float?
        /// Radians, 0 = straight ahead, negative = left.
        var horizontalAngle: Float?
        var direction: SIMD3<Float>?
    }

    static var isSupported: Bool {
        NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
    }

    static var capabilitySummary: String {
        let caps = NISession.deviceCapabilities
        return "Distance \(caps.supportsPreciseDistanceMeasurement ? "✓" : "✗") · Direction \(caps.supportsDirectionMeasurement ? "✓" : "✗") · Camera assist \(caps.supportsCameraAssistance ? "✓" : "✗")"
    }

    var onReading: ((Reading) -> Void)?
    var onLog: ((String) -> Void)?

    private var session: NISession?
    private var peerToken: NIDiscoveryToken?
    private var useCameraAssistance = false

    /// Starts a session and returns our token, archived, to send to the friend.
    func start(cameraAssistance: Bool) -> Data? {
        guard Self.isSupported else {
            onLog?("Nearby Interaction not supported on this iPhone")
            return nil
        }
        useCameraAssistance = cameraAssistance && NISession.deviceCapabilities.supportsCameraAssistance
        let session = NISession()
        session.delegate = self
        session.delegateQueue = .main
        self.session = session
        guard let token = session.discoveryToken,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else {
            onLog?("Couldn't get our discovery token")
            return nil
        }
        return data
    }

    /// Called when the friend's token arrives.
    func connect(peerTokenData: Data) {
        guard let session else { return }
        guard let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: peerTokenData) else {
            onLog?("Couldn't read friend's token")
            return
        }
        peerToken = token
        run(session, token: token)
    }

    func stop() {
        session?.invalidate()
        session = nil
        peerToken = nil
    }

    private func run(_ session: NISession, token: NIDiscoveryToken) {
        let configuration = NINearbyPeerConfiguration(peerToken: token)
        if useCameraAssistance {
            configuration.isCameraAssistanceEnabled = true
        }
        session.run(configuration)
        onLog?("Ranging started\(useCameraAssistance ? " (camera assistance on)" : "")")
    }

    // MARK: - NISessionDelegate (delivered on the main queue)

    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let object = nearbyObjects.first else { return }
        let reading = Reading(distance: object.distance, horizontalAngle: object.horizontalAngle, direction: object.direction)
        MainActor.assumeIsolated { self.onReading?(reading) }
    }

    nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        MainActor.assumeIsolated {
            self.onLog?(reason == .timeout ? "Friend out of range (timeout)" : "Friend stopped ranging")
            self.onReading?(Reading())
            if reason == .timeout, let token = self.peerToken, let current = self.session {
                self.run(current, token: token) // try again
            }
        }
    }

    nonisolated func sessionWasSuspended(_ session: NISession) {
        MainActor.assumeIsolated { self.onLog?("Ranging suspended (app in background?)") }
    }

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        MainActor.assumeIsolated {
            self.onLog?("Ranging resumed")
            if let token = self.peerToken { self.run(session, token: token) }
        }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        MainActor.assumeIsolated { self.onLog?("Ranging stopped: \(error.localizedDescription)") }
    }
}
