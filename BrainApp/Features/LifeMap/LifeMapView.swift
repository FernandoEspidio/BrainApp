import SwiftUI

struct AreaRoute: Hashable {
    let id: String
}

/// Life map: radial overview + list alternative (accessible and for large text).
/// Extra connections only appear when an area is selected.
struct LifeMapView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showList = false
    @State private var selectedAreaID: String?
    @State private var connectionTarget: MapConnection?
    @State private var showLegend = false

    var body: some View {
        let repo = model.repository
        let summaries = repo.areaSummaries()
        let useList = showList || dynamicTypeSize.isAccessibilitySize

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if repo.isDemo { DemoBanner() }

                if !dynamicTypeSize.isAccessibilitySize {
                    Picker("View", selection: $showList) {
                        Text("Map").tag(false)
                        Text("List").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                if useList {
                    AreaListContent(summaries: summaries)
                } else {
                    RadialMapView(
                        summaries: summaries,
                        connections: repo.report.connections,
                        selectedAreaID: selectedAreaID,
                        appearance: repo.snapshot.companion,
                        stage: repo.companionStage,
                        onSelect: { id in selectedAreaID = (selectedAreaID == id) ? nil : id }
                    )
                    .frame(height: 380)

                    selectionPanel(repo: repo, summaries: summaries)
                }
            }
            .padding()
        }
        .background(Theme.cream.ignoresSafeArea())
        .navigationTitle("Life map")
        .toolbar {
            Button {
                showLegend = true
            } label: {
                Label("How to read the map", systemImage: "questionmark.circle")
            }
        }
        .sheet(isPresented: $showLegend) { MapLegendSheet() }
        .sheet(item: $connectionTarget) { connection in ConnectionDetailSheet(connection: connection) }
    }

    @ViewBuilder
    private func selectionPanel(repo: LocalRepository, summaries: [AreaSummary]) -> some View {
        if let id = selectedAreaID, let summary = summaries.first(where: { $0.area.id == id }) {
            let related = repo.connections(involving: id)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TintedIcon(symbol: summary.area.symbol, tint: summary.area.tint, size: 36)
                    Text(summary.area.name).font(.headline).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(countLabel(summary.recentCount, "moment", "moments"))
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                }
                if !related.isEmpty {
                    ForEach(related) { connection in
                        Button {
                            connectionTarget = connection
                        } label: {
                            Label("Association with \(repo.area(id: connection.other(than: id)).name)", systemImage: "link")
                        }
                    }
                }
                NavigationLink(value: AreaRoute(id: id)) {
                    Label("See moments", systemImage: "chevron.right.circle")
                }
                .foregroundStyle(Theme.pinkDeep)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        } else {
            Text("Tap an area. Bigger = more moments lately.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
                .frame(maxWidth: .infinity)
        }
    }
}

struct AreaListContent: View {
    let summaries: [AreaSummary]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(summaries) { summary in
                NavigationLink(value: AreaRoute(id: summary.area.id)) {
                    HStack(spacing: 12) {
                        TintedIcon(symbol: summary.area.symbol, tint: summary.area.tint, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(summary.area.name).font(.headline)
                            Text("\(countLabel(summary.recentCount, "moment", "moments")) in 14 days")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }
}

struct MapLegendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Lab.parkedFeaturesKey) private var showsParked = false

    var body: some View {
        NavigationStack {
            List {
                Section("What each element means") {
                    Label("Each circle is an area, always with an icon and a name.", systemImage: "circle")
                    Label("Size: number of entries in the last 14 days (stops growing after 20).", systemImage: "arrow.up.left.and.arrow.down.right")
                    if showsParked {
                        Label("Bold outline: you marked the area as Important or Very important.", systemImage: "circle.circle")
                    }
                    Label("Thin gray lines: they only link each area to you; they mean nothing else.", systemImage: "line.diagonal")
                    Label("Dashed colored line: an association observed in your entries. It appears when you select an area. It is not a proven cause.", systemImage: "link")
                }
                if showsParked {
                    Section("Balance") {
                        Text("There is no universal balance score. The map compares what you log with the priorities you choose; areas don't need to be the same size.")
                    }
                }
            }
            .navigationTitle("How to read the map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
