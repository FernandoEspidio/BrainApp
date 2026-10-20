import SwiftUI

/// Friends: your brain animoji card (exactly what friends will see), ways to send it,
/// and your friends' brains to compare with yours.
struct NearbyFriendsView: View {
    @Environment(AppModel.self) private var model

    @State private var tracker = FaceTracker()
    @State private var mirroring = false
    @State private var recordingProgress: Double?
    @State private var poke = 0
    @State private var reaction: ActiveReaction?
    @State private var showShare = false

    var body: some View {
        @Bindable var bindable = model
        let repo = model.repository

        ScrollView {
            VStack(spacing: 20) {
                if repo.isDemo { DemoBanner() }

                myBrainCard(repo: repo, options: $bindable.shareOptions)
                actions
                if model.nearby.primaryTransport != nil { quickSwap }
                friendsSection(repo: repo)
            }
            .padding()
        }
        .background(Theme.cream.ignoresSafeArea())
        .navigationTitle("Friends")
        .sheet(isPresented: $showShare) { ShareCardSheet() }
        .onDisappear { stopMirroring() }
    }

    // MARK: - My brain

    private func myBrainCard(repo: LocalRepository, options: Binding<ShareOptions>) -> some View {
        let mood = repo.companionState().mood
        let base = BrainExpressions.base(mood: mood, overallProgress: repo.overallProgress(), anyRingClosed: false)

        return VStack(spacing: 16) {
            BrainBuddyView(
                appearance: repo.snapshot.companion,
                mood: mood,
                basePose: base,
                livePose: mirroring && tracker.isTracking ? tracker.pose : nil,
                clip: mirroring ? nil : repo.snapshot.animoji,
                reaction: reaction,
                stage: nil,
                poke: poke,
                onTap: {
                    poke += 1
                    reaction = ActiveReaction(kind: BrainReaction.allCases.randomElement() ?? .giggle, start: .now)
                }
            )
            .frame(width: 210, height: 210)
            .sensoryFeedback(.impact(weight: .light), trigger: poke)
            .overlay(alignment: .topTrailing) { recordingBadge }

            expressionPicker(repo: repo)

            if FaceTracker.isSupported { mirrorControls(repo: repo) }

            Divider()

            HStack(spacing: 8) {
                ShareChip(title: "Animoji", symbol: "face.smiling", isOn: options.includeAnimoji)
                ShareChip(title: "Mood", symbol: mood.symbol, isOn: options.includeMood)
                ShareChip(title: "Rings", symbol: "circle.circle", isOn: options.includeRings)
                ShareChip(title: "Traits", symbol: "sparkles", isOn: options.includeTraits)
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle(padding: 20)
    }

    /// Preset expressions become your animoji in one tap (no camera needed).
    private func expressionPicker(repo: LocalRepository) -> some View {
        let current = repo.snapshot.animoji
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BrainReaction.allCases, id: \.self) { kind in
                    let frames = AnimojiClip.frames(for: kind)
                    let isSelected = !current.isEmpty && current == frames
                    Button {
                        repo.setAnimoji(isSelected ? [] : frames)
                        poke += 1
                    } label: {
                        Text(kind.emoji)
                            .font(.system(size: 24))
                            .frame(width: 46, height: 46)
                            .background(isSelected ? Theme.Tint.rose : Theme.ink.opacity(0.05), in: Circle())
                            .overlay(Circle().strokeBorder(isSelected ? Theme.pinkDeep : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(kind.rawValue)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 2)
        }
        .sensoryFeedback(.selection, trigger: current)
    }

    private func mirrorControls(repo: LocalRepository) -> some View {
        HStack(spacing: 10) {
            Button {
                mirroring ? stopMirroring() : startMirroring()
            } label: {
                Label(mirroring ? "Stop" : "Mirror me", systemImage: mirroring ? "stop.fill" : "face.dashed")
            }
            .buttonStyle(SoftButtonStyle())

            if mirroring {
                Button {
                    record(repo: repo)
                } label: {
                    Label("Record", systemImage: "record.circle")
                }
                .buttonStyle(SoftButtonStyle())
                .disabled(!tracker.isTracking || recordingProgress != nil)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy, value: mirroring)
    }

    @ViewBuilder
    private var recordingBadge: some View {
        if let progress = recordingProgress {
            ZStack {
                StaticRing(fraction: progress, color: .red, lineWidth: 4)
                Circle().fill(.red).frame(width: 10, height: 10)
            }
            .frame(width: 36, height: 36)
            .transition(.scale)
        }
    }

    // MARK: - Send

    private var actions: some View {
        HStack(spacing: 12) {
            NavigationLink { PeerToPeerTestView() } label: {
                ActionTile(title: "Swap", symbol: "antenna.radiowaves.left.and.right", tint: Theme.Tint.sky)
            }
            NavigationLink { ThrowTestView() } label: {
                ActionTile(title: "Throw", symbol: "hand.point.up.left.fill", tint: Theme.Tint.mint)
            }
            Button { showShare = true } label: {
                ActionTile(title: "Share", symbol: "square.and.arrow.up", tint: Theme.Tint.rose)
            }
        }
        .buttonStyle(.plain)
    }

    /// One-tap exchange through the build's nearby transport (Wi-Fi Aware, or simulated in Demo mode).
    private var quickSwap: some View {
        let nearby = model.nearby
        return VStack(alignment: .leading, spacing: 12) {
            #if WIFI_AWARE_ENABLED && canImport(WiFiAware)
            if #available(iOS 26.0, *) {
                if nearby.primaryTransport?.kind == .wifiAware {
                    WiFiAwarePairingRows()
                }
            }
            #endif

            switch nearby.state {
            case .idle:
                startButtons
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.footnote)
                startButtons
            case .working:
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Looking…").foregroundStyle(Theme.inkSoft)
                    Spacer()
                    Button("Cancel", role: .cancel) { nearby.cancel() }
                }
            case .received(let card):
                Label("\(card.displayName) joined!", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Button("Done") { nearby.reset() }
                    .buttonStyle(SoftButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var startButtons: some View {
        HStack(spacing: 10) {
            Button { start(.host) } label: { Label("Wait", systemImage: "antenna.radiowaves.left.and.right") }
                .buttonStyle(SoftButtonStyle())
            Button { start(.join) } label: { Label("Find", systemImage: "magnifyingglass") }
                .buttonStyle(SoftButtonStyle())
        }
    }

    private func start(_ role: NearbySharingCoordinator.Role) {
        let repo = model.repository
        let kind = model.nearby.primaryTransport?.kind ?? .demo
        model.nearby.start(role, card: model.makeCard()) { received in
            repo.addFriend(received, via: kind)
        }
    }

    // MARK: - Friends

    private func friendsSection(repo: LocalRepository) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Friends", systemImage: "person.2.fill")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            if repo.snapshot.friends.isEmpty {
                Text("Swap brains to add one")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(repo.snapshot.friends) { friend in
                            NavigationLink { FriendDetailView(friend: friend) } label: {
                                VStack(spacing: 6) {
                                    AnimojiPlayer(appearance: friend.card.appearance, mood: friend.card.brainMood ?? .idle,
                                                  clip: friend.card.animoji ?? [], animated: false)
                                        .frame(width: 72, height: 72)
                                    Text(friend.card.displayName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(1)
                                }
                                .frame(width: 80)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Mirror & record

    private func startMirroring() {
        tracker.start()
        withAnimation(.snappy) { mirroring = true }
    }

    private func stopMirroring() {
        guard mirroring else { return }
        tracker.stop()
        withAnimation(.snappy) { mirroring = false }
    }

    /// Captures a few seconds of your expressions (poses only, never camera images) as your animoji.
    private func record(repo: LocalRepository) {
        withAnimation { recordingProgress = 0 }
        Task {
            let total = Int(AnimojiClip.recordSeconds * AnimojiClip.fps)
            var frames: [FacePose] = []
            for index in 0..<total {
                frames.append(tracker.pose)
                recordingProgress = Double(index + 1) / Double(total)
                try? await Task.sleep(for: .seconds(1.0 / AnimojiClip.fps))
            }
            repo.setAnimoji(frames)
            withAnimation { recordingProgress = nil }
            stopMirroring()
            poke += 1
        }
    }
}

/// On/off chip for one piece of what gets shared.
struct ShareChip: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.snappy) { isOn.toggle() }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isOn ? symbol : "eye.slash")
                    .font(.system(size: 16, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(title).font(.caption2.weight(.semibold))
            }
            .foregroundStyle(isOn ? Color.white : Theme.inkSoft)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isOn ? Theme.ink : Theme.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityLabel("Share \(title)")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

struct ActionTile: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            TintedIcon(symbol: symbol, tint: tint, size: 44)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity)
        .cardStyle(padding: 14)
    }
}

/// A friend's brain next to yours: animoji, mood, rings and traits in common.
struct FriendDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let friend: Friend
    @State private var confirmRemove = false

    var body: some View {
        let repo = model.repository
        let card = friend.card
        let myRings = repo.rings().map { SharedRing(areaID: $0.area.id, percent: $0.percent) }
        let myTitles = Set(repo.rankedDiscoveries.map(\.title))

        ScrollView {
            VStack(spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    brainColumn(name: "You", appearance: repo.snapshot.companion,
                                mood: repo.companionState().mood, clip: repo.snapshot.animoji)
                    brainColumn(name: card.displayName, appearance: card.appearance,
                                mood: card.brainMood, clip: card.animoji ?? [])
                }
                .cardStyle()

                if let theirRings = card.rings, !theirRings.isEmpty {
                    RingsCompare(mine: myRings, theirs: theirRings, friendName: card.displayName)
                        .cardStyle()
                }

                if !card.highlights.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Traits", systemImage: "sparkles").font(.headline).foregroundStyle(Theme.ink)
                        ForEach(card.highlights, id: \.self) { highlight in
                            HStack(spacing: 10) {
                                Image(systemName: highlight.symbol).foregroundStyle(Theme.pinkDeep).frame(width: 22)
                                Text(highlight.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                                Spacer(minLength: 0)
                                if myTitles.contains(highlight.title) {
                                    Text("Both").font(.caption2.weight(.bold)).foregroundStyle(.white)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Theme.pinkDeep, in: Capsule())
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }

                Text(friend.receivedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding()
        }
        .background(Theme.cream.ignoresSafeArea())
        .navigationTitle(card.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { confirmRemove = true } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Remove friend")
            }
        }
        .confirmationDialog("Remove \(card.displayName)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                repo.removeFriend(friend.id)
                dismiss()
            }
        }
    }

    private func brainColumn(name: String, appearance: CompanionAppearance, mood: BrainMood?, clip: [FacePose]) -> some View {
        VStack(spacing: 8) {
            AnimojiPlayer(appearance: appearance, mood: mood ?? .idle, clip: clip)
                .frame(width: 130, height: 130)
            Text(name).font(.headline).foregroundStyle(Theme.ink).lineLimit(1)
            if let mood { MoodChip(mood: mood) }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Two bars per area: you (solid) and your friend (light).
struct RingsCompare: View {
    let mine: [SharedRing]
    let theirs: [SharedRing]
    let friendName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Label("Rings", systemImage: "circle.circle").font(.headline).foregroundStyle(Theme.ink)
                Spacer()
                legend("You", opacity: 1)
                legend(friendName, opacity: 0.35)
            }
            ForEach(LifeArea.builtIns) { area in
                let me = mine.first { $0.areaID == area.id }?.percent ?? 0
                let them = theirs.first { $0.areaID == area.id }?.percent ?? 0
                HStack(spacing: 10) {
                    Image(systemName: area.symbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(area.ringColor)
                        .frame(width: 22)
                    VStack(spacing: 4) {
                        bar(me, color: area.ringColor)
                        bar(them, color: area.ringColor.opacity(0.35))
                    }
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(me)%").font(.caption2.weight(.bold))
                        Text("\(them)%").font(.caption2).foregroundStyle(Theme.inkSoft)
                    }
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(area.name): you \(me) percent, \(friendName) \(them) percent")
            }
        }
    }

    private func legend(_ text: String, opacity: Double) -> some View {
        HStack(spacing: 4) {
            Circle().fill(Theme.ink.opacity(opacity)).frame(width: 8, height: 8)
            Text(text).font(.caption2.weight(.semibold)).foregroundStyle(Theme.inkSoft).lineLimit(1)
        }
    }

    private func bar(_ percent: Int, color: Color) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ink.opacity(0.06))
                Capsule().fill(color)
                    .frame(width: max(6, geometry.size.width * min(Double(percent) / 100, 1)))
            }
        }
        .frame(height: 8)
    }
}
