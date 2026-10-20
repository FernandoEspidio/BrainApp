import SwiftUI

/// SPIKE (Lab): reads the last 60 days of Health and shows which connections they support,
/// before anything is wired into the real flow. Read-only: nothing is saved.
struct HealthProbeView: View {
    private static let daysBack = 60

    @Environment(AppModel.self) private var model
    @State private var source = HealthKitDataSource()
    @State private var state: ProbeState = .idle

    private enum ProbeState {
        case idle, reading
        case done(ProbeResult)
        case failed(String)
    }

    private struct ProbeResult {
        let days: [HealthDay]
        let connections: [HealthConnections.Result]
        let momentCount: Int
        let engineFindings: [String]
        /// False in demo mode: fictional check-ins are never mixed with real Health data.
        let usedCheckIns: Bool

        var timeInBedNights: Int { days.filter(\.sleepIsTimeInBed).count }
    }

    var body: some View {
        List {
            Section {
                Text("Reads the last \(Self.daysBack) days from Health and looks for connections that need no ratings. Nothing is saved or shared.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
                if HealthKitDataSource.isAvailable {
                    Button {
                        Task { await run() }
                    } label: {
                        if case .reading = state {
                            ProgressView()
                        } else {
                            Label("Read my Health data", systemImage: "heart.text.square")
                        }
                    }
                } else {
                    Text("Health isn't available on this device.")
                }
            }

            switch state {
            case .idle, .reading:
                EmptyView()
            case .failed(let message):
                Section { Label(message, systemImage: "exclamationmark.triangle") }
            case .done(let result):
                results(result)
            }
        }
        .navigationTitle("Health probe")
    }

    @ViewBuilder
    private func results(_ result: ProbeResult) -> some View {
        Section {
            ForEach(HealthConnections.coverage(result.days), id: \.metric) { row in
                LabeledContent(row.metric.label, value: "\(row.days) of \(result.days.count) days")
                if row.metric == .sleep, result.timeInBedNights > 0 {
                    LabeledContent("   only time in bed", value: "\(result.timeInBedNights) nights")
                }
            }
        } header: {
            Text("Data found")
        } footer: {
            Text("Empty rows can mean no data or no permission: Health doesn't say which. Time in bed comes from the iPhone's Sleep Schedule when there's no Watch, and overestimates sleep."
                 + (result.usedCheckIns ? "" : " Demo mode is on, so check-ins were left out."))
        }

        Section("Connections") {
            ForEach(result.connections) { connection in
                ConnectionResultRow(result: connection)
            }
        }

        Section {
            if result.engineFindings.isEmpty {
                Text("No discoveries.").foregroundStyle(Theme.inkSoft)
            }
            ForEach(result.engineFindings, id: \.self) { Text($0) }
        } header: {
            Text("Today's engine on Health moments")
        } footer: {
            Text("\(result.momentCount) moments (nights and workouts). Most rules need ratings, so few are expected here.")
        }

        Section {
            ShareLink(item: reportText(result)) {
                Label("Share results", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func run() async {
        state = .reading
        do {
            try await source.requestAuthorization()
            let calendar = Calendar.current
            let start = calendar.date(byAdding: .day, value: -Self.daysBack, to: calendar.startOfDay(for: .now)) ?? .now
            let checkIns = model.isDemoMode ? [] : model.repository.snapshot.activities
            let days = HealthConnections.addingCheckIns(checkIns, to: try await source.dailySummaries(since: start))
            let moments = try await source.fetchActivities(since: start)
            let report = InsightEngine().analyze(activities: moments, areas: LifeArea.builtIns)
            state = .done(ProbeResult(days: days, connections: HealthConnections.evaluate(days),
                                      momentCount: moments.count, engineFindings: report.discoveries.map(\.title),
                                      usedCheckIns: !model.isDemoMode))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Plain text to paste into a chat or a note.
    private func reportText(_ result: ProbeResult) -> String {
        var lines = ["BrainApp Health probe · last \(result.days.count) days", "", "Data found:"]
        for row in HealthConnections.coverage(result.days) {
            lines.append("- \(row.metric.label): \(row.days) days")
            if row.metric == .sleep, result.timeInBedNights > 0 {
                lines.append("  (\(result.timeInBedNights) nights only time in bed)")
            }
        }
        if !result.usedCheckIns { lines.append("(demo mode: check-ins left out)") }
        lines += ["", "Connections:"]
        for c in result.connections {
            lines.append("- \(c.rule.title): \(ConnectionResultRow.verdictLabel(c.verdict))")
            guard c.high.days + c.low.days > 0 else {
                lines.append("  No days with both numbers.")
                continue
            }
            lines.append("  \(c.high.label): \(c.rule.effect.format(c.high.mean)), \(c.high.days) days")
            lines.append("  \(c.low.label): \(c.rule.effect.format(c.low.mean)), \(c.low.days) days")
            if c.verdict != .notEnoughData {
                lines.append("  Difference \(c.differenceText), effect size \(c.effectSize.formatted(.number.precision(.fractionLength(2))))")
            }
        }
        lines += ["", "Engine on \(result.momentCount) Health moments: "
                  + (result.engineFindings.isEmpty ? "nothing" : result.engineFindings.joined(separator: "; "))]
        return lines.joined(separator: "\n")
    }
}

private struct ConnectionResultRow: View {
    let result: HealthConnections.Result

    static func verdictLabel(_ verdict: HealthConnections.Verdict) -> String {
        switch verdict {
        case .connection: return "Connection"
        case .tooWeak: return "Too weak"
        case .notEnoughData: return "Not enough data"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(result.rule.title).font(.headline)
                Spacer()
                Text(Self.verdictLabel(result.verdict))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(result.verdict == .connection ? Theme.pinkDeep : Theme.inkSoft)
            }
            if result.high.days + result.low.days == 0 {
                Text("No days with both numbers.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
            } else {
                group(result.high)
                group(result.low)
            }
            if result.verdict != .notEnoughData {
                Text("\(result.differenceText) · effect size \(result.effectSize.formatted(.number.precision(.fractionLength(2))))")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.vertical, 4)
    }

    private func group(_ group: HealthConnections.Group) -> some View {
        Text(group.days == 0
             ? "\(group.label): no days"
             : "\(group.label): \(result.rule.effect.format(group.mean)) · \(countLabel(group.days, "day", "days"))")
            .font(.subheadline)
            .foregroundStyle(Theme.inkSoft)
    }
}
