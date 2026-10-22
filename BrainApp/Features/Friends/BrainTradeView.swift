import SwiftUI

/// The whole trade, full screen:
/// searching (bush) → "You found a brain named Sam" (both confirm, same 3 emojis) →
/// portal (swipe your brain in) → their brain arrives, traits orbit, their move plays.
/// Host/join and the network never show: both phones simply look for each other.
/// A brain you already met is recognized and simply updated.
struct BrainTradeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var session: BrainLinkSession?
    /// What we had of this friend before the trade (to show what changed).
    @State private var previousCard: ShareableBrainCard?
    @State private var showPractice = false

    var body: some View {
        let repo = model.repository
        let phase = session?.phase ?? .idle

        ZStack {
            background(for: phase).ignoresSafeArea()

            switch phase {
            case .idle, .searching, .found, .waitingForPeer, .declined:
                searchStage(phase: phase, appearance: repo.snapshot.companion)
                    .transition(.opacity)
            case .linked(let peer), .sent(let peer):
                PortalStage(appearance: repo.snapshot.companion, peer: peer,
                            hasSent: phase == .sent(peer), peerHasSent: session?.peerHasSent ?? false,
                            aim: session?.aim, aimAvailable: session?.aimAvailable ?? false) {
                    session?.sendBrain()
                }
                .transition(.opacity)
            case .arrived(_, let card):
                ArrivalStage(card: card, previous: previousCard, isSaved: savesFriends) { dismiss() }
                    .transition(.opacity)
            case .failed(let message):
                failure(message)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topLeading) {
            if !isArrived(phase) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.85), in: Circle())
                }
                .padding()
                .accessibilityLabel("Close")
            }
        }
        .animation(.easeInOut(duration: 0.45), value: phase)
        .sensoryFeedback(trigger: phase) { _, new in
            switch new {
            case .found: return .impact(weight: .medium)
            case .linked: return .success
            case .declined, .failed: return .warning
            default: return nil
            }
        }
        .onAppear {
            guard session == nil else { return }
            let link = model.makeBrainLink()
            session = link
            link.start(card: model.makeCard())
        }
        .onDisappear { session?.stop() }
        .onChange(of: phase) { _, new in
            if case .arrived(_, let card) = new {
                previousCard = repo.snapshot.friends.first { $0.card.id == card.id }?.card
                if savesFriends { repo.addFriend(card, via: session?.mode == .simulated ? .demo : .peerToPeer) }
            }
        }
        .task(id: phase == .searching) {
            // Nobody showing up? After a few seconds, offer a practice trade.
            guard phase == .searching, session?.mode == .network else { return }
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { withAnimation(.snappy) { showPractice = true } }
        }
    }

    /// Practice brains are fictional: they're only kept when you're looking at a sample profile,
    /// never mixed into your real data.
    private var savesFriends: Bool {
        session?.mode == .network || model.repository.isDemo
    }

    private func knownFriend(_ peer: BrainLinkSession.Peer?) -> Friend? {
        guard let id = peer?.cardID else { return nil }
        return model.repository.snapshot.friends.first { $0.card.id == id }
    }

    private func isArrived(_ phase: BrainLinkSession.Phase) -> Bool {
        if case .arrived = phase { return true }
        return false
    }

    private func background(for phase: BrainLinkSession.Phase) -> LinearGradient {
        switch phase {
        case .linked, .sent, .arrived:
            return LinearGradient(colors: [Color(hex: 0xE3DEFA), Theme.Tint.sky, Theme.cream], startPoint: .top, endPoint: .bottom)
        default:
            return LinearGradient(colors: [Theme.Tint.sky.opacity(0.7), Theme.cream], startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: - Searching + found popup

    private func searchStage(phase: BrainLinkSession.Phase, appearance: CompanionAppearance) -> some View {
        let found: Bool = {
            switch phase {
            case .found, .waitingForPeer: return true
            default: return false
            }
        }()
        return VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text(found ? "Found one!" : "Looking for brains…")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.opacity)
                Text("Ask your friend to open Friends and tap Trade brains. Stay close to each other.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .opacity(found ? 0 : 1)
            }
            .padding(.top, 70)

            // Kept in the top half so it stays visible above the "found" card.
            SearchScene(appearance: appearance, found: found, foundAppearance: knownFriend(session?.peer)?.card.appearance)
                .frame(height: 340)
                .padding(.top, 10)

            Spacer(minLength: 0)
            if !found {
                SearchingDots().padding(.bottom, showPractice ? 16 : 50)
                if showPractice {
                    Button {
                        showPractice = false
                        session?.startPractice()
                    } label: {
                        Label("Nobody around? Practice with a demo brain", systemImage: "theatermasks")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(SoftButtonStyle())
                    .padding(.bottom, 40)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let peer = session?.peer {
                FoundCard(peer: peer, known: knownFriend(peer), phase: phase,
                          onAccept: { session?.accept() },
                          onDecline: { session?.decline() })
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: session?.peer)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Canvas { context, size in BrainDrawing.drawMystery(context, size: size, time: nil) }
                .frame(width: 140, height: 140)
                .opacity(0.6)
            Text("Couldn't trade this time")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Spacer()
            VStack(spacing: 10) {
                Button("Try again") { session?.start(card: model.makeCard()) }
                    .buttonStyle(InkButtonStyle())
                Button("Close") { dismiss() }
                    .buttonStyle(SoftLargeButtonStyle())
            }
            .padding()
        }
    }
}

// MARK: - Found card

/// "You found a brain named Sam": shown on BOTH phones. Same 3 emojis on each screen
/// so people can check they matched with the right person.
private struct FoundCard: View {
    let peer: BrainLinkSession.Peer
    /// Set when this brain is already in your collection.
    let known: Friend?
    let phase: BrainLinkSession.Phase
    var onAccept: () -> Void
    var onDecline: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(headline)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.inkSoft)
            Text(peer.name)
                .font(.largeTitle.weight(.heavy))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if case .declined = phase {
                Text("That wasn't them. Still looking…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
            } else {
                if let known {
                    Text("You met on \(known.receivedAt.formatted(date: .abbreviated, time: .omitted)). Trade again to get their latest brain.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 10) {
                    ForEach(Array(peer.matchCode.enumerated()), id: \.offset) { _, emoji in
                        Text(emoji)
                            .font(.system(size: 30))
                            .frame(width: 54, height: 54)
                            .background(Theme.cream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Match code: \(peer.matchCode.joined(separator: " "))")
                Text("Check that \(peer.name) sees the same")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
            }

            switch phase {
            case .found:
                HStack(spacing: 12) {
                    Button(known == nil ? "Not them" : "Not now", action: onDecline)
                        .buttonStyle(SoftLargeButtonStyle())
                    Button(known == nil ? "Trade!" : "Update!", action: onAccept)
                        .buttonStyle(InkButtonStyle())
                }
                .padding(.top, 4)
            case .waitingForPeer:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Waiting for \(peer.name) to say yes…")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                }
                .padding(.vertical, 12)
                Button("Cancel", action: onDecline)
                    .font(.subheadline.weight(.semibold))
                    .tint(Theme.inkSoft)
            default:
                EmptyView()
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: Theme.ink.opacity(0.12), radius: 24, y: 8)
    }

    private var headline: String {
        if case .declined = phase { return "Oops" }
        return known == nil ? "You found a brain named" : "Look who's back!"
    }
}

private struct SearchingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 8) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Theme.pinkDeep)
                        .frame(width: 9, height: 9)
                        .opacity(0.3 + 0.7 * max(0, sin(t * 4 - Double(index) * 0.8)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Portal

/// Your brain (facing you, looking up excitedly) at the bottom, the vortex at the top. Three ways to send it:
/// - Swipe it up: the closer it gets, the stronger the pull, the rumble and the shake.
/// - Point your iPhone at your friend and walk closer (UWB phones): the portal leans toward them and
///   charges; once you're close and aimed, hold still for a moment and it goes.
/// - Tap "Send" (also the VoiceOver action): it charges and goes on its own.
private struct PortalStage: View {
    let appearance: CompanionAppearance
    let peer: BrainLinkSession.Peer
    let hasSent: Bool
    let peerHasSent: Bool
    var aim: NearbyRanging.Reading?
    var aimAvailable = false
    var onSent: () -> Void

    /// Close and aimed enough to start the "hold it there" moment.
    private static let holdThreshold = 0.8
    private static let holdSeconds = 1.2
    @State private var holdStart: Date?

    @State private var drag: CGSize = .zero
    @State private var autoCharge: Date?
    @State private var suckStart: Date?
    @State private var haptics = PortalHaptics()
    @State private var lastHapticLevel = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let portal = CGPoint(x: w / 2, y: h * 0.25)
            let home = CGPoint(x: w / 2, y: h * 0.74)
            let brainSize = min(w * 0.46, 190)

            TimelineView(.animation) { timeline in
                let now = timeline.date
                let t = now.timeIntervalSinceReferenceDate
                let charge = intensity(now: now, distance: home.y - portal.y)
                let suck = suckProgress(now: now)
                let shake = reduceMotion ? 0 : CGFloat(sin(t * 70) * 4 * max(0, charge - 0.45) / 0.55)
                // The portal leans toward where the friend is.
                let lean = CGFloat(sin(Double(aim?.horizontalAngle ?? 0))) * w * 0.22
                let portalAt = CGPoint(x: portal.x + (suckStart == nil ? lean : 0), y: portal.y)
                let brain = brainPosition(home: home, portal: portalAt, suck: suck)

                ZStack {
                    PortalView(intensity: max(charge, hasSent ? 0.35 : 0) + suck * 0.4, time: t)
                        .frame(width: w * 0.8, height: w * 0.8 * 0.75)
                        .offset(x: shake * 0.6, y: -shake * 0.3)
                        .position(portalAt)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: lean)

                    if let holdStart, suckStart == nil {
                        let progress = min(now.timeIntervalSince(holdStart) / Self.holdSeconds, 1)
                        ZStack {
                            StaticRing(fraction: progress, color: Theme.lavender, lineWidth: 6)
                            Text("Hold it there…")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.white, in: Capsule())
                                .offset(y: -brainSize * 0.62)
                        }
                        .frame(width: brainSize * 1.1, height: brainSize * 1.1)
                        .position(brain)
                    }

                    WindStreaks(from: CGPoint(x: brain.x, y: brain.y - brainSize * 0.4), to: portalAt,
                                intensity: hasSent ? 0.25 : charge, time: t)

                    if !hasSent || suck < 1 {
                        // Facing you, looking up at the portal: the closer it gets, the bigger the happy scream.
                        BrainPoseView(appearance: appearance, mood: charge > 0.35 || suck > 0 ? .celebrating : .idle,
                                      pose: screamPose(charge: charge, suck: suck, time: reduceMotion ? 0 : t),
                                      showsHalo: false)
                        .frame(width: brainSize, height: brainSize)
                        // Stretched toward the portal and spun as it's pulled in.
                        .scaleEffect(x: 1 - 0.55 * suck - 0.05 * charge, y: 1 - 0.75 * suck + 0.12 * charge)
                        .rotationEffect(.degrees(suck * 300 + Double(drag.width) * 0.05))
                        .opacity(1 - pow(suck, 3))
                        // Little hops of joy that get faster and higher as the portal pulls.
                        .offset(x: shake, y: reduceMotion ? 0 : -abs(CGFloat(sin(t * (3 + 6 * charge)))) * CGFloat(4 + 8 * charge))
                        .overlay(alignment: .top) { shout(charge: charge, suck: suck, size: brainSize) }
                        .position(brain)
                        .gesture(dragGesture(home: home, portal: portal))
                        .accessibilityElement()
                        .accessibilityLabel("Your brain")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(named: "Send to \(peer.name)") { startAutoCharge() }
                    }
                }
                .onChange(of: Int(charge * 10)) { _, _ in updateHaptics(charge) }
                .onChange(of: aimCharge >= Self.holdThreshold) { _, holding in updateHold(holding) }
            }

            VStack(spacing: 6) {
                Spacer()
                Text(caption)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                if !hasSent {
                    if aimAvailable {
                        HStack(spacing: 6) {
                            Image(systemName: "iphone.radiowaves.left.and.right")
                            Text("Point at \(peer.name) and walk closer")
                            if let distance = aim?.distance {
                                Text(distance.formatted(.number.precision(.fractionLength(1))) + " m")
                                    .monospacedDigit()
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.white, in: Capsule())
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .transition(.opacity)
                    }
                    Button { startAutoCharge() } label: {
                        Label(aimAvailable ? "Or swipe up · tap to send" : "Swipe up · or tap to send", systemImage: "arrow.up")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(Theme.inkSoft)
                    .disabled(autoCharge != nil || suckStart != nil)
                } else {
                    ProgressView().padding(.top, 4)
                }
            }
            .padding(.bottom, 34)
            .frame(maxWidth: .infinity)
            .animation(.snappy, value: hasSent)
            .animation(.snappy, value: aimAvailable)
        }
        .onDisappear { haptics.release() }
    }

    private var caption: String {
        if hasSent { return peerHasSent ? "Here it comes!" : "Waiting for \(peer.name)'s brain…" }
        if holdStart != nil { return "Hold still…" }
        if peerHasSent { return "\(peer.name)'s brain is on its way. Send yours!" }
        return "Send your brain to \(peer.name)"
    }

    // MARK: Pull

    private func dragGesture(home: CGPoint, portal: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard suckStart == nil, !hasSent else { return }
                // Upward moves count fully; sideways and downward are resisted.
                drag = CGSize(width: value.translation.width * 0.4, height: min(0, value.translation.height) + max(0, value.translation.height) * 0.2)
                if -drag.height > (home.y - portal.y) * 0.62 { triggerSuck() }
            }
            .onEnded { value in
                guard suckStart == nil else { return }
                let flung = value.predictedEndTranslation.height < -(home.y - portal.y) * 0.9
                if flung && -drag.height > (home.y - portal.y) * 0.3 {
                    triggerSuck()
                } else {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { drag = .zero }
                    haptics.release()
                }
            }
    }

    private func startAutoCharge() {
        guard autoCharge == nil, suckStart == nil, !hasSent else { return }
        autoCharge = .now
        Task {
            try? await Task.sleep(for: .seconds(1.3))
            triggerSuck()
        }
    }

    private func triggerSuck() {
        guard suckStart == nil else { return }
        suckStart = .now
        haptics.whoosh()
        Task {
            try? await Task.sleep(for: .seconds(0.7))
            onSent()
        }
    }

    // MARK: Face

    private func screamPose(charge c: Double, suck: Double, time t: Double) -> FacePose {
        var pose = FacePose()
        // Excited, not smug: big smile, outer brows up, eyes wide, looking up at the portal.
        pose.smile = 0.95
        pose.gazeY = -0.8
        pose.headPitch = -0.2
        // Inner + outer brows together keep them level and lifted (outer alone reads as a frown).
        pose.browUp = Float(0.55 + 0.35 * c)
        pose.leftBrowRaise = Float(0.2 + 0.4 * c)
        pose.rightBrowRaise = Float(0.2 + 0.4 * c)
        pose.eyeWide = Float(0.35 + 0.6 * c)
        pose.jawOpen = Float(0.18 + 0.7 * c)          // "aaah!" grows with the pull
        pose.headRoll = Float(sin(t * (2.4 + 6 * c)) * (0.06 + 0.06 * c))
        if c < 0.1 && t.truncatingRemainder(dividingBy: 3.4) < 0.13 {
            pose.leftEyeOpen = 0.05
            pose.rightEyeOpen = 0.05
        }
        if suck > 0 {
            // ^O^ Wheee!
            pose.jawOpen = 1
            pose.squint = 1
            pose.eyeWide = 0
            pose.gazeY = 0
        }
        return pose
    }

    @ViewBuilder
    private func shout(charge: Double, suck: Double, size: CGFloat) -> some View {
        let text: String? = suck > 0 ? "Wheee!" : (charge > 0.55 ? "Ooh…!" : nil)
        if let text {
            Text(text)
                .font(.system(size: suck > 0 ? 22 : 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.white, in: Capsule())
                .shadow(color: Theme.ink.opacity(0.1), radius: 6, y: 2)
                .rotationEffect(.degrees(-8))
                .offset(x: size * 0.42, y: -size * 0.12)
                .opacity(1 - suck)
                .transition(.scale.combined(with: .opacity))
                .accessibilityHidden(true)
        }
    }

    // MARK: Aim (UWB)

    /// 0…1 from how close you are (1.6 m → 0, 0.3 m → 1) and, when the phone knows it, how well you're aiming.
    private var aimCharge: Double {
        guard !hasSent, let distance = aim?.distance else { return 0 }
        let closeness = min(max((1.6 - Double(distance)) / 1.3, 0), 1)
        var alignment = 1.0
        if let angle = aim?.horizontalAngle { alignment = min(max(1 - Double(abs(angle)) / 0.7, 0), 1) }
        return closeness * alignment
    }

    private func updateHold(_ holding: Bool) {
        guard suckStart == nil, !hasSent else { return }
        guard holding else { holdStart = nil; return }
        let start = Date.now
        holdStart = start
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        Task {
            try? await Task.sleep(for: .seconds(Self.holdSeconds))
            if holdStart == start { triggerSuck() }
        }
    }

    private func intensity(now: Date, distance: CGFloat) -> Double {
        if suckStart != nil { return 1 }
        var level = Double(min(max(-drag.height / (distance * 0.62), 0), 1))
        level = max(level, aimCharge)
        if let autoCharge { level = max(level, min(now.timeIntervalSince(autoCharge) / 1.3, 1)) }
        return level
    }

    private func suckProgress(now: Date) -> Double {
        guard let suckStart else { return hasSent ? 1 : 0 }
        let p = min(now.timeIntervalSince(suckStart) / 0.7, 1)
        return p * p
    }

    private func brainPosition(home: CGPoint, portal: CGPoint, suck: Double) -> CGPoint {
        let held = CGPoint(x: home.x + drag.width, y: home.y + drag.height)
        // Auto-charge leans the brain toward the portal a bit.
        let start = autoCharge != nil && drag == .zero ? CGPoint(x: home.x, y: home.y - 24) : held
        return CGPoint(x: start.x + (portal.x - start.x) * suck, y: start.y + (portal.y - start.y) * suck)
    }

    private func updateHaptics(_ level: Double) {
        guard suckStart == nil else { return }
        if level > 0.05 {
            haptics.charge(level)
        } else if lastHapticLevel > 0.05 {
            haptics.release()
        }
        lastHapticLevel = level
    }
}

// MARK: - Arrival

/// Their brain drops out of the portal, lands, its traits pop out and orbit, then it plays its move.
private struct ArrivalStage: View {
    let card: ShareableBrainCard
    /// Their card from a previous trade, if any (then this is an update).
    var previous: ShareableBrainCard?
    var isSaved = true
    var onDone: () -> Void

    @State private var arrivedAt = Date.now
    @State private var playStart: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let fall: Double = 0.85

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height

            TimelineView(.animation) { timeline in
                let now = timeline.date
                let t = now.timeIntervalSinceReferenceDate
                let p = reduceMotion ? 1 : min(now.timeIntervalSince(arrivedAt) / fall, 1)
                let portalFade = max(0, 1 - now.timeIntervalSince(arrivedAt) / 1.4)

                ZStack {
                    PortalView(intensity: 0.6 * portalFade, time: t)
                        .frame(width: w * 0.8 * (0.6 + 0.4 * portalFade), height: w * 0.6 * (0.6 + 0.4 * portalFade))
                        .opacity(portalFade)
                        .position(x: w / 2, y: h * 0.25)

                    BrainOrbitView(appearance: card.appearance, clip: card.animoji ?? .empty, traits: card.traits,
                                   playStart: playStart ?? arrivedAt.addingTimeInterval(fall + 0.3 + Double(card.traits.count) * 0.32 + 0.3),
                                   revealStart: arrivedAt.addingTimeInterval(fall + 0.15), brainSize: 175)
                        .scaleEffect(0.25 + 0.75 * easeOutBack(p))
                        .rotationEffect(.degrees((1 - p) * -260))
                        .position(x: w / 2, y: h * 0.25 + (h * 0.43 - h * 0.25) * easeOutBounce(p))
                        .onTapGesture { playStart = .now }
                }
            }

            VStack(spacing: 8) {
                Spacer()
                Text(previous == nil ? "\(card.displayName)'s brain arrived!" : "\(card.displayName)'s brain is up to date!")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                if previous != nil {
                    changesRow
                }
                if isSaved {
                    Label(previous == nil ? "Added to your brains" : "Updated in your brains", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Deep.mint)
                } else {
                    Label("Practice brain · not saved", systemImage: "theatermasks")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
                HStack(spacing: 12) {
                    if !(card.animoji ?? .empty).isEmpty {
                        Button { playStart = .now } label: { Label("Replay", systemImage: "play.fill") }
                            .buttonStyle(SoftLargeButtonStyle())
                    }
                    Button("Done", action: onDone)
                        .buttonStyle(InkButtonStyle())
                }
                .padding(.top, 10)
            }
            .padding()
            .padding(.bottom, 12)
        }
        .sensoryFeedback(.success, trigger: arrivedAt)
    }

    /// What changed since the last trade, as small chips ("New look", "+1 trait"…).
    private var changes: [(String, String)] {
        guard let previous else { return [] }
        var list: [(String, String)] = []
        if previous.appearance.colorIndex != card.appearance.colorIndex || previous.appearance.outfit != card.appearance.outfit {
            list.append(("New look", "tshirt"))
        }
        if (previous.animoji ?? .empty) != (card.animoji ?? .empty) { list.append(("New move", "face.smiling")) }
        let before = Set(previous.highlights.map(\.title))
        let added = card.highlights.filter { !before.contains($0.title) }.count
        if added > 0 { list.append(("+\(added) trait\(added == 1 ? "" : "s")", "sparkles")) }
        if card.stage > previous.stage { list.append(("Grew: \(card.stageName)", "leaf.fill")) }
        return list
    }

    @ViewBuilder
    private var changesRow: some View {
        if changes.isEmpty {
            Text("Same brain you know 💛")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
        } else {
            HStack(spacing: 6) {
                ForEach(changes, id: \.0) { change in
                    Label(change.0, systemImage: change.1)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.white, in: Capsule())
                }
            }
        }
    }

    private func easeOutBack(_ x: Double) -> Double {
        let c1 = 1.4, c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }

    private func easeOutBounce(_ x: Double) -> Double {
        let n1 = 7.5625, d1 = 2.75
        if x < 1 / d1 { return n1 * x * x }
        if x < 2 / d1 { let y = x - 1.5 / d1; return n1 * y * y + 0.75 }
        if x < 2.5 / d1 { let y = x - 2.25 / d1; return n1 * y * y + 0.9375 }
        let y = x - 2.625 / d1
        return n1 * y * y + 0.984375
    }
}
