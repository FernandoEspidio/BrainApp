import DeviceActivity
import Foundation

/// SPIKE: the only Screen Time path that hands data to BrainApp. iOS wakes this extension when a
/// watched category passes a threshold; it writes one line to the app group shared with the app,
/// which the Screen Time probe reads. Event names are set by `ScreenTimeProbe` in the app.
/// The class name must match NSExtensionPrincipalClass in Info.plist.
class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        SharedLog.append("dayStart")
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        SharedLog.append(event.rawValue)
    }
}

/// Lines "timestamp|event" in the app group `group.<app bundle ID>`.
enum SharedLog {
    /// Same key as `ScreenTimeProbe.logKey` in the app.
    static let key = "screenTime.log"

    static func append(_ event: String) {
        // This extension's ID is "<app bundle ID>.ScreenTimeMonitor".
        guard let id = Bundle.main.bundleIdentifier,
              let defaults = UserDefaults(suiteName: "group." + id.split(separator: ".").dropLast().joined(separator: "."))
        else { return }
        var lines = defaults.stringArray(forKey: key) ?? []
        lines.append("\(Date.now.timeIntervalSince1970)|\(event)")
        defaults.set(Array(lines.suffix(500)), forKey: key)
    }
}
