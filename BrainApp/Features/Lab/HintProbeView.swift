import SwiftUI

/// SPIKE (Lab): what Today would say for each goal, as one sentence, one number and one action.
/// Runs on your Health days, or on six made-up weeks from a Watch owner. Read-only: nothing is saved.
struct HintProbeView: View {
    private static let daysBack = 60

    @Environment(AppModel.self) private var model
    @State private var source = HealthKitDataSource()
    @State private var goal = Goal.focus
    @State private var data = DataChoice.sample
    @State private var myDays: [HealthDay]?
    @State private var reading = false
    @State private var message: String?

    private enum DataChoice: String, CaseIterable, Identifiable {
        case sample = "Sample Watch owner"
        case mine = "My data"

        var id: String { rawValue }
    }

    var body: some View {
        List {
            Section {
                Picker("Goal", selection: $goal) {
                    ForEach(Goal.allCases) { Text($0.label).tag($0) }
                }
                Picker("Data", selection: $data) {
                    ForEach(DataChoice.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if data == .mine, myDays == nil {
                    if HealthKitDataSource.isAvailable {
                        Button {
                            Task { await read() }
                        } label: {
                            if reading {
                                ProgressView()
                            } else {
                                Label("Read my Health data", systemImage: "heart.text.square")
                            }
                        }
                    } else {
                        Text("Health isn't available on this device.")
                    }
                }
            } footer: {
                Text(data == .sample
                     ? "Six made-up weeks with sleep, workouts and an answer to the daily question every day. Some connections are planted on purpose."
                     : "Your last \(Self.daysBack) days of Health. Until the daily question exists, “\(Goal.feel.label)” uses your check-ins on moments and the other goals have no answers.")
            }

            if let days = days(for: goal) {
                stateSections(HintEngine.state(for: goal, days: days))
                Section {
                    ShareLink(item: reportText) {
                        Label("Share results (all goals)", systemImage: "square.and.arrow.up")
                    }
                }
            }

            if let message {
                Section { Label(message, systemImage: "exclamationmark.triangle") }
            }
        }
        .navigationTitle("Hints")
    }

    @ViewBuilder
    private func stateSections(_ state: HintState) -> some View {
        Section("What Today would say") {
            if case .hint(let hint, _) = state {
                HintRow(hint: hint)
            } else {
                Text(state.headline(for: goal))
                    .font(.title3.weight(.semibold))
            }
        }
        if case .hint(_, let others) = state, !others.isEmpty {
            Section("Also found") {
                ForEach(others) { HintRow(hint: $0) }
            }
        }
    }

    private func days(for goal: Goal) -> [HealthDay]? {
        switch data {
        case .sample:
            return SampleHealthDays.watchOwner(goal: goal)
        case .mine:
            guard goal == .feel else { return myDays }
            return myDays?.map { day in
                var day = day
                day.answer = day.feeling
                return day
            }
        }
    }

    private func read() async {
        reading = true
        defer { reading = false }
        do {
            try await source.requestAuthorization()
            let calendar = Calendar.current
            let start = calendar.date(byAdding: .day, value: -Self.daysBack, to: calendar.startOfDay(for: .now)) ?? .now
            // Demo mode: fictional check-ins are never mixed with real Health data.
            let checkIns = model.isDemoMode ? [] : model.repository.snapshot.activities
            myDays = HealthConnections.addingCheckIns(checkIns, to: try await source.dailySummaries(since: start))
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    /// Plain text to paste into a chat: every goal, so one share is enough to judge them all.
    private var reportText: String {
        var lines = ["BrainApp hints · \(data.rawValue)"]
        for goal in Goal.allCases {
            guard let days = days(for: goal) else { continue }
            let state = HintEngine.state(for: goal, days: days)
            lines += ["", "\(goal.label) (measured by: \(HintEngine.outcome(for: goal, days: days).label))"]
            guard case .hint(let hint, let others) = state else {
                lines.append("  \(state.headline(for: goal))")
                continue
            }
            for hint in [hint] + others {
                lines.append("- [\(hint.strength.label)] \(hint.sentence)")
                lines.append("  \(hint.number)" + (hint.action.map { " → \($0)" } ?? ""))
            }
        }
        return lines.joined(separator: "\n")
    }
}

private struct HintRow: View {
    let hint: Hint

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(hint.strength.label.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.pinkDeep)
            Text(hint.sentence)
                .font(.title3.weight(.semibold))
            Text(hint.number)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
            if let action = hint.action {
                Label(action, systemImage: "arrow.right.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.pinkDeep)
            }
        }
        .padding(.vertical, 4)
    }
}
