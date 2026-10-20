import SwiftUI

/// "Me": your buddy's look, your data and settings. Plain list, no hidden menus.
struct MeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let repo = model.repository
        let companion = repo.snapshot.companion

        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        BrainAvatarView(appearance: companion, stage: repo.companionStage, size: 72, animated: false)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(companion.name).font(.title3.weight(.bold)).foregroundStyle(Theme.ink)
                            Text(CompanionStage.name(repo.companionStage)).font(.subheadline).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Your buddy") {
                    NavigationLink { CompanionCustomizationView() } label: {
                        Label("Customize", systemImage: "paintbrush")
                    }
                }

                Section("Your data") {
                    NavigationLink { ActivityListView() } label: {
                        Label("All moments", systemImage: "list.bullet")
                    }
                    NavigationLink { PrioritiesView() } label: {
                        Label("Priorities", systemImage: "slider.horizontal.3")
                    }
                    NavigationLink { AreasView() } label: {
                        Label("Areas", systemImage: "circle.hexagongrid")
                    }
                }

                Section {
                    NavigationLink { SettingsView() } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("Me")
        }
    }
}
