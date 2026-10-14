import SwiftUI

/// First run in three calm steps: meet your buddy → your phone does the logging → let's go.
/// No real permissions yet: sensing is simulated in this prototype.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var name = ""
    @State private var simulateSensing = true
    @State private var poke = 0

    var body: some View {
        let repo = model.repository
        ZStack {
            Theme.cream.ignoresSafeArea()
            VStack(spacing: 20) {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule().fill(index <= step ? Theme.ink : Theme.hairline).frame(width: index == step ? 22 : 8, height: 8)
                    }
                }
                .padding(.top, 12)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(step + 1) of 3")

                Spacer(minLength: 0)

                BrainAvatarView(appearance: repo.snapshot.companion, stage: 0,
                                mood: [BrainMood.idle, .resting, .celebrating][step], size: 260, poke: poke)
                    .onTapGesture { poke += 1 }

                VStack(spacing: 10) {
                    Text(title).font(.title.weight(.bold)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                    Text(subtitle).font(.body).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                if step == 0 {
                    TextField("Your name", text: $name)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 12)
                        .background(Color.white, in: Capsule())
                        .padding(.horizontal, 40)
                        .submitLabel(.next)
                } else if step == 1 {
                    VStack(spacing: 10) {
                        sensingRow("moon.zzz.fill", "Sleep", Theme.Tint.lilac)
                        sensingRow("figure.walk", "Walks and workouts", Theme.Tint.mint)
                        sensingRow("book.fill", "Reading and focus time", Theme.Tint.sky)
                        Toggle("Simulate it for now", isOn: $simulateSensing)
                            .font(.subheadline.weight(.semibold))
                            .tint(Theme.pinkDeep)
                            .padding(.top, 4)
                    }
                    .cardStyle()
                    .padding(.horizontal)
                }

                Spacer(minLength: 0)

                Button(step < 2 ? "Continue" : "Let's go") { advance(repo) }
                    .buttonStyle(InkButtonStyle())
                    .padding(.horizontal)

                if step == 0 {
                    Button("Just look around with sample data") { model.setDemoMode(true) }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(.bottom, 12)
            .animation(.easeInOut, value: step)
        }
    }

    private var title: String {
        switch step {
        case 0: return "Hi! I'm your brain buddy."
        case 1: return "Your phone does the logging"
        default: return "I'll learn as we go"
        }
    }

    private var subtitle: String {
        switch step {
        case 0: return "I show what you're discovering about yourself. I don't measure your brain, and I never get sad if you rest."
        case 1: return "Moments are noticed automatically. You only add what the phone can't see."
        default: return "Patterns show up after a few days, always with the evidence behind them."
        }
    }

    private func sensingRow(_ symbol: String, _ text: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            TintedIcon(symbol: symbol, tint: tint, size: 34)
            Text(text).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
            Spacer()
            Image(systemName: "checkmark").foregroundStyle(Theme.inkSoft)
        }
    }

    private func advance(_ repo: LocalRepository) {
        if step == 0 { repo.setUserName(name) }
        if step < 2 {
            step += 1
        } else {
            repo.completeOnboarding(simulateSensing: simulateSensing)
        }
    }
}
