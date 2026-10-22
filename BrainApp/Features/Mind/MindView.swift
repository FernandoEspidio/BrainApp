import SwiftUI

/// Mind: everything your brain has learned about you, over time (Today only shows today).
/// 1. Your traits as a neuron: your brain is the cell body, each trait sits at the end of a branch,
///    and thin threads join traits that share a part of your life (the "connections").
/// 2. Hunches: what you believe about yourself, checked day by day. Confirmed ones become traits.
struct MindView: View {
    @Environment(AppModel.self) private var model
    @State private var evidenceTarget: Discovery?
    @State private var hunchTarget: HunchRoute?
    @State private var showNewHunch = false
    @State private var showSettled = false

    var body: some View {
        let repo = model.repository
        let discoveries = repo.rankedDiscoveries.filter { repo.snapshot.feedback[$0.id]?.notRepresentative != true }
        let neurons = MindNeuron.make(discoveries: discoveries, hunches: repo.confirmedHunches)
        let testing = repo.testingHunches
        let settled = repo.snapshot.hunches.filter { $0.status != .testing }

        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if repo.isDemo { DemoBanner() }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Your traits", systemImage: "brain")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(neurons.isEmpty
                             ? "Your first trait appears after \(InsightThresholds.minimumActivitiesForPatterns) moments, or when you confirm a hunch."
                             : "Each branch is something your brain learned about you. Threads join traits that share a part of your life.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                        NeuronMapView(appearance: repo.snapshot.companion, neurons: neurons,
                                      areaName: { repo.area(id: $0).name }) { neuron in
                            switch neuron.source {
                            case .discovery(let discovery): evidenceTarget = discovery
                            case .hunch(let id): hunchTarget = HunchRoute(id: id)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(16)
                    .background(NeuronMapView.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: Theme.ink.opacity(0.12), radius: 12, y: 4)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            sectionTitle("Hunches", symbol: "lightbulb")
                            Spacer()
                            Button { showNewHunch = true } label: { Label("New", systemImage: "plus") }
                                .buttonStyle(SoftButtonStyle())
                        }
                        Text("Something you believe about yourself? Check it for a few days.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSoft)
                        if testing.isEmpty {
                            Button { showNewHunch = true } label: {
                                Label("Start your first hunch", systemImage: "lightbulb.max")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(InkButtonStyle())
                        }
                        ForEach(testing) { hunch in
                            Button { hunchTarget = HunchRoute(id: hunch.id) } label: { HunchRow(hunch: hunch) }
                                .buttonStyle(.plain)
                            if hunch.id != testing.last?.id { Divider() }
                        }
                        if !settled.isEmpty {
                            DisclosureGroup("Settled (\(settled.count))", isExpanded: $showSettled) {
                                VStack(spacing: 10) {
                                    ForEach(settled) { hunch in
                                        Button { hunchTarget = HunchRoute(id: hunch.id) } label: { HunchRow(hunch: hunch) }
                                            .buttonStyle(.plain)
                                    }
                                }
                                .padding(.top, 8)
                            }
                            .tint(Theme.ink)
                            .font(.subheadline.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()

                }
                .padding()
            }
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("Mind")
            .navigationDestination(for: AreaRoute.self) { route in AreaDetailView(areaID: route.id) }
            .navigationDestination(for: RingRoute.self) { route in AreaGoalDetailView(areaID: route.id) }
            .sheet(item: $evidenceTarget) { discovery in EvidenceSheet(discoveryID: discovery.id) }
            .sheet(item: $hunchTarget) { route in HunchDetailSheet(hunchID: route.id) }
            .sheet(isPresented: $showNewHunch) { NewHunchSheet(suggestionsFrom: discoveries) }
        }
    }

    private func sectionTitle(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.headline).foregroundStyle(Theme.ink)
    }
}

struct HunchRow: View {
    let hunch: Hunch

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TintedIcon(symbol: hunch.symbol, tint: hunch.status == .confirmed ? Theme.Tint.lilac : Theme.Tint.butter, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hunch.statement)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    Text(subtitle).font(.caption).foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSoft)
            }
            if hunch.status == .testing { HunchDots(hunch: hunch).padding(.leading, 46) }
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        switch hunch.status {
        case .testing: return hunch.isReadyToDecide ? "Ready: see how it went" : "Day \(hunch.answeredCount) of \(hunch.targetCheckIns)"
        case .confirmed: return "Confirmed · now a trait"
        case .notReally: return "Not really you"
        }
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

// MARK: - Neuron map

/// A trait as a neuron: from a discovery the app found, or a hunch you confirmed.
struct MindNeuron: Identifiable {
    enum Source {
        case discovery(Discovery)
        case hunch(UUID)
    }

    let id: String
    let title: String
    let symbol: String
    let areaIDs: [String]
    let isStrong: Bool
    let source: Source

    var tint: Color {
        if case .hunch = source { return Theme.Tint.lilac }
        return isStrong ? Theme.Tint.rose : Theme.Tint.peach
    }

    static let maxShown = 8

    static func make(discoveries: [Discovery], hunches: [Hunch]) -> [MindNeuron] {
        let fromHunches = hunches.map {
            MindNeuron(id: "hunch.\($0.id)", title: $0.statement, symbol: $0.symbol, areaIDs: $0.areaIDs,
                       isStrong: true, source: .hunch($0.id))
        }
        let fromDiscoveries = discoveries.map {
            MindNeuron(id: $0.id, title: $0.title, symbol: $0.symbol, areaIDs: $0.areaIDs,
                       isStrong: $0.level == .possibleStrength, source: .discovery($0))
        }
        return Array((fromHunches + fromDiscoveries).prefix(maxShown))
    }
}
