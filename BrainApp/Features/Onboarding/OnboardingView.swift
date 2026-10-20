import SwiftUI

/// First run in three calm steps: meet your buddy → pick what you protect → let's go.
/// Health access is asked on Today, once there's a goal to read it for.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var name = ""
    @State private var goal: Goal?
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
                                mood: [BrainMood.idle, .resting, .celebrating][step], size: step == 1 ? 140 : 260, poke: poke)
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
                    GoalPicker(selected: goal) { goal = $0 }
                        .padding(.horizontal)
                }

                Spacer(minLength: 0)

                Button(step < 2 ? "Continue" : "Let's go") { advance(repo) }
                    .buttonStyle(InkButtonStyle())
                    .disabled(step == 1 && goal == nil)
                    .opacity(step == 1 && goal == nil ? 0.4 : 1)
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
        case 1: return "What are you protecting?"
        default: return "I'll learn as we go"
        }
    }

    private var subtitle: String {
        switch step {
        case 0: return "I show what you're discovering about yourself. I don't measure your brain, and I never get sad if you rest."
        case 1: return "Pick one. I'll find what comes with it. You can change it any time."
        default:
            let finding = "what comes with \(goal?.change(better: true) ?? "it")"
            return goal?.question == nil
                ? "Log what you do with +. Health counts the rest, and I'll tell you \(finding)."
                : "Log what you do with +, and answer one question a day. In about a week I'll tell you \(finding)."
        }
    }

    private func advance(_ repo: LocalRepository) {
        if step == 0 { repo.setUserName(name) }
        if step == 1, let goal { repo.setGoal(goal) }
        if step < 2 {
            step += 1
        } else {
            // Simulated moments would mix with real ones; they can still be turned on in Settings.
            repo.completeOnboarding(simulateSensing: false)
        }
    }
}
