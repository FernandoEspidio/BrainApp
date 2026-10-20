#if os(iOS)
import DeviceActivity
import FamilyControls
import ManagedSettings
import SwiftUI

extension DeviceActivityReport.Context {
    /// Drawn by the ScreenTimeReport extension, which defines the same name.
    static let totalActivity = Self("Total Activity")
}

/// SPIKE (Lab): what Screen Time lets BrainApp see, on a real iPhone. Two paths:
/// - Alerts: the ScreenTimeMonitor extension writes "15/30/60/120 min reached" for chosen categories.
///   BrainApp's code can use these, but only from the day watching starts.
/// - Report: iOS draws the real daily numbers inside this screen. BrainApp's code can't read them.
struct ScreenTimeProbeView: View {
    @ObservedObject private var center = AuthorizationCenter.shared
    @State private var selection = ScreenTimeProbe.savedSelection()
    @State private var showPicker = false
    @State private var alerts: [ScreenTimeProbe.Alert] = []
    @State private var watched = ScreenTimeProbe.watchedCategories()
    @State private var message: String?

    var body: some View {
        List {
            Section {
                Text("Checks what Screen Time lets BrainApp see. Works only on a real iPhone. Nothing is shared.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
                LabeledContent("Access", value: statusLabel)
                if center.authorizationStatus != .approved {
                    Button("Allow Screen Time access") { Task { await requestAccess() } }
                }
            } header: {
                Text("1 · Access")
            }

            if center.authorizationStatus == .approved {
                Section {
                    Button("Choose categories (\(selection.categoryTokens.count) chosen)") { showPicker = true }
                    Button("Start watching") { startWatching() }
                        .disabled(selection.categoryTokens.isEmpty)
                    ForEach(Array(watched.enumerated()), id: \.offset) { index, token in
                        Label(token).badge("#\(index + 1)")
                    }
                } header: {
                    Text("2 · Watch categories")
                } footer: {
                    Text("Pick up to \(ScreenTimeProbe.maxCategories) categories, for example Social, Entertainment, Reading and Productivity. BrainApp gets an alert when each one passes \(ScreenTimeProbe.thresholdsText) in a day, counted from midnight.")
                }

                Section {
                    if alerts.isEmpty {
                        Text("None yet. Use a watched category for 15 minutes, then pull to refresh.")
                            .foregroundStyle(Theme.inkSoft)
                    }
                    ForEach(alerts) { alert in
                        HStack {
                            if let index = alert.categoryIndex, watched.indices.contains(index) {
                                Label(watched[index])
                            } else {
                                Text(alert.label)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                if let minutes = alert.minutes { Text("\(minutes) min").bold() }
                                Text(alert.date, format: .dateTime.day().month().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(Theme.inkSoft)
                            }
                        }
                    }
                } header: {
                    Text("3 · Alerts BrainApp received")
                } footer: {
                    Text("This is the only Screen Time data BrainApp's code can use.")
                }

                Section {
                    DeviceActivityReport(.totalActivity, filter: ScreenTimeProbe.lastWeekFilter())
                        .frame(minHeight: 420)
                } header: {
                    Text("4 · Last 7 days, drawn by iOS")
                } footer: {
                    Text("These numbers live only inside the report. BrainApp's code can't read them, so they can't feed connections. Take a screenshot to share them.")
                }

                Section {
                    ShareLink(item: reportText) {
                        Label("Share results", systemImage: "square.and.arrow.up")
                    }
                }
            }

            if let message {
                Section { Label(message, systemImage: "exclamationmark.triangle") }
            }
        }
        .navigationTitle("Screen Time probe")
        .familyActivityPicker(isPresented: $showPicker, selection: $selection)
        .onChange(of: selection) { _, newValue in ScreenTimeProbe.save(newValue) }
        .onAppear { alerts = ScreenTimeProbe.readAlerts() }
        .refreshable { alerts = ScreenTimeProbe.readAlerts() }
    }

    private var statusLabel: String {
        switch center.authorizationStatus {
        case .approved: return "Allowed"
        case .denied: return "Denied"
        case .notDetermined: return "Not asked yet"
        @unknown default: return "Unknown"
        }
    }

    private func requestAccess() async {
        do {
            try await center.requestAuthorization(for: .individual)
            message = nil
        } catch {
            message = "Access failed: \(error.localizedDescription)"
        }
    }

    private func startWatching() {
        do {
            watched = try ScreenTimeProbe.startWatching(selection)
            message = nil
            alerts = ScreenTimeProbe.readAlerts()
        } catch {
            message = "Couldn't start watching: \(error.localizedDescription)"
        }
    }

    /// Plain text to paste into a chat. Category names can't be turned into text: iOS only draws them.
    private var reportText: String {
        var lines = ["BrainApp Screen Time probe", "Access: \(statusLabel)",
                     "Watching \(watched.count) categories (names are hidden from the app; #1, #2…)", "",
                     "Alerts received (\(alerts.filter { $0.minutes != nil }.count)):"]
        for alert in alerts {
            let time = alert.date.formatted(.dateTime.day().month().hour().minute())
            if let index = alert.categoryIndex, let minutes = alert.minutes {
                lines.append("- \(time) · category #\(index + 1) · \(minutes) min")
            } else {
                lines.append("- \(time) · \(alert.label)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// Watching setup and the alert log shared with the ScreenTimeMonitor extension.
enum ScreenTimeProbe {
    static let activity = DeviceActivityName("brainapp.daily")
    static let thresholds = [15, 30, 60, 120]
    static let maxCategories = 4
    /// Same key as `SharedLog.key` in the extension.
    static let logKey = "screenTime.log"
    private static let selectionKey = "screenTime.selection"
    private static let watchedKey = "screenTime.watched"

    static var thresholdsText: String {
        thresholds.map { "\($0)" }.joined(separator: ", ") + " minutes"
    }

    struct Alert: Identifiable {
        let id = UUID()
        let date: Date
        /// Event names are "c<index>.<minutes>"; anything else (like "dayStart") is shown as is.
        let categoryIndex: Int?
        let minutes: Int?
        let label: String
    }

    /// The app group shared with the extension: `group.<app bundle ID>`.
    private static var shared: UserDefaults? {
        Bundle.main.bundleIdentifier.flatMap { UserDefaults(suiteName: "group.\($0)") }
    }

    static func savedSelection() -> FamilyActivitySelection {
        UserDefaults.standard.data(forKey: selectionKey)
            .flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) } ?? FamilyActivitySelection()
    }

    static func save(_ selection: FamilyActivitySelection) {
        UserDefaults.standard.set(try? JSONEncoder().encode(selection), forKey: selectionKey)
    }

    /// The categories being watched, in the order their event names use.
    static func watchedCategories() -> [ActivityCategoryToken] {
        UserDefaults.standard.data(forKey: watchedKey)
            .flatMap { try? JSONDecoder().decode([ActivityCategoryToken].self, from: $0) } ?? []
    }

    /// Watches each chosen category every day, midnight to midnight. Today's earlier use counts too,
    /// so thresholds already passed arrive right away.
    static func startWatching(_ selection: FamilyActivitySelection) throws -> [ActivityCategoryToken] {
        let categories = Array(selection.categoryTokens.prefix(maxCategories))
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for (index, token) in categories.enumerated() {
            for minutes in thresholds {
                events[DeviceActivityEvent.Name("c\(index).\(minutes)")] = DeviceActivityEvent(
                    categories: [token], threshold: DateComponents(minute: minutes), includesPastActivity: true)
            }
        }
        let schedule = DeviceActivitySchedule(intervalStart: DateComponents(hour: 0, minute: 0),
                                              intervalEnd: DateComponents(hour: 23, minute: 59), repeats: true)
        let center = DeviceActivityCenter()
        center.stopMonitoring([activity])
        try center.startMonitoring(activity, during: schedule, events: events)
        UserDefaults.standard.set(try? JSONEncoder().encode(categories), forKey: watchedKey)
        shared?.removeObject(forKey: logKey)
        return categories
    }

    static func readAlerts() -> [Alert] {
        let lines = shared?.stringArray(forKey: logKey) ?? []
        return lines.compactMap { line -> Alert? in
            let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let seconds = Double(parts[0]) else { return nil }
            let event = parts[1]
            let fields = event.dropFirst().split(separator: ".").compactMap { Int($0) }
            let isCategory = event.hasPrefix("c") && fields.count == 2
            return Alert(date: Date(timeIntervalSince1970: seconds),
                         categoryIndex: isCategory ? fields[0] : nil,
                         minutes: isCategory ? fields[1] : nil,
                         label: event == "dayStart" ? "New day started" : event)
        }
        .reversed()
    }

    static func lastWeekFilter() -> DeviceActivityFilter {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: .now)) ?? .now
        return DeviceActivityFilter(segment: .daily(during: DateInterval(start: start, end: .now)),
                                    users: .all, devices: .init([.iPhone]))
    }
}
#endif
