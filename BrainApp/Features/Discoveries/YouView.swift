import SwiftUI

/// Insights tab: Life rings (tap a ring → goal & progress), then discoveries, then the connections map.
struct YouView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: Discovery?

    var body: some View {
        let repo = model.repository
        let rings = repo.rings()
        let discoveries = repo.rankedDiscoveries

        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if repo.isDemo { DemoBanner() }

                    // Life rings
                    VStack(spacing: 22) {
                        RingsOverview(rings: rings)
                        RingTileRow(rings: rings)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .cardStyle(padding: 20)

                    // Discoveries
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("Discoveries", symbol: "sparkles")
                        if repo.report.isEarlyStage || discoveries.isEmpty {
                            learningState(repo: repo)
                        } else {
                            ForEach(discoveries) { discovery in
                                Button { selected = discovery } label: {
                                    DiscoveryRow(discovery: discovery, isNew: repo.isUnseen(discovery))
                                }
                                .buttonStyle(.plain)
                                if discovery.id != discoveries.last?.id { Divider() }
                            }
                        }
                    }
                    .cardStyle()

                    NavigationLink {
                        LifeMapView()
                    } label: {
                        HStack(spacing: 12) {
                            TintedIcon(symbol: "point.3.connected.trianglepath.dotted", tint: Theme.Tint.lilac, size: 40)
                            Text("Connections map")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        .cardStyle()
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("Insights")
            .navigationDestination(for: RingRoute.self) { route in AreaGoalDetailView(areaID: route.id) }
            .navigationDestination(for: AreaRoute.self) { route in AreaDetailView(areaID: route.id) }
            .sheet(item: $selected) { discovery in EvidenceSheet(discoveryID: discovery.id) }
        }
    }

    private func sectionTitle(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.headline)
            .foregroundStyle(Theme.ink)
    }

    private func learningState(repo: LocalRepository) -> some View {
        let minimum = InsightThresholds.minimumActivitiesForPatterns
        let count = min(repo.report.usableCount, minimum)
        return HStack(spacing: 6) {
            ForEach(0..<minimum, id: \.self) { index in
                Circle().fill(index < count ? Theme.pink : Theme.hairline).frame(width: 10, height: 10)
            }
            Spacer()
            Text("\(count)/\(minimum)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.inkSoft)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Learning about you: \(count) of \(minimum) moments")
    }
}

struct DiscoveryRow: View {
    let discovery: Discovery
    let isNew: Bool

    var body: some View {
        HStack(spacing: 12) {
            TintedIcon(symbol: discovery.symbol, tint: Theme.Tint.rose, size: 40)
            Text(discovery.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            Spacer(minLength: 0)
            if isNew { Circle().fill(Theme.pinkDeep).frame(width: 8, height: 8) }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSoft)
        }
        .contentShape(Rectangle())
    }
}
