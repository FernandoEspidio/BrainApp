import SwiftUI

/// PROTOTYPE. Today, the only screen: the buddy says one thing, each guess shows how far it is,
/// and one question a day moves every guess forward. Day 14 opens the newest verdict.
struct PrototypeTodayView: View {
    let day: PrototypeData.Day
    var name = ""
    var alikeDays = false

    /// The open guesses, at most 3. A settled one leaves its slot with "Test another guess".
    @State private var slots: [PrototypeData.Guess]
    /// Settled guesses that freed their slot.
    @State private var found: [PrototypeData.Guess] = []
    /// Picked with "Test another guess": they start at 0.
    @State private var fresh: Set<String> = []
    @State private var answer: Int?
    @State private var doneToday: Set<String> = []
    @State private var reveal: PrototypeData.Verdict?
    /// Set by the reveal's "Test another guess", picked once the reveal has closed.
    @State private var replacing: PrototypeData.Guess?
    @State private var picking: PrototypeData.Guess?
    @State private var poke = 0

    init(day: PrototypeData.Day, name: String = "", guesses: [PrototypeData.Guess], alikeDays: Bool = false) {
        self.day = day
        self.name = name
        self.alikeDays = alikeDays
        _slots = State(initialValue: guesses)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(name.isEmpty ? "Today" : "Hi, \(name)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)

                buddy

                ForEach(slots) { guess in
                    card(for: guess)
                }

                DailyQuestionCard(goal: .focus, question: Goal.focus.question ?? "", answer: answer) { value in
                    withAnimation(.spring(duration: 0.6)) { answer = value }
                }

                if !found.isEmpty { foundCard }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.cream.ignoresSafeArea())
        .fullScreenCover(item: $reveal, onDismiss: {
            picking = replacing
            replacing = nil
        }) { verdict in
            PrototypeRevealView(verdict: verdict) { replacing = verdict.guess }
        }
        .sheet(item: $picking) { old in
            PrototypeNextGuessSheet(guesses: PrototypeData.guesses.filter { !slots.contains($0) && !found.contains($0) }) { new in
                replace(old, with: new)
            }
        }
        .task {
            // Day 14: Today shows first, then the newest verdict rises over it.
            guard day == .fourteen, let verdict = PrototypeData.newestVerdict(among: slots, alikeDays: alikeDays) else { return }
            try? await Task.sleep(for: .seconds(0.8))
            reveal = verdict
        }
    }

    private var buddy: some View {
        VStack(spacing: 10) {
            BrainAvatarView(appearance: CompanionAppearance(), stage: 0, mood: mood, size: 110, poke: poke)
                .onTapGesture { poke += 1 }
            Text(PrototypeData.buddyLine(on: day, guesses: openGuesses, alikeDays: alikeDays, answered: answer != nil))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
        }
        .padding(.bottom, 8)
    }

    private var mood: BrainMood {
        guard day == .fourteen else { return .idle }
        return PrototypeData.newestVerdict(among: openGuesses, alikeDays: alikeDays)?.mood ?? .idle
    }

    /// Slots without the freshly picked ones, which have nothing to say yet.
    private var openGuesses: [PrototypeData.Guess] {
        slots.filter { !fresh.contains($0.id) }
    }

    @ViewBuilder
    private func card(for guess: PrototypeData.Guess) -> some View {
        let standing = fresh.contains(guess.id)
            ? PrototypeData.Standing(status: .watching, counted: 0)
            : PrototypeData.standing(of: guess, on: day, alikeDays: alikeDays)
        switch standing.status {
        case .cantTell:
            PrototypeCantTellCard(guess: guess)
        case let status where status.isSettled:
            let verdict = PrototypeData.verdict(for: guess)
            PrototypeSettledCard(guess: guess, standing: standing, onOpen: verdict.map { verdict in { reveal = verdict } })
        default:
            // Answering the daily question counts today for every open guess.
            let counted = min(standing.counted + (answer == nil ? 0 : 1), PrototypeData.daysNeeded)
            PrototypeGuessCard(guess: guess, status: standing.status, counted: counted, doneToday: Binding(
                get: { doneToday.contains(guess.id) },
                set: { done in
                    if done { doneToday.insert(guess.id) } else { doneToday.remove(guess.id) }
                }
            ))
        }
    }

