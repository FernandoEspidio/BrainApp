import SwiftUI
import UIKit

/// TEST SCREEN (not final UI): swap brain cards between two iPhones without Internet.
/// One phone taps "Host", the other "Join" and picks it from the list. A live log shows each step.
struct PeerToPeerTestView: View {
    @Environment(AppModel.self) private var model
    @State private var session = PeerToPeerSession()
    @State private var role = 0
    @State private var shownName = ""
    @State private var saved = false
    @State private var forceDirect = true

    var body: some View {
        let repo = model.repository
        let card = currentCard()

        List {
            Section {
                Text("Test only. Keep Wi-Fi ON on both phones (it doesn't need to be connected to any network: Airplane mode + Wi-Fi back on works). Bluetooth ON helps discovery. Keep the app open and screens on.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
            }

            Section("Your card") {
                TextField("Name shown to the other phone", text: $shownName)
                BrainCardView(card: card)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }

            Section("Connect") {
                Picker("Role", selection: $role) {
                    Text("Host").tag(0)
                    Text("Join").tag(1)
                }
                .pickerStyle(.segmented)
                .disabled(isBusy)

                Text(session.phase.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusColor)

                if role == 0 {
                    Button(isBusy ? "Stop" : "Start hosting") {
                        if isBusy { session.stop() } else { saved = false; session.startHosting(card: card) }
                    }
                } else {
                    Button(isBusy ? "Stop" : "Search nearby phones") {
                        if isBusy { session.stop() } else { saved = false; session.startBrowsing() }
                    }
                    Toggle("Force direct peer-to-peer (awdl)", isOn: $forceDirect)
                        .font(.subheadline)
                    ForEach(session.peers) { peer in
                        Button {
                            session.connect(to: peer, card: card, forceDirect: forceDirect)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(peer.name, systemImage: "iphone.radiowaves.left.and.right")
                                Text("Seen on: \(peer.interfaceNames.isEmpty ? "unknown" : peer.interfaceNames.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.inkSoft)
                            }
                        }
                    }
                }
            }

            if let received = session.received {
                Section("Received") {
                    BrainCardView(card: received)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    Button(saved ? "Saved to Nearby friends ✓" : "Save as friend") {
                        repo.addFriend(received, via: .peerToPeer)
                        saved = true
                    }
                    .disabled(saved)
                }
            }

            Section {
                if session.log.isEmpty {
                    Text("Nothing yet").foregroundStyle(Theme.inkSoft)
                }
                ForEach(session.log.reversed()) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Text(line.date.formatted(.dateTime.hour().minute().second()))
                            .foregroundStyle(Theme.inkSoft)
                        Text(line.text)
                    }
                    .font(.system(.caption, design: .monospaced))
                }
            } header: {
                HStack {
                    Text("Log")
                    Spacer()
                    Button("Clear") { session.clearLog() }.font(.caption)
                }
            }
        }
        .navigationTitle("P2P test")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if shownName.isEmpty {
                let user = repo.snapshot.userName
                shownName = user.isEmpty ? UIDevice.current.name : user
            }
            UIApplication.shared.isIdleTimerDisabled = true // keep the screen on while testing
        }
        .onDisappear {
            session.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var isBusy: Bool {
        switch session.phase {
        case .hosting, .browsing, .connecting: return true
        default: return false
        }
    }

    private var statusColor: Color {
        switch session.phase {
        case .done: return Theme.Deep.mint
        case .failed: return .red
        default: return Theme.ink
        }
    }

    /// The same privacy-filtered card used for sharing, with a custom display name for the test.
    private func currentCard() -> ShareableBrainCard {
        let repo = model.repository
        var card = model.makeCard(options: ShareOptions(selectedDiscoveryIDs: BrainCardFactory.defaultSelection(repo.rankedDiscoveries)))
        let name = shownName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { card.displayName = String(name.prefix(40)) }
        return card
    }
}
