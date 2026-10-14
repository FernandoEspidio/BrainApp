import SwiftUI

struct CompanionCustomizationView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = CompanionAppearance()
    @State private var loaded = false

    var body: some View {
        let repo = model.repository
        Form {
            Section {
                BrainAvatarView(appearance: draft, stage: repo.companionStage, size: 200)
                    .frame(maxWidth: .infinity)
            }

            Section("Name") {
                TextField("Companion name", text: $draft.name)
            }

            Section("Color") {
                HStack(spacing: 14) {
                    ForEach(Theme.brainVariants.indices, id: \.self) { index in
                        let option = Theme.brainVariants[index]
                        Button {
                            draft.colorIndex = index
                        } label: {
                            Circle()
                                .fill(option.fill)
                                .frame(width: 36, height: 36)
                                .overlay(Circle().strokeBorder(Color.primary, lineWidth: draft.colorIndex == index ? 3 : 0))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.name)
                        .accessibilityAddTraits(draft.colorIndex == index ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Accessory") {
                Picker("Accessory", selection: $draft.accessory) {
                    ForEach(CompanionAppearance.Accessory.allCases) { accessory in
                        Text(accessory.label).tag(accessory)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("How it grows") {
                Text(CompanionStage.explanation).font(.subheadline)
                ForEach(CompanionStage.names.indices, id: \.self) { index in
                    Label(CompanionStage.names[index],
                          systemImage: index <= repo.companionStage ? "checkmark.circle.fill" : "circle")
                }
            }
        }
        .navigationTitle("Your companion")
        .onAppear {
            guard !loaded else { return }
            draft = repo.snapshot.companion
            loaded = true
        }
        .onChange(of: draft) { _, newValue in
            guard loaded else { return }
            var cleaned = newValue
            cleaned.name = String(newValue.name.prefix(40))
            repo.updateCompanion(cleaned)
        }
    }
}
