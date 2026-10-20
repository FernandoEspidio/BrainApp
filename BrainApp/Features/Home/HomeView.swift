import SwiftUI

/// Today: the brain animoji is the screen.
/// - Its face shows your current state (sleepy, focused, happier as rings fill).
/// - Tap it: it reacts and tells you one real insight (tap the bubble to open that ring).
/// - Drag it: it looks around. (Mirror me / sharing lives in Friends.)
/// - Below: today's five rings (tap → goal detail) and one card.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("hasTappedBrain") private var hasTappedBrain = false

    @State private var poke = 0
    @State private var reaction: ActiveReaction?
    @State private var line: BrainLine?
    @State private var lineIndex = 0
    @State private var logRequest: LogRequest?
    @State private var evidenceTarget: Discovery?

    var body: some View {
        let repo = model.repository
        let live = repo.companionState()
        let rings = repo.rings()
        let mood = live.mood
        let night = mood.isNight
        let ink = night ? Color.white : Theme.ink
        let card = repo.homeCard()
        let base = BrainExpressions.base(mood: mood, overallProgress: repo.overallProgress(),
                                         anyRingClosed: rings.contains(where: \.isComplete))
        let bubbleText = line?.text ?? mood.title

        NavigationStack {
            ZStack {
                (night ? Theme.night : Theme.cream).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        header(repo: repo, ink: ink)
                        if repo.isDemo { DemoBanner() }

                        // The brain
                        VStack(spacing: 4) {
                            bubble(text: bubbleText, ringID: line?.ringID)
                            BrainBuddyView(
                                appearance: repo.snapshot.companion,
                                mood: mood,
                                basePose: base,
                                livePose: nil,
                                reaction: reaction,
                                stage: live.stage,
                                poke: poke,
                                onTap: { tapBrain(repo: repo, mood: mood) }
                            )
                            .frame(width: 270, height: 270)
                            .sensoryFeedback(.impact(weight: .light), trigger: poke)
                            tapHint(ink: ink)
                        }

                        // Today's rings
                        RingTileRow(rings: rings, ringSize: 46, showsNames: false)
                            .padding(.vertical, 4)
                            .cardStyle(padding: 14)
                            .padding(.horizontal)

                        if card.isShown {
                            HomeCardView(
                                card: card,
                                onOpenDiscovery: { evidenceTarget = $0 },
                                onFeeling: { activity, value in repo.setFeeling(value, for: activity.id) },
                                onSkip: { repo.skipCheckIn($0.id) },
                                onOpenExperiment: { _ in }
                            )
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 24)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: RingRoute.self) { route in AreaGoalDetailView(areaID: route.id) }
            .navigationDestination(for: AreaRoute.self) { route in AreaDetailView(areaID: route.id) }
            .sheet(item: $logRequest) { request in LogActivitySheet(existing: nil, presetAreaID: request.areaID) }
            .sheet(item: $evidenceTarget) { discovery in EvidenceSheet(discoveryID: discovery.id) }
            .animation(.easeInOut(duration: 0.35), value: night)
        }
    }

    // MARK: - Interaction

    private func tapBrain(repo: LocalRepository, mood: BrainMood) {
        hasTappedBrain = true
        let lines = BrainTalk.lines(repo: repo, mood: mood)
        guard !lines.isEmpty else { return }
        let next = lines[lineIndex % lines.count]
        lineIndex += 1
        poke += 1
        withAnimation(.snappy) { line = next }
        reaction = ActiveReaction(kind: next.reaction, start: .now)

        let shown = lineIndex
        Task {
            try? await Task.sleep(for: .seconds(4.5))
            if shown == lineIndex { withAnimation(.snappy) { line = nil } }
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func bubble(text: String, ringID: String?) -> some View {
        if let ringID {
            NavigationLink(value: RingRoute(id: ringID)) {
                SpeechBubble(text: text, showsChevron: true)
            }
            .buttonStyle(.plain)
        } else {
            SpeechBubble(text: text, showsChevron: false)
        }
    }

    /// Shown only until the first tap; keeps the same height afterwards so nothing jumps.
    private func tapHint(ink: Color) -> some View {
        Label("Tap me", systemImage: "hand.tap.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(ink.opacity(0.55))
            .symbolEffect(.pulse)
            .opacity(hasTappedBrain ? 0 : 1)
            .frame(height: 22)
            .accessibilityHidden(hasTappedBrain)
    }

    private func header(repo: LocalRepository, ink: Color) -> some View {
        let name = repo.snapshot.userName
        return HStack(spacing: 10) {
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
                logRequest = LogRequest(areaID: nil)
            } label: {
                Image(systemName: "plus")
                    .font(.headline)
                    .foregroundStyle(ink == .white ? Theme.ink : .white)
                    .frame(width: 34, height: 34)
                    .background(ink == .white ? Color.white : Theme.ink, in: Circle())
            }
            .accessibilityLabel("Add a moment")
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

private extension HomeCard {
    /// Quiet states say nothing: the brain already shows it.
    var isShown: Bool {
        switch self {
        case .gettingToKnowYou, .allQuiet, .experiment: return false
        default: return true
        }
    }
}

/// Rounded bubble with a tail pointing at the brain. Text cross-fades when it changes.
struct SpeechBubble: View {
    let text: String
    var showsChevron = false

    var body: some View {
        VStack(spacing: -1) {
            HStack(spacing: 6) {
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .contentTransition(.opacity)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.pinkDeep)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.white)
        }
        .padding(.horizontal, 32)
        .shadow(color: Theme.ink.opacity(0.08), radius: 8, y: 3)
        .id(text)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }
}
