import SwiftUI

/// Two tabs: Today (the brain) and You (what it has learned).
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !model.isDemoMode && !model.repository.snapshot.hasCompletedOnboarding {
                OnboardingView()
            } else {
                TabView {
                    HomeView()
                        .tabItem { Label("Today", systemImage: "brain.head.profile") }
                    YouView()
                        .tabItem { Label("You", systemImage: "sparkles") }
                }
            }
        }
        .tint(Theme.ink)
        .fontDesign(.rounded)
        // The pastel palette is designed for light mode; "night" is a mood, not a system setting.
        .preferredColorScheme(.light)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.repository.syncDetections() }
        }
        .alert("Notice", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.repository.lastError ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.repository.lastError != nil },
            set: { if !$0 { model.repository.lastError = nil } }
        )
    }
}
