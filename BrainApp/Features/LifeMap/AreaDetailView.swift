import Charts
import SwiftUI

/// When an area is selected: activities, data sources, trend and relevant relationships.
struct AreaDetailView: View {
    @Environment(AppModel.self) private var model
    let areaID: String
    @State private var editing: Activity?
    @State private var connectionTarget: MapConnection?

    var body: some View {
        let repo = model.repository
        let area = repo.area(id: areaID)
        let items = repo.snapshot.activities.filter { $0.areaID == areaID }.sorted { $0.date > $1.date }
        let summary = repo.areaSummaries().first { $0.area.id == areaID }
        let weeks = repo.weeklyCounts(areaID: areaID)
        let related = repo.connections(involving: areaID)

        List {
            Section {
                Picker("Priority for you", selection: Binding(
                    get: { repo.priority(for: areaID) },
                    set: { repo.setPriority($0, for: areaID) }
                )) {
                    ForEach(Priority.allCases) { priority in
                        Text(priority.label).tag(priority)
                    }
                }
            } footer: {
                Text("The map compares what you log with what you decide matters. There is no ideal ratio.")
            }

            Section("Trend") {
                Chart(weeks) { week in
                    BarMark(
                        x: .value("Week", week.weekStart, unit: .weekOfYear),
                        y: .value("Moments", week.count)
                    )
                    .foregroundStyle(area.color)
                }
                .chartYAxisLabel("Moments per week")
                .frame(height: 160)
                .accessibilityLabel("Moments per week over the last 8 weeks")

                if let summary {
                    Text("Last 14 days: \(summary.recentCount) · before that: \(summary.previousCount)")
                        .font(.subheadline)
                }
            }

            Section("Data sources") {
                if let summary, !summary.sources.isEmpty {
                    ForEach(summary.sources.sorted { $0.key.rawValue < $1.key.rawValue }, id: \.key) { entry in
                        LabeledContent(entry.key.label, value: countLabel(entry.value, "moment", "moments"))
                    }
                } else {
                    Text("No data available.").foregroundStyle(.secondary)
                }
            }

            if !related.isEmpty {
                Section("Observed relationships") {
                    ForEach(related) { connection in
                        Button {
                            connectionTarget = connection
                        } label: {
                            Label("Association with \(repo.area(id: connection.other(than: areaID)).name)", systemImage: "link")
                        }
                    }
                }
            }

            Section("Moments") {
                if items.isEmpty {
                    Text("No moments in this area yet.").foregroundStyle(.secondary)
                }
                ForEach(items) { activity in
                    Button {
                        editing = activity
                    } label: {
                        ActivityRow(activity: activity, area: area)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    repo.deleteActivities(Set(offsets.map { items[$0].id }))
                }
            }
        }
        .navigationTitle(area.name)
        .sheet(item: $editing) { activity in LogActivitySheet(existing: activity) }
        .sheet(item: $connectionTarget) { connection in ConnectionDetailSheet(connection: connection) }
    }
}
