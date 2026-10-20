import SwiftUI

/// Today: greeting, the brain doing what you did, one line of why, today's moments and ONE card.
/// No bars, no dashboards. Most moments arrive on their own (detected by the phone).
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var previewMoment: UUID?
    @State private var poke = 0
    @State private var showLog = false
    @State private var showSettings = false
    @State private var evidenceTarget: Discovery?
    @State private var experimentRoute: UUID?

    var body: some View {
        let repo = model.repository
        let live = repo.companionState()
        let moments = repo.todayMoments()
        let preview = moments.first { $0.id == previewMoment }
        let mood = preview?.mood ?? live.mood
        let reason = preview.map { repo.describe($0.activity, prefix: $0.activity.date.formatted(date: .omitted, time: .shortened)) } ?? live.reason
        let night = mood.isNight
        let ink = night ? Color.white : Theme.ink

        NavigationStack {
            ZStack {
                (night ? Theme.night : Theme.cream).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        header(repo: repo, ink: ink)
                        if repo.isDemo { DemoBanner() }

                        BrainAvatarView(appearance: repo.snapshot.companion, stage: live.stage, mood: mood,
                                        size: 300, showsStage: true, poke: poke)
                            .onTapGesture { poke += 1 }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("Tap to say hi")

                        VStack(spacing: 4) {
                            Text(mood.title)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(ink)
                            Text(reason)
                                .font(.footnote)
                                .foregroundStyle(night ? Color.white.opacity(0.7) : Theme.inkSoft)
                                .multilineTextAlignment(.center)
                        }
                        .animation(.easeInOut, value: mood)

                        if !moments.isEmpty {
                            TodayStrip(moments: moments, selected: $previewMoment, night: night)
                        }

                        HomeCardView(
                            card: repo.homeCard(),
                            onOpenDiscovery: { evidenceTarget = $0 },
                            onFeeling: { activity, value in repo.setFeeling(value, for: activity.id) },
                            onSkip: { repo.skipCheckIn($0.id) },
                            onOpenExperiment: { experimentRoute = $0.id }
                        )
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 24)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $experimentRoute) { id in ExperimentDetailView(experimentID: id) }
            .sheet(isPresented: $showLog) { LogActivitySheet(existing: nil) }
            .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
            .sheet(item: $evidenceTarget) { discovery in EvidenceSheet(discoveryID: discovery.id) }
            .animation(.easeInOut(duration: 0.35), value: night)
        }
    }

    private func header(repo: LocalRepository, ink: Color) -> some View {
        let name = repo.snapshot.userName
        return HStack(spacing: 10) {
            // Settings live behind the avatar.
            Button {
                showSettings = true
            } label: {
                Group {
                    if let initial = name.first {
                        Text(String(initial).uppercased()).font(.headline)
                    } else {
                        Image(systemName: "person.fill").font(.subheadline)
                    }
                }
                .foregroundStyle(Theme.ink)
                .frame(width: 34, height: 34)
                .background(Color.white, in: Circle())
            }
            .accessibilityLabel("Settings")
            Text(name.isEmpty ? "Hi there" : "Hi, \(name)")
                .font(.title2.weight(.bold))
                .foregroundStyle(ink)
            Spacer()
            // Days together, not a streak: missing a day never breaks anything.
            Label("Day \(repo.daysTogether())", systemImage: "leaf.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white, in: Capsule())
                .accessibilityLabel("Day \(repo.daysTogether()) together")
            Button {
                showLog = true
            } label: {
                Image(systemName: "plus")
                    .font(.headline)
                    .foregroundStyle(ink == .white ? Theme.ink : .white)
                    .frame(width: 34, height: 34)
                    .background(ink == .white ? Color.white : Theme.ink, in: Circle())
            }
            .accessibilityLabel("Add something your phone can't detect")
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

/// Today's moments as small chips. Tapping one shows the brain in that moment.
struct TodayStrip: View {
    let moments: [TodayMoment]
    @Binding var selected: UUID?
    var night: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(moments) { moment in
                    let isSelected = selected == moment.id
                    Button {
                        withAnimation(.snappy) { selected = isSelected ? nil : moment.id }
                    } label: {
                        Label(moment.shortValue, systemImage: moment.symbol)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(night && !isSelected ? 0.85 : 1), in: Capsule())
                            .overlay(Capsule().strokeBorder(isSelected ? Theme.pinkDeep : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(moment.activity.title), \(moment.shortValue)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal)
        }
    }
}
