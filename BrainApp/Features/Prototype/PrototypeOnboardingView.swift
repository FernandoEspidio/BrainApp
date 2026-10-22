import SwiftUI

/// PROTOTYPE. First run in three steps: your name → what you think helps you study → two weeks.
struct PrototypeOnboardingView: View {
    @Binding var name: String
    @Binding var picks: [PrototypeData.Guess]
    var onDone: () -> Void

    @State private var step = 0
    @State private var poke = 0

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    stepDots
                    Spacer(minLength: 0)
                    BrainAvatarView(appearance: CompanionAppearance(), stage: 0,
                                    mood: [BrainMood.idle, .focused, .celebrating][step],
                                    size: step == 1 ? 96 : 220, poke: poke)
                        .onTapGesture { poke += 1 }

                    VStack(spacing: 10) {
                        Text(title)
                            .font(.title.weight(.bold))
                            .foregroundStyle(Theme.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                    switch step {
                    case 0:
                        TextField("Your name", text: $name)
                            .font(.title3)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 12)
                            .background(Color.white, in: Capsule())
                            .padding(.horizontal, 40)
                            .submitLabel(.next)
                            .onSubmit { step = 1 }
                    case 1:
                        PrototypeGuessList(guesses: PrototypeData.guesses, selected: picks) { toggle($0) }
                            .padding(.horizontal)
                    default:
                        PrototypePickedRow(guesses: picks)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom) {
            Button(step < 2 ? "Continue" : "Let's go") { advance() }
                .buttonStyle(InkButtonStyle())
                .disabled(step == 1 && picks.isEmpty)
                .opacity(step == 1 && picks.isEmpty ? 0.4 : 1)
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Theme.cream)
        }
        .background(Theme.cream.ignoresSafeArea())
        .animation(.easeInOut, value: step)
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Capsule().fill(index <= step ? Theme.ink : Theme.hairline).frame(width: index == step ? 22 : 8, height: 8)
            }
        }
        .padding(.top, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step + 1) of 3")
    }

    private var title: String {
        switch step {
        case 0: return "Hi! I'm your brain buddy."
        case 1: return "What do you think helps you study?"
        default: return "I'll check over the next 2 weeks."
        }
    }

    private var subtitle: String {
        switch step {
        case 0: return "I'll tell you if you're right about what helps you study. What should I call you?"
        case 1: return picks.isEmpty ? "Pick up to 3. I'll check each one against your days." : "\(picks.count) of 3 picked."
        default: return "Answer one question each evening. Health counts sleep, steps and workouts; you tap for the rest."
        }
    }

    private func toggle(_ guess: PrototypeData.Guess) {
        if let index = picks.firstIndex(of: guess) {
            picks.remove(at: index)
        } else if picks.count < 3 {
            picks.append(guess)
        }
    }

    private func advance() {
        if step < 2 { step += 1 } else { onDone() }
    }
}

/// The six guesses, each saying who counts it. Picks stop at `limit`.
struct PrototypeGuessList: View {
    let guesses: [PrototypeData.Guess]
    let selected: [PrototypeData.Guess]
    var limit = 3
    var onTap: (PrototypeData.Guess) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(guesses) { guess in
                let isSelected = selected.contains(guess)
                let isFull = !isSelected && selected.count >= limit
                Button {
                    onTap(guess)
                } label: {
                    HStack(spacing: 12) {
                        TintedIcon(symbol: guess.symbol, tint: guess.tint, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(guess.label)
                                .font(.body.weight(.medium))
                            Label(guess.source, systemImage: guess.sourceSymbol)
                                .font(.caption)
                                .foregroundStyle(Theme.inkSoft)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? Theme.pinkDeep : Theme.hairline)
                    }
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isSelected ? Theme.Tint.rose : Theme.ink.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isFull)
                .opacity(isFull ? 0.4 : 1)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// The picked guesses as small chips: "Sleep · Library · Coffee".
struct PrototypePickedRow: View {
    let guesses: [PrototypeData.Guess]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(guesses) { guess in
                Label(guess.short, systemImage: guess.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(guess.tint, in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Onboarding") {
    @Previewable @State var name = ""
    @Previewable @State var picks: [PrototypeData.Guess] = []
    PrototypeOnboardingView(name: $name, picks: $picks) {}
        .fontDesign(.rounded)
}
