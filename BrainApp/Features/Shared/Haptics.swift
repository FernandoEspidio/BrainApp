import CoreHaptics
import UIKit

/// A rumble that builds up while the portal charges, then a strong "whoosh" when the brain goes through.
/// Uses Core Haptics when the device has it (no-op on the simulator and on iPads).
@MainActor
final class PortalHaptics {
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.isAutoShutdownEnabled = true
        engine?.resetHandler = { [weak self] in
            MainActor.assumeIsolated {
                try? self?.engine?.start()
                self?.player = nil
            }
        }
    }

    /// 0…1: how strong the pull feels right now.
    func charge(_ level: Double) {
        guard let engine else { return }
        do {
            if player == nil {
                try engine.start()
                let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                ], relativeTime: 0, duration: 30)
                let pattern = try CHHapticPattern(events: [event], parameters: [])
                player = try engine.makeAdvancedPlayer(with: pattern)
                try player?.start(atTime: CHHapticTimeImmediate)
            }
            let level = Float(min(max(level, 0), 1))
            try player?.sendParameters([
                CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: 0.15 + level * 0.85, relativeTime: 0),
                CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: 0.1 + level * 0.6, relativeTime: 0)
            ], atTime: CHHapticTimeImmediate)
        } catch {
            player = nil
        }
    }

    func release() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
    }

    func whoosh() {
        release()
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
