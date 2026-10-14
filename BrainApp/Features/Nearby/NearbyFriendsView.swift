import SwiftUI

/// Companion exchange with nearby people, without Internet.
/// The view only knows `NearbySharingCoordinator`; the concrete transport (Wi-Fi Aware, simulation…)
/// is chosen in `NearbyTransportFactory`.
struct NearbyFriendsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let repo = model.repository
        let nearby = model.nearby

        List {
            Section {
                Text("Share your companion with someone right next to you. The connection is direct between devices, with no Internet or servers.")
            }

            Section {
                NavigationLink {
                    PeerToPeerTestView()
                } label: {
                    Label("Test: swap cards with a nearby iPhone", systemImage: "antenna.radiowaves.left.and.right")
                }
                NavigationLink {
                    ThrowTestView()
                } label: {
                    Label("Test: throw your brain (+ distance)", systemImage: "hand.point.up.left.fill")
                }
            } footer: {
                Text("Uses peer-to-peer Wi-Fi through Apple's Network framework. Works today on any two iPhones, no Internet.")
            }

            Section("What gets shared") {
                Label("Avatar, name, stage and up to \(ShareOptions.maxHighlights) discoveries, without schedules or health data.",
                      systemImage: "checkmark.shield")
                Label("Never: entries, schedules, ratings or notes.", systemImage: "hand.raised")
            }

            Section("Connect") {
                if let transport = nearby.primaryTransport {
                    Text(transport.requirementsNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    #if WIFI_AWARE_ENABLED && canImport(WiFiAware)
                    if #available(iOS 26.0, *) {
                        if transport.kind == .wifiAware {
                            WiFiAwarePairingRows()
                        }
                    }
                    #endif

                    switch nearby.state {
                    case .idle:
                        startButtons
                    case .failed(let message):
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        startButtons
                    case .working(let role):
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(role == .host
                                 ? "Waiting for a paired device to connect…"
                                 : "Looking for paired devices nearby…")
                        }
                        Button("Cancel", role: .cancel) { nearby.cancel() }
                    case .received(let card):
                        Label("You received \(card.displayName)'s companion", systemImage: "person.crop.circle.badge.checkmark")
                        Button("Done") { nearby.reset() }
                    }
                } else {
                    Label("Not available in this build", systemImage: "wifi.slash")
                    Text(NearbyTransportFactory.unavailableExplanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Friends") {
                if repo.snapshot.friends.isEmpty {
                    Text("You haven't swapped companions yet.").foregroundStyle(.secondary)
                }
                ForEach(repo.snapshot.friends) { friend in
                    NavigationLink {
                        FriendDetailView(friend: friend)
                    } label: {
                        HStack(spacing: 12) {
                            BrainAvatarView(appearance: friend.card.appearance, stage: friend.card.stage, size: 34, animated: false)
                                .frame(width: 50, height: 50)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(friend.card.displayName).font(.headline)
                                Text("\(friend.card.stageName) · via \(friend.via.label)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { repo.snapshot.friends[$0].id }
                    ids.forEach { repo.removeFriend($0) }
                }
            }
        }
        .navigationTitle("Nearby friends")
    }

    @ViewBuilder
    private var startButtons: some View {
        Button("Wait for a friend", systemImage: "antenna.radiowaves.left.and.right") { start(.host) }
        Button("Find a friend", systemImage: "magnifyingglass") { start(.join) }
    }

    private func start(_ role: NearbySharingCoordinator.Role) {
        let repo = model.repository
        let options = ShareOptions(selectedDiscoveryIDs: BrainCardFactory.defaultSelection(repo.rankedDiscoveries))
        let card = model.makeCard(options: options)
        let kind = model.nearby.primaryTransport?.kind ?? .demo
        model.nearby.start(role, card: card) { received in
            repo.addFriend(received, via: kind)
        }
    }
}

struct FriendDetailView: View {
    let friend: Friend

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                BrainCardView(card: friend.card)
                Text("Received on \(friend.receivedAt.formatted(date: .long, time: .shortened)) via \(friend.via.label).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle(friend.card.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
