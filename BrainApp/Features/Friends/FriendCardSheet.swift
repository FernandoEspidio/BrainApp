import SwiftUI

/// A friend's card: their brain plays the move they recorded, their traits orbit around it.
/// Below, the same traits as a plain list (readable, VoiceOver-friendly), marking the ones you share.
struct FriendCardSheet: View {
    let friend: Friend

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var playStart = Date.now.addingTimeInterval(0.5)
    @State private var revealStart = Date.now.addingTimeInterval(0.15)
    @State private var confirmRemove = false

    var body: some View {
        let card = friend.card
        // What you have in common: your discoveries and the hunches you confirmed.
        let mine = Set(model.repository.rankedDiscoveries.map(\.title) + model.repository.confirmedHunches.map(\.statement))

        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    BrainOrbitView(appearance: card.appearance, clip: card.animoji ?? .empty, traits: card.traits,
                                   playStart: playStart, revealStart: revealStart)
                        .onTapGesture { replay() }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Plays their move again")

                    VStack(spacing: 4) {
                        Text(card.displayName)
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Theme.ink)
                        Text(card.stageName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.inkSoft)
                    }

                    if !(card.animoji ?? .empty).isEmpty {
                        Button { replay() } label: {
                            Label("Play their move", systemImage: "play.fill")
                        }
                        .buttonStyle(SoftButtonStyle())
                    }

                    if !card.traits.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Traits", systemImage: "sparkles").font(.headline).foregroundStyle(Theme.ink)
                            ForEach(card.traits, id: \.self) { trait in
                                HStack(spacing: 10) {
                                    TintedIcon(symbol: trait.symbol, tint: Theme.Tint.rose, size: 34)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(trait.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                                        Text(trait.levelLabel).font(.caption).foregroundStyle(Theme.inkSoft)
                                    }
                                    Spacer(minLength: 0)
                                    if mine.contains(trait.title) {
                                        Text("You too").font(.caption2.weight(.bold)).foregroundStyle(.white)
                                            .padding(.horizontal, 8).padding(.vertical, 3)
                                            .background(Theme.pinkDeep, in: Capsule())
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardStyle()
                    }

                    HStack(spacing: 6) {
                        if card.isDemo { Label("Fictional", systemImage: "theatermasks") }
                        Text("Met \(friend.receivedAt.formatted(date: .abbreviated, time: .omitted))")
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
                }
                .padding()
            }
            .background(Theme.cream.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Menu {
                        Button(role: .destructive) { confirmRemove = true } label: { Label("Remove", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Remove \(card.displayName)?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    model.repository.removeFriend(friend.id)
                    dismiss()
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func replay() {
        playStart = .now
    }
}

/// Your own card exactly as a friend receives it, plus what travels with it.
struct MyCardPreviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var playStart = Date.now.addingTimeInterval(0.4)

    var body: some View {
        @Bindable var bindable = model
        let repo = model.repository
        let card = model.makeCard()
        let candidates = BrainCardFactory.candidates(repo.rankedDiscoveries, hunches: repo.snapshot.hunches, options: model.shareOptions)
        let selected = model.shareOptions.selectedDiscoveryIDs

        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        BrainOrbitView(appearance: card.appearance, clip: card.animoji ?? .empty, traits: card.traits,
                                       playStart: playStart, revealStart: nil, brainSize: 140)
                            .onTapGesture { playStart = .now }
                        Text(card.displayName).font(.title3.weight(.bold)).foregroundStyle(Theme.ink)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section {
                    Toggle(isOn: $bindable.shareOptions.includeAnimoji) {
                        Label("My move", systemImage: "face.smiling")
                    }
                    Toggle(isOn: $bindable.shareOptions.includeTraits) {
                        Label("Traits", systemImage: "sparkles")
                    }
                } header: {
                    Text("Travels with your brain")
                } footer: {
                    Text("Your look and name always go. Never your moments, rings or health data.")
                }

                if model.shareOptions.includeTraits && !candidates.isEmpty {
                    Section {
                        ForEach(candidates) { discovery in
                            let isOn = selected.contains(discovery.id)
                            Button {
                                toggle(discovery.id, in: &bindable.shareOptions)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isOn ? Theme.pinkDeep : Theme.inkSoft)
                                    Text(discovery.title).foregroundStyle(Theme.ink)
                                }
                            }
                            .disabled(!isOn && selected.count >= ShareOptions.maxHighlights)
                        }
                    } header: {
                        Text("Pick up to \(ShareOptions.maxHighlights)")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("What friends see")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear {
                if model.shareOptions.selectedDiscoveryIDs.isEmpty {
                    model.shareOptions.selectedDiscoveryIDs = BrainCardFactory.defaultSelection(repo.rankedDiscoveries, hunches: repo.snapshot.hunches)
                }
            }
        }
    }

    private func toggle(_ id: String, in options: inout ShareOptions) {
        if let index = options.selectedDiscoveryIDs.firstIndex(of: id) {
            options.selectedDiscoveryIDs.remove(at: index)
        } else if options.selectedDiscoveryIDs.count < ShareOptions.maxHighlights {
            options.selectedDiscoveryIDs.append(id)
        }
    }
}
