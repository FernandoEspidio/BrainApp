import SwiftUI

/// Create, edit and delete entries. Also used to review the entries behind a discovery.
struct ActivityListView: View {
    @Environment(AppModel.self) private var model
    var filterIDs: Set<UUID>? = nil
    var title = "All moments"

    @State private var editing: Activity?
    @State private var showNew = false

    var body: some View {
        let repo = model.repository
        let calendar = Calendar.current
        let items = repo.snapshot.activities
            .filter { filterIDs?.contains($0.id) ?? true }
            .sorted { $0.date > $1.date }
        let days = Set(items.map { calendar.startOfDay(for: $0.date) }).sorted(by: >)

        Group {
            if items.isEmpty {
                ContentUnavailableView("No moments yet", systemImage: "tray",
                                       description: Text("Your phone will add them as your day goes."))
            } else {
                List {
                    if repo.isDemo {
                        Section { DemoBanner() }
                    }
                    ForEach(days, id: \.self) { day in
                        let dayItems = items.filter { calendar.isDate($0.date, inSameDayAs: day) }
                        Section(day.formatted(date: .complete, time: .omitted)) {
                            ForEach(dayItems) { activity in
                                Button {
                                    editing = activity
                                } label: {
                                    ActivityRow(activity: activity, area: repo.area(id: activity.areaID))
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete { offsets in
                                repo.deleteActivities(Set(offsets.map { dayItems[$0].id }))
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            if filterIDs == nil {
                Button {
                    showNew = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editing) { activity in LogActivitySheet(existing: activity) }
        .sheet(isPresented: $showNew) { LogActivitySheet(existing: nil) }
    }
}
