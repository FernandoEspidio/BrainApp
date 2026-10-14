import SwiftUI

/// For the few things the phone can't detect: type it, the area is guessed, optionally one face.
/// Also used to fix a detected moment.
struct LogActivitySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let existing: Activity?
    var presetExperimentID: UUID? = nil

    @State private var title = ""
    @State private var date = Date.now
    @State private var areaID: String?
    @State private var areaWasSuggested = false
    @State private var allowSuggestion = true
    @State private var feeling: Int?
    @State private var measureRating: Int?
    @State private var linkExperiment = false
    @State private var arm: Experiment.Arm = .a
    @State private var confirmDelete = false
    @State private var loaded = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        let repo = model.repository
        let experiment = repo.openExperiment.flatMap { $0.status == .active ? $0 : nil }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let existing, let detection = existing.detection {
                        Label("Detected by your phone · \(detection.label)", systemImage: detection.symbol)
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSoft)
                    }

                    TextField("What did you do?", text: $title)
                        .font(.title3.weight(.semibold))
                        .focused($titleFocused)
                        .submitLabel(.done)
                        .onChange(of: title) { _, newValue in suggestArea(for: newValue, repo: repo) }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(repo.areas) { area in
                                let isSelected = areaID == area.id
                                Button {
                                    areaID = area.id
                                    areaWasSuggested = false
                                    allowSuggestion = false
                                } label: {
                                    Label(area.name, systemImage: area.symbol)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(isSelected ? area.tint : Theme.ink.opacity(0.05), in: Capsule())
                                        .overlay(Capsule().strokeBorder(isSelected ? Theme.ink : .clear, lineWidth: 1.5))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            }
                        }
                    }
                    if areaWasSuggested {
                        Text("Area guessed from what you wrote. Tap another to change it.")
                            .font(.caption)
                            .foregroundStyle(Theme.inkSoft)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("How did it feel? (optional)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        FeelingPicker(selected: feeling) { feeling = feeling == $0 ? nil : $0 }
                    }

                    DatePicker("When", selection: $date)
                        .font(.subheadline)

                    if let experiment {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Part of your experiment", isOn: $linkExperiment)
                                .font(.subheadline.weight(.semibold))
                            if linkExperiment {
                                Picker("Condition", selection: $arm) {
                                    ForEach(Experiment.Arm.allCases) { arm in
                                        Text(experiment.label(for: arm)).tag(arm)
                                    }
                                }
                                .pickerStyle(.segmented)
                                if experiment.measure != .enjoyment {
                                    Text("\(experiment.measure.label)?").font(.subheadline).foregroundStyle(Theme.inkSoft)
                                    FeelingPicker(selected: measureRating) { measureRating = measureRating == $0 ? nil : $0 }
                                }
                            }
                        }
                        .cardStyle()
                    }

                    if existing != nil {
                        Button("Delete this moment", role: .destructive) { confirmDelete = true }
                            .font(.subheadline)
                    }
                }
                .padding()
            }
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle(existing == nil ? "Add a moment" : "Edit moment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(repo: repo, experiment: experiment) }
                        .disabled(!canSave)
                }
            }
            .confirmationDialog("Delete this moment?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let existing { repo.deleteActivities([existing.id]) }
                    dismiss()
                }
            } message: {
                if existing?.isDetected == true {
                    Text("Your phone won't bring this one back.")
                }
            }
            .onAppear { load(experiment: experiment) }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Logic

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && areaID != nil
    }

    private func suggestArea(for text: String, repo: LocalRepository) {
        guard allowSuggestion, existing == nil else { return }
        if let suggestion = CategorySuggester.suggest(for: text, customAreas: repo.snapshot.customAreas) {
            areaID = suggestion
            areaWasSuggested = true
        }
    }

    private func load(experiment: Experiment?) {
        guard !loaded else { return }
        loaded = true
        if let activity = existing {
            allowSuggestion = false
            title = activity.title
            date = activity.date
            areaID = activity.areaID
            areaWasSuggested = activity.areaWasSuggested
            feeling = activity.enjoyment
            if let experiment, activity.experimentID == experiment.id {
                linkExperiment = true
                arm = activity.experimentArm ?? .a
                measureRating = activity.rating(experiment.measure)
            }
        } else {
            titleFocused = true
            if let experiment, presetExperimentID == experiment.id { linkExperiment = true }
        }
    }

    private func save(repo: LocalRepository, experiment: Experiment?) {
        guard let areaID else { return }
        var activity = existing ?? Activity(title: "", areaID: areaID, date: date, source: repo.isDemo ? .demo : .manual)
        activity.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        activity.areaID = areaID
        activity.date = date
        activity.enjoyment = feeling
        activity.areaWasSuggested = areaWasSuggested

        if let experiment {
            if linkExperiment {
                activity.experimentID = experiment.id
                activity.experimentArm = arm
                switch experiment.measure {
                case .focus: activity.focus = measureRating ?? activity.focus
                case .energy: activity.energy = measureRating ?? activity.energy
                case .enjoyment: break
                }
            } else if activity.experimentID == experiment.id {
                activity.experimentID = nil
                activity.experimentArm = nil
            }
        }

        if existing == nil { repo.add(activity) } else { repo.update(activity) }
        dismiss()
    }
}
