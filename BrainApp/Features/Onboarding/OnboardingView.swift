import SwiftUI

/// First run in ONE screen: meet your buddy, say your name, go.
/// Permissions (sleep, motion…) will be asked later, at the moment each one is needed.
/// Sensing is simulated in this prototype, so it's switched on by default.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var poke = 0
    @State private var choosingSample = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        let repo = model.repository
        ZStack {
            Theme.cream.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer(minLength: 0)

                BrainAvatarView(appearance: repo.snapshot.companion, stage: 0, mood: .celebrating, size: 280, poke: poke)
                    .onTapGesture { poke += 1 }

                Text("Hi! I'm your brain buddy.")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)

                TextField("Your name", text: $name)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12)
                    .background(Color.white, in: Capsule())
                    .padding(.horizontal, 40)
                    .focused($nameFocused)
                    .submitLabel(.go)
                    .onSubmit { start(repo) }

                Spacer(minLength: 0)

                Button("Let's go") { start(repo) }
                    .buttonStyle(InkButtonStyle())
                    .padding(.horizontal)

                Button("Look around with a sample profile") { choosingSample = true }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .confirmationDialog("Sample profile", isPresented: $choosingSample, titleVisibility: .visible) {
                        ForEach(DemoProfile.allCases) { profile in
                            Button(profile.title) { model.setDemoProfile(profile) }
                        }
                    } message: {
                        Text("Fictional data, kept only in memory. Your own brain starts fresh with “Let's go”.")
                    }
            }
            .padding(.bottom, 12)
        }
    }

    private func start(_ repo: LocalRepository) {
        repo.setUserName(name)
        repo.completeOnboarding(simulateSensing: true)
    }
}
