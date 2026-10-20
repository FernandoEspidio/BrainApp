import SwiftUI
import UIKit

/// TEST SCREEN: connect two iPhones, then FLICK your brain upward to throw it to your friend.
/// It lands on their screen with a bounce. Distance/direction (Nearby Interaction) is shown when available
/// and can optionally gate the throw ("aim"), but the throw works without it.
struct ThrowTestView: View {
    @Environment(AppModel.self) private var model
    @State private var session = ThrowSession()
    @State private var role = 0
    @State private var name = ""
    @State private var useRanging = true
    @State private var cameraAssist = false
    @State private var requireAim = false

    // Throw animation
    @State private var drag: CGSize = .zero
    @State private var flying = false
    @State private var landed = false
    @State private var savedCount = 0

    var body: some View {
        let repo = model.repository
        ZStack {
            Theme.cream.ignoresSafeArea()
            if session.isConnected {
                arena(repo: repo)
            } else {
                setup
            }
            if let card = session.incoming {
                landing(card: card, repo: repo)
            }
        }
        .navigationTitle("Throw")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.isConnected {
                Button("Disconnect") { session.stop() }
            }
        }
        .onAppear {
            if name.isEmpty {
                let user = repo.snapshot.userName
                name = user.isEmpty ? UIDevice.current.name : user
            }
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            session.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: session.incomingCount) { _, _ in
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: - Setup (before connecting)

    private var setup: some View {
        List {
            Section {
                Text(NearbyRanging.capabilitySummary)
                    .font(.system(.footnote, design: .monospaced))
            } header: {
                Text("This iPhone")
            } footer: {
                Text("Distance needs iPhone 11 or later with UWB. Direction is unreliable on newer models; camera assistance may help.")
            }

            Section("Setup") {
                TextField("Your name", text: $name)
                Toggle("Measure distance (Nearby Interaction)", isOn: $useRanging)
                    .disabled(!NearbyRanging.isSupported)
                Toggle("Camera assistance (for direction)", isOn: $cameraAssist)
                    .disabled(!useRanging)
            }

            Section("Connect") {
                Picker("Role", selection: $role) {
                    Text("Host").tag(0)
                    Text("Join").tag(1)
                }
                .pickerStyle(.segmented)
                Text(session.phase.label).font(.subheadline.weight(.semibold))
                if role == 0 {
                    Button("Start hosting") {
                        session.startHosting(name: name, ranging: useRanging && NearbyRanging.isSupported, cameraAssistance: cameraAssist)
                    }
                } else {
                    Button("Search nearby phones") {
                        session.startBrowsing(name: name, ranging: useRanging && NearbyRanging.isSupported, cameraAssistance: cameraAssist)
                    }
                    ForEach(session.peers) { peer in
                        Button {
                            session.connect(to: peer)
                        } label: {
                            Label(peer.name.replacingOccurrences(of: ThrowSession.marker, with: ""),
                                  systemImage: "iphone.radiowaves.left.and.right")
                        }
                    }
                }
            }

            logSection
        }
    }

    private var logSection: some View {
        Section("Log") {
            ForEach(session.log.reversed()) { line in
                Text(line.text).font(.system(.caption, design: .monospaced))
            }
        }
    }

    // MARK: - Arena (connected)

    private var angleDegrees: Double? {
        session.reading.horizontalAngle.map { Double($0) * 180 / .pi }
    }

    private var isAimed: Bool {
        guard let angle = angleDegrees else { return false }
        return abs(angle) < 20
    }

    private var canThrow: Bool { !requireAim || isAimed }

    private func arena(repo: LocalRepository) -> some View {
        VStack(spacing: 16) {
            // Friend target at the top.
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isAimed ? Theme.Tint.mint : Theme.Tint.rose)
                        .frame(width: 96, height: 96)
                    if let angle = angleDegrees {
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(Theme.ink)
                            .rotationEffect(.degrees(angle))
                            .animation(.easeOut(duration: 0.2), value: angle)
                    } else {
                        Image(systemName: "person.fill").font(.system(size: 34)).foregroundStyle(Theme.ink)
                    }
                }
                Text(session.phase.label.replacingOccurrences(of: "Connected with ", with: ""))
                    .font(.headline).foregroundStyle(Theme.ink)
                Text(rangingText).font(.subheadline).foregroundStyle(Theme.inkSoft)
            }
            .padding(.top, 12)

