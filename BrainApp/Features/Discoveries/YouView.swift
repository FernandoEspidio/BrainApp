import SwiftUI

/// "You": what your buddy has learned (max 3 bubbles), your week at a glance, and a few doors.
struct YouView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: Discovery?
    @State private var showShare = false

    private let maxBubbles = 3

    var body: some View {
        let repo = model.repository
        let discoveries = repo.rankedDiscoveries
        let newIDs = Set(discoveries.filter { repo.isUnseen($0) }.map(\.id))

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if repo.isDemo { DemoBanner() }

                    if repo.report.isEarlyStage || discoveries.isEmpty {
                        earlyState(repo: repo)
                    } else {
                        BubbleCloudView(
                            discoveries: Array(discoveries.prefix(maxBubbles)),
                            appearance: repo.snapshot.companion,
                            stage: repo.companionStage,
                            newIDs: newIDs,
                            onSelect: { selected = $0 }
                        )
                        .frame(height: 360)

                        if discoveries.count > maxBubbles {
                            NavigationLink("See all \(discoveries.count) discoveries") {
                                AllDiscoveriesView()
                            }
                            .buttonStyle(SoftButtonStyle())
                            .frame(maxWidth: .infinity)
                        }
                    }

                    WeekAreasView(summaries: repo.areaSummaries().filter { $0.area.isBuiltIn || $0.recentCount > 0 })

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        NavigationLink { ActivityListView() } label: {
                            Tile(title: "All moments", symbol: "list.bullet", tint: Theme.Tint.peach)
                        }
                        NavigationLink { ExperimentsView() } label: {
                            Tile(title: "Experiments", symbol: "flask", tint: Theme.Tint.butter)
                        }
                        NavigationLink { NearbyFriendsView() } label: {
                            Tile(title: "Nearby friends", symbol: "person.2.wave.2", tint: Theme.Tint.rose)
                        }
                        NavigationLink { Brain3DPreviewView() } label: {
                            Tile(title: "3D buddy (preview)", symbol: "cube.transparent", tint: Theme.Tint.lilac)
                        }
                        NavigationLink { FacePuppetView() } label: {
                            Tile(title: "Brain animoji (test)", symbol: "face.smiling", tint: Theme.Tint.mint)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("You")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showShare = true
                    } label: {
                        Label("Share card", systemImage: "square.and.arrow.up")
                    }
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationDestination(for: AreaRoute.self) { route in AreaDetailView(areaID: route.id) }
            .sheet(item: $selected) { discovery in EvidenceSheet(discoveryID: discovery.id) }
            .sheet(isPresented: $showShare) { ShareCardSheet() }
        }
    }

    private func earlyState(repo: LocalRepository) -> some View {
        let minimum = InsightThresholds.minimumActivitiesForPatterns
        let count = min(repo.report.usableCount, minimum)
        return VStack(spacing: 12) {
            BrainAvatarView(appearance: repo.snapshot.companion, stage: repo.companionStage, size: 200)
            Text(repo.report.isEarlyStage ? "Still getting to know you" : "No clear patterns yet")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.ink)
            Text(repo.report.isEarlyStage
                 ? "Patterns appear after a few days of moments."
                 : "Nothing repeats clearly yet. That's a valid result too.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
            if repo.report.isEarlyStage {
                HStack(spacing: 6) {
                    ForEach(0..<minimum, id: \.self) { index in
                        Circle().fill(index < count ? Theme.pink : Theme.hairline).frame(width: 8, height: 8)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(count) of \(minimum) moments collected")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Five soft circles: the size is how many moments each area had in the last 14 days.
struct WeekAreasView: View {
    let summaries: [AreaSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Last 2 weeks").font(.headline).foregroundStyle(Theme.ink)
                Spacer()
                NavigationLink("Open map") { LifeMapView() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.pinkDeep)
            }
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(summaries) { summary in
                    NavigationLink(value: AreaRoute(id: summary.area.id)) {
                        VStack(spacing: 6) {
                            let diameter = 34 + CGFloat(min(summary.recentCount, 20)) * 1.4
                            Image(systemName: summary.area.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .frame(width: diameter, height: diameter)
                                .background(summary.area.tint, in: Circle())
                            Text(summary.area.name)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.inkSoft)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(summary.area.name), \(countLabel(summary.recentCount, "moment", "moments")) in 2 weeks")
                }
            }
            .frame(height: 96, alignment: .bottom)
        }
        .cardStyle()
    }
}

struct AllDiscoveriesView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: Discovery?

    var body: some View {
        let repo = model.repository
        List(repo.rankedDiscoveries) { discovery in
            Button {
                selected = discovery
            } label: {
                HStack(spacing: 12) {
                    TintedIcon(symbol: discovery.symbol, tint: Theme.Tint.rose, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(discovery.title).font(.body.weight(.semibold))
                        Text(discovery.level.label).font(.caption).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    if repo.isUnseen(discovery) { Circle().fill(Theme.pinkDeep).frame(width: 8, height: 8) }
                }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Discoveries")
        .sheet(item: $selected) { discovery in EvidenceSheet(discoveryID: discovery.id) }
    }
}
