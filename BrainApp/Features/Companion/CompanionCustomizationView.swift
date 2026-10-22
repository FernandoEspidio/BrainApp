import SwiftUI

/// Your brain's closet: name, one of the curated colors, something for the head and something for the eyes.
/// The live preview reacts to every change (a little hop and a happy face).
struct CompanionCustomizationView: View {
    var isSheet = false

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = CompanionAppearance()
    @State private var loaded = false
    @State private var poke = 0
    @State private var reaction: ActiveReaction?

    var body: some View {
        let repo = model.repository
        ScrollView {
            VStack(spacing: 20) {
                preview
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("Name")
                    TextField("Brain name", text: $draft.name)
                        .font(.headline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .submitLabel(.done)
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("Color")
                    colorRow
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("On the head")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 10)], spacing: 10) {
                        ForEach(CompanionAppearance.Headwear.allCases) { item in
                            ClosetTile(title: item.label, isSelected: draft.headwear == item,
                                       appearance: CompanionAppearance(name: "", colorIndex: draft.colorIndex, headwear: item)) {
                                draft.headwear = item
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("On the eyes")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 10)], spacing: 10) {
                        ForEach(CompanionAppearance.Eyewear.allCases) { item in
                            ClosetTile(title: item.label, isSelected: draft.eyewear == item,
                                       appearance: CompanionAppearance(name: "", colorIndex: draft.colorIndex, eyewear: item)) {
                                draft.eyewear = item
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("How it grows")
                    Text(CompanionStage.explanation).font(.subheadline).foregroundStyle(Theme.inkSoft)
                    ForEach(CompanionStage.names.indices, id: \.self) { index in
                        Label(CompanionStage.names[index],
                              systemImage: index <= repo.companionStage ? "checkmark.circle.fill" : "circle")
                            .font(.subheadline)
                            .foregroundStyle(index <= repo.companionStage ? Theme.ink : Theme.inkSoft)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.cream.ignoresSafeArea())
        .navigationTitle("Style")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .sensoryFeedback(.selection, trigger: draft)
        .onAppear {
            guard !loaded else { return }
            draft = repo.snapshot.companion
            loaded = true
        }
        .onChange(of: draft) { old, newValue in
            guard loaded else { return }
            var cleaned = newValue
            cleaned.name = String(newValue.name.prefix(24))
            repo.updateCompanion(cleaned)
            // Hop on every look change (not while typing the name).
            if old.colorIndex != newValue.colorIndex || old.headwear != newValue.headwear || old.eyewear != newValue.eyewear {
                poke += 1
                reaction = ActiveReaction(kind: [.proud, .giggle, .wink].randomElement() ?? .proud, start: .now)
            }
        }
    }

    private var preview: some View {
        var base = FacePose()
        base.smile = 0.45
        return BrainBuddyView(appearance: draft, mood: .idle, basePose: base, livePose: nil,
                              reaction: reaction, stage: nil, poke: poke,
                              onTap: {
                                  poke += 1
                                  reaction = ActiveReaction(kind: BrainReaction.allCases.randomElement() ?? .giggle, start: .now)
                              },
                              accessibilityTapHint: "Tap for a reaction")
            .frame(width: 200, height: 200)
    }

    private var colorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Theme.brainVariants.indices, id: \.self) { index in
                    let option = Theme.brainVariants[index]
                    let isSelected = draft.colorIndex == index
                    Button {
                        draft.colorIndex = index
                    } label: {
                        Circle()
                            .fill(option.fill)
                            .overlay(Circle().strokeBorder(option.shade, lineWidth: 3))
                            .frame(width: 40, height: 40)
                            .padding(4)
                            .overlay(Circle().strokeBorder(Theme.ink, lineWidth: isSelected ? 2.5 : 0))
                            .scaleEffect(isSelected ? 1.08 : 1)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.name)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.headline).foregroundStyle(Theme.ink)
    }
}

/// One accessory, shown on a small still brain.
private struct ClosetTile: View {
    let title: String
    let isSelected: Bool
    let appearance: CompanionAppearance
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                BrainThumbnail(appearance: appearance)
                    .frame(width: 58, height: 58)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? Theme.pinkDeep : .clear, lineWidth: 2.5))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