            if angleDegrees != nil {
                Toggle("Only throw when aiming", isOn: $requireAim)
                    .font(.subheadline)
                    .padding(.horizontal, 40)
            }

            Spacer()

            Text(canThrow ? "Flick your brain up to throw it" : "Point your phone at your friend")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.inkSoft)

            // My brain: drag up and release to throw.
            BrainAvatarView(appearance: repo.snapshot.companion, stage: repo.companionStage,
                            mood: flying ? .celebrating : .idle, size: 180, animated: !flying)
                .offset(x: drag.width * 0.3, y: flying ? -900 : min(drag.height, 30))
                .scaleEffect(flying ? 0.35 : 1 - min(max(-drag.height, 0), 200) / 1000)
                .rotationEffect(.degrees(flying ? 360 : Double(drag.width) / 10))
                .opacity(flying ? 0 : 1)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard !flying else { return }
                            drag = value.translation
                        }
                        .onEnded { value in
                            let flickedUp = value.translation.height < -110 || value.predictedEndTranslation.height < -350
                            if flickedUp && canThrow {
                                throwBrain(repo: repo)
                            } else {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { drag = .zero }
                            }
                        }
                )
                .padding(.bottom, 40)
                .accessibilityAction(named: "Throw to friend") { if canThrow { throwBrain(repo: repo) } }

            if savedCount > 0 {
                Text("Friends saved this session: \(savedCount)").font(.caption).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private var rangingText: String {
        guard session.rangingActive else { return "Distance: off" }
        guard let distance = session.reading.distance else { return "Measuring…" }
        var text = String(format: "%.2f m away", distance)
        if let angle = angleDegrees {
            text += String(format: " · %.0f°", angle)
        } else {
            text += " · no direction on this device"
        }
        return text
    }

    private func throwBrain(repo: LocalRepository) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let card = model.makeCard()
        var named = card
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { named.displayName = String(trimmed.prefix(40)) }

        withAnimation(.easeIn(duration: 0.45)) { flying = true }
        session.throwCard(named)
        // Bring a fresh brain back after it leaves.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            drag = .zero
            flying = false
        }
    }

    // MARK: - Landing (receiver)

    private func landing(card: ShareableBrainCard, repo: LocalRepository) -> some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
                .onTapGesture { session.dismissIncoming(); landed = false }
            VStack(spacing: 16) {
                Text("Caught one! 🎯").font(.title2.weight(.bold)).foregroundStyle(.white)
                BrainCardView(card: card)
                    .frame(maxWidth: 320)
                    .offset(y: landed ? 0 : -700)
                    .rotationEffect(.degrees(landed ? 0 : -25))
                    .scaleEffect(landed ? 1 : 0.4)
                HStack(spacing: 12) {
                    Button("Save as friend") {
                        repo.addFriend(card, via: .peerToPeer)
                        savedCount += 1
                        session.dismissIncoming()
                        landed = false
                    }
                    .buttonStyle(InkButtonStyle())
                    Button("Dismiss") {
                        session.dismissIncoming()
                        landed = false
                    }
                    .buttonStyle(SoftButtonStyle())
                }
                .padding(.horizontal, 32)
            }
        }
        .onAppear {
            landed = false
            withAnimation(.spring(response: 0.55, dampingFraction: 0.55)) { landed = true }
        }
        .onChange(of: session.incomingCount) { _, _ in
            landed = false
            withAnimation(.spring(response: 0.55, dampingFraction: 0.55)) { landed = true }
        }
    }
}