    /// Settled verdicts whose slot went to a new guess. Tap to see the reveal again.
    private var foundCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What you've found")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            ForEach(found) { guess in
                if let verdict = PrototypeData.verdict(for: guess) {
                    Button {
                        reveal = verdict
                    } label: {
                        HStack(spacing: 10) {
                            TintedIcon(symbol: guess.symbol, tint: guess.tint, size: 28)
                            Text(verdict.headline)
                                .font(.subheadline.weight(.medium))
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption.weight(.bold))
                        }
                        .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func replace(_ old: PrototypeData.Guess, with new: PrototypeData.Guess) {
        guard let index = slots.firstIndex(of: old) else { return }
        withAnimation {
            slots[index] = new
            found.append(old)
            fresh.insert(new.id)
        }
    }
}

/// An open guess: its status, how many days are counted, and for guesses the student logs, a one-tap toggle.
struct PrototypeGuessCard: View {
    let guess: PrototypeData.Guess
    let status: PrototypeData.Status
    let counted: Int
    @Binding var doneToday: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                TintedIcon(symbol: guess.symbol, tint: guess.tint, size: 36)
                VStack(alignment: .leading, spacing: 10) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) {
                            title
                            Spacer(minLength: 8)
                            PrototypeStatusPill(status: status)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            title
                            PrototypeStatusPill(status: status)
                        }
                    }
                    PrototypeProgressBar(fraction: Double(counted) / Double(PrototypeData.daysNeeded),
                                         tint: status == .watching ? Theme.pink : Theme.pinkDeep)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(guess.label): \(status.label), \(counted) of \(PrototypeData.daysNeeded) days")

            if guess.isLogged {
                Toggle("Did it today", isOn: $doneToday)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .tint(Theme.pinkDeep)
                    .padding(.leading, 48)
            }
        }
        .cardStyle()
    }

    private var title: some View {
        Text("\(guess.short) · \(counted) of \(PrototypeData.daysNeeded) days")
            .font(.headline)
            .foregroundStyle(Theme.ink)
            .contentTransition(.numericText())
    }
}

/// A settled guess: the verdict in one line. Tap to see the reveal again.
struct PrototypeSettledCard: View {
    let guess: PrototypeData.Guess
    let standing: PrototypeData.Standing
    var onOpen: (() -> Void)?

    var body: some View {
        Button {
            onOpen?()
        } label: {
            HStack(spacing: 12) {
                TintedIcon(symbol: guess.symbol, tint: guess.tint, size: 36)
                VStack(alignment: .leading, spacing: 6) {
                    Text(guess.short)
                        .font(.headline)
                    PrototypeStatusPill(status: standing.status)
                    if let line = standing.line {
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if onOpen != nil {
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.inkSoft)
                }
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
        .disabled(onOpen == nil)
        .accessibilityElement(children: .combine)
    }
}

/// Days too alike to compare: say so, and offer a short experiment instead.
struct PrototypeCantTellCard: View {
    let guess: PrototypeData.Guess
    @State private var accepted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TintedIcon(symbol: guess.symbol, tint: guess.tint, size: 36)
                Text(guess.short)
                    .font(.headline)
                Spacer(minLength: 0)
                PrototypeStatusPill(status: .cantTell)
            }
            .foregroundStyle(Theme.ink)

            Text("Your days are too alike to tell.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text(PrototypeData.alikeLine(for: guess))
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)

            VStack(alignment: .leading, spacing: 10) {
                Label("A short experiment", systemImage: "flask")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.pinkDeep)
                Text(guess.experiment)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                Button(accepted ? "Starts tomorrow" : "Try it") { accepted = true }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(accepted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(guess.tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

/// "Leaning yes", "You're right": small, with a symbol so color is never the only cue.
struct PrototypeStatusPill: View {
    let status: PrototypeData.Status

    var body: some View {
        Label(status.label, systemImage: status.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status == .watching ? Theme.inkSoft : Theme.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background, in: Capsule())
    }

    private var background: Color {
        switch status {
        case .right: return Theme.Tint.mint
        case .leaningYes, .leaningNo: return Theme.Tint.rose
        case .cantTell: return Theme.Tint.butter
        default: return Theme.ink.opacity(0.06)
        }
    }
}

/// A calm progress bar that eases forward when a day is counted.
struct PrototypeProgressBar: View {
    let fraction: Double
    var tint: Color = Theme.pink

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ink.opacity(0.06))
                Capsule().fill(tint)
                    .frame(width: fraction > 0 ? max(10, geometry.size.width * min(fraction, 1)) : 0)
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

/// "Test another guess": the settled guess frees its slot for a new one.
struct PrototypeNextGuessSheet: View {
    let guesses: [PrototypeData.Guess]
    var onPick: (PrototypeData.Guess) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("What else might help you study?")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text("I'll start counting it today.")
                        .foregroundStyle(Theme.inkSoft)
                    PrototypeGuessList(guesses: guesses, selected: []) { guess in
                        onPick(guess)
                        dismiss()
                    }
                }
                .padding()
            }
            .background(Theme.cream.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview("Today · Day 1") {
    PrototypeTodayView(day: .one, name: "Giulia", guesses: PrototypeData.demoPicks)
        .fontDesign(.rounded)
}

#Preview("Today · Day 7") {
    PrototypeTodayView(day: .seven, name: "Giulia", guesses: PrototypeData.demoPicks)
        .fontDesign(.rounded)
}

#Preview("Today · Day 14") {
    PrototypeTodayView(day: .fourteen, name: "Giulia", guesses: PrototypeData.demoPicks)
        .fontDesign(.rounded)
}

#Preview("Can't tell") {
    PrototypeCantTellCard(guess: PrototypeData.library)
        .padding()
        .background(Theme.cream)
        .fontDesign(.rounded)
}
