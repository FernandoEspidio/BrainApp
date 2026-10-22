import SwiftUI
import UIKit

/// Friends: your brain on top (live, copying your face when the camera is allowed),
/// one clear action ("Trade brains") and the collection of brains you've met.
/// Friends' brains are drawn still here; tapping one opens its card and plays its move,
/// so the screen never turns into a wall of moving faces.
struct FriendsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    @State private var tracker = FaceTracker()
    @State private var access = FaceTracker.access
    @State private var isOnScreen = false

    @State private var poke = 0
    @State private var reaction: ActiveReaction?
    @State private var replayStart: Date?

    @State private var showRecord = false
    @State private var showCloset = false
    @State private var showTrade = false
    @State private var showPreview = false
    @State private var showShareImage = false
    @State private var selectedFriend: Friend?
    @State private var friendToRemove: Friend?

    var body: some View {
        let repo = model.repository

        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if repo.isDemo { DemoBanner() }
                    hero(repo: repo)
                    collection(repo: repo)
                }
                .padding()
            }
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("Friends")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showPreview = true } label: { Label("What friends see", systemImage: "eye") }
                        Button { showShareImage = true } label: { Label("Share as image", systemImage: "square.and.arrow.up") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                }
            }
            .sheet(isPresented: $showRecord, onDismiss: resumeMirror) {
                RecordMoveSheet(tracker: tracker) { clip in
                    repo.setAnimoji(clip)
                    replayStart = nil
                }
            }
            .sheet(isPresented: $showCloset) {
                NavigationStack { CompanionCustomizationView(isSheet: true) }
            }
            .sheet(isPresented: $showPreview) { MyCardPreviewSheet() }
            .sheet(isPresented: $showShareImage) { ShareCardSheet() }
            .sheet(item: $selectedFriend) { friend in FriendCardSheet(friend: friend) }
            .fullScreenCover(isPresented: $showTrade, onDismiss: resumeMirror) { BrainTradeView() }
            .confirmationDialog("Remove \(friendToRemove?.card.displayName ?? "")?", isPresented: removeBinding, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if let friend = friendToRemove { withAnimation { repo.removeFriend(friend.id) } }
                }
            }
        }
        .onAppear {
            isOnScreen = true
            resumeMirror()
        }
        .onDisappear {
            isOnScreen = false
            tracker.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { resumeMirror() } else { tracker.stop() }
        }
    }

    // MARK: - Your brain

    private var mirroring: Bool { tracker.isRunning }

    private func hero(repo: LocalRepository) -> some View {
        let companion = repo.snapshot.companion
        let clip = repo.snapshot.animoji
        var base = FacePose()
        base.smile = 0.4

        return VStack(spacing: 14) {
            BrainBuddyView(
                appearance: companion,
                mood: .idle,
                basePose: base,
                livePose: nil,
                liveSource: mirroring && tracker.isTracking ? tracker : nil,
                clip: mirroring ? nil : clip,
                clipStart: replayStart,
                reaction: reaction,
                stage: nil,
                poke: poke,
                onTap: { tapBrain(clip: clip) },
                accessibilityTapHint: clip.isEmpty ? "Tap for a reaction" : "Tap to play your move"
            )
            .frame(width: 220, height: 220)
            .sensoryFeedback(.impact(weight: .light), trigger: poke)
            .overlay(alignment: .topTrailing) { liveBadge }

            VStack(spacing: 4) {
                Text(companion.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.ink)
                statusLine(name: companion.name, hasMove: !clip.isEmpty)
            }

            HStack(spacing: 10) {
                Button { showRecord = true } label: {
                    Label(clip.isEmpty ? "Record a move" : "New move", systemImage: "record.circle")
                }
                .buttonStyle(SoftButtonStyle())
                Button { showCloset = true } label: {
                    Label("Style", systemImage: "tshirt")
                }
                .buttonStyle(SoftButtonStyle())
            }

            Button { showTrade = true } label: {
                Label("Trade brains", systemImage: "sparkles")
            }
            .buttonStyle(InkButtonStyle())

            Text("You both tap Trade · no internet needed")
                .font(.caption)
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .cardStyle(padding: 20)
    }

    @ViewBuilder
    private var liveBadge: some View {
        if mirroring {
            HStack(spacing: 5) {
                Circle().fill(tracker.isTracking ? Color.red : Theme.inkSoft).frame(width: 7, height: 7)
                Text(tracker.isTracking ? "Live" : "Looking…")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white, in: Capsule())
            .shadow(color: Theme.ink.opacity(0.08), radius: 4, y: 2)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel(tracker.isTracking ? "Copying your face" : "Looking for your face")
        }
    }

    @ViewBuilder
    private func statusLine(name: String, hasMove: Bool) -> some View {
        switch access {
        case .notAsked:
            Button {
                tracker.start()
                // The system asks for camera access now; re-check once it's answered.
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    access = FaceTracker.access
                }
            } label: {
                Label("Let \(name) copy your face", systemImage: "camera.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(Theme.pinkDeep)
        case .allowed where mirroring:
            Text(tracker.isTracking ? "Copying your face · only shapes, never images" : "Look at the screen")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
        default:
            Text(hasMove ? "Tap \(name) to see your move" : "Record a move so friends see the real you")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private func tapBrain(clip: BrainClip) {
        poke += 1
        if !mirroring && !clip.isEmpty {
            // Play it from the start once, then go back to looping.
            let start = Date.now
            replayStart = start
            Task {
                try? await Task.sleep(for: .seconds(clip.duration + 0.4))
                if replayStart == start { replayStart = nil }
            }
        } else {
            reaction = ActiveReaction(kind: BrainReaction.allCases.randomElement() ?? .giggle, start: .now)
        }
    }

    /// The camera only runs while this screen is visible, the app is active and nothing covers it.
    private func resumeMirror() {
        access = FaceTracker.access
        guard isOnScreen, access == .allowed, !showTrade, scenePhase == .active else { return }
        withAnimation(.snappy) { tracker.start() }
    }

    // MARK: - Collection

    private func collection(repo: LocalRepository) -> some View {
        let friends = repo.snapshot.friends
        // Empty "?" slots make it feel like a collection to fill, never like a ranking.
        let slots = max(6, Int((Double(friends.count + 1) / 3).rounded(.up)) * 3)
        let mysteries = max(0, slots - friends.count)
        let columns = [GridItem(.adaptive(minimum: 92), spacing: 12)]

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Brains you've met", systemImage: "square.grid.3x3.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(friends.count)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Theme.Tint.rose, in: Capsule())
                    .accessibilityLabel("\(friends.count) met")
            }

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(friends) { friend in
                    Button { selectedFriend = friend } label: {
                        VStack(spacing: 4) {
                            BrainThumbnail(appearance: friend.card.appearance)
                                .frame(width: 84, height: 84)
                            Text(friend.card.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .contextMenu {
                        Button(role: .destructive) { friendToRemove = friend } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    .accessibilityLabel("\(friend.card.displayName)'s brain")
                    .accessibilityHint("Opens their card")
                }
                ForEach(0..<mysteries, id: \.self) { _ in
                    VStack(spacing: 4) {
                        MysteryThumbnail().frame(width: 84, height: 84)
                        Text("???")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkSoft.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                }
            }

            if friends.isEmpty {
                Text("Trade with someone nearby to meet your first brain.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var removeBinding: Binding<Bool> {
        Binding(get: { friendToRemove != nil }, set: { if !$0 { friendToRemove = nil } })
    }
}

/// Springy press feedback for tappable brains.
struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
