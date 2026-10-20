import SwiftUI

/// Four tabs, one job each. Every feature is reachable from a visible tab → list → detail.
/// Ring completions are celebrated here so they show up wherever the user is.
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
                        .tabItem { Label("Insights", systemImage: "sparkles") }
                    FriendsTab()
                        .tabItem { Label("Friends", systemImage: "person.2") }
                    MeView()
                        .tabItem { Label("Me", systemImage: "person.crop.circle") }
                }
                .overlay {
                    // A ring just reached 100%: celebrate once, wherever the user is.
                    if let ring = model.repository.nextCelebration() {
                        CelebrationOverlay(ring: ring) {
                            withAnimation(.easeOut(duration: 0.3)) { model.repository.markCelebrated(ring) }
                        }
                        .id(ring.celebrationKey)
                        .transition(.opacity)
                    }
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

/// Friends tab: your brain card, sending it, and your friends' brains.
struct FriendsTab: View {
    var body: some View {
        NavigationStack { NearbyFriendsView() }
    }
}
