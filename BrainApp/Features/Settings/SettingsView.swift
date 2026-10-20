import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmErase = false

    var body: some View {
        let repo = model.repository
        Form {
            Section {
                Toggle("Demo mode", isOn: Binding(
                    get: { model.isDemoMode },
                    set: { model.setDemoMode($0) }
                ))
            } footer: {
                Text("Sample data · your entries stay untouched")
            }

            Section("Personalization") {
                TextField("Your name", text: Binding(
                    get: { repo.snapshot.userName },
                    set: { repo.setUserName($0) }
                ))
                NavigationLink {
                    CompanionCustomizationView()
                } label: {
                    Label("Your companion", systemImage: "brain")
                }
                NavigationLink {
                    PrioritiesView()
                } label: {
                    Label("Priorities", systemImage: "slider.horizontal.3")
                }
                NavigationLink {
                    AreasView()
                } label: {
                    Label("Areas", systemImage: "circle.hexagongrid")
                }
            }

            Section {
                Toggle("Simulated phone sensing", isOn: Binding(
                    get: { repo.snapshot.simulateSensing },
                    set: { repo.setSimulateSensing($0) }
                ))
                .disabled(repo.isDemo)
                LabeledContent("Health, Motion, Screen Time", value: "Not connected yet")
            } header: {
                Text("Data sources")
            } footer: {
                Text("Simulated until real sensors are connected")
            }

            Section {
                Label("Stays on this device", systemImage: "lock.shield")
                Button("Erase all my data", role: .destructive) { confirmErase = true }
            } header: {
                Text("Privacy")
            } footer: {
                if repo.isDemo {
                    Text("Demo mode: only resets the examples")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.cream.ignoresSafeArea())
        .navigationTitle("Settings")
        .confirmationDialog("Erase all data?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase everything", role: .destructive) { repo.eraseAll() }
        } message: {
            Text("Entries, experiments, seen discoveries and friends will be removed from this device. This can't be undone.")
        }
    }
}

struct PrioritiesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let repo = model.repository
        Form {
            Section {
                ForEach(repo.areas) { area in
                    Picker(selection: Binding(
                        get: { repo.priority(for: area.id) },
                        set: { repo.setPriority($0, for: area.id) }
                    )) {
                        ForEach(Priority.allCases) { priority in
                            Text(priority.label).tag(priority)
                        }
                    } label: {
                        Label(area.name, systemImage: area.symbol)
                    }
                }
            } footer: {
                Text("The map compares what you log with what you decide matters right now. There is no universal balance score, and areas don't need to be equal.")
            }
        }
        .navigationTitle("Priorities")
    }
}

struct AreasView: View {
    @Environment(AppModel.self) private var model
    @State private var newName = ""
    @State private var newSymbol = LifeArea.customSymbols[0]
    @State private var showBlockedDelete = false

    var body: some View {
        let repo = model.repository
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        Form {
            Section("Base areas") {
                ForEach(LifeArea.builtIns) { area in
                    Label(area.name, systemImage: area.symbol)
                }
            }

            Section {
                if repo.snapshot.customAreas.isEmpty {
                    Text("Add areas that matter to you and aren't on the list.").foregroundStyle(.secondary)
                }
                ForEach(repo.snapshot.customAreas) { area in
                    Label(area.name, systemImage: area.symbol)
                }
                .onDelete { offsets in
                    let ids = offsets.map { repo.snapshot.customAreas[$0].id }
                    for id in ids {
                        if repo.canDeleteArea(id) { repo.deleteCustomArea(id) } else { showBlockedDelete = true }
                    }
                }
            } header: {
                Text("Your areas")
            } footer: {
                Text("You can only delete an area that has no entries.")
            }

            Section("New area") {
                TextField("Name", text: $newName)
                Picker("Icon", selection: $newSymbol) {
                    ForEach(LifeArea.customSymbols, id: \.self) { symbol in
                        Image(systemName: symbol).tag(symbol)
                    }
                }
                Button("Add area") {
                    repo.addCustomArea(name: String(trimmed.prefix(30)), symbol: newSymbol)
                    newName = ""
                }
                .disabled(trimmed.isEmpty)
            }
        }
        .navigationTitle("Areas")
        .alert("This area has entries", isPresented: $showBlockedDelete) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Change the area of those entries before deleting it.")
        }
    }
}
