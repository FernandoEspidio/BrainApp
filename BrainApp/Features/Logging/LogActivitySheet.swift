import SwiftUI

/// For the few things the phone can't detect: type it → area is guessed → (optional) one face → Done.
/// Also used to fix a detected moment.
struct LogActivitySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let existing: Activity?
    /// Set when opened from an area button on Today: that area is pre-selected.
    var presetAreaID: String? = nil

    @State private var title = ""
    @State private var date = Date.now
    @State private var areaID: String?
    @State private var areaWasSuggested = false
    @State private var allowSuggestion = true
    @State private var feeling: Int?
    @State private var duration: Int?
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
                VStack(alignment: .leading, spacing: 20) {
                    if let existing, let detection = existing.detection {
                        Label(detection.label, systemImage: detection.symbol)
                            .font(.caption)
                            .foregroundStyle(Theme.inkSoft)
                    }

                    TextField("What did you do?", text: $title)
                        .font(.title2.weight(.semibold))
                        .focused($titleFocused)
                        .submitLabel(.done)
                        .onChange(of: title) { _, newValue in suggestArea(for: newValue, repo: repo) }

                    // Area chips. A guessed area is simply pre-selected (with a sparkle), no explanation text.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(repo.areas) { area in
                                let isSelected = areaID == area.id
                                Button {
                                    areaID = area.id
                                    areaWasSuggested = false
                                    allowSuggestion = false
                                } label: {
                                    Label(area.name, systemImage: isSelected && areaWasSuggested ? "sparkles" : area.symbol)
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

                    FeelingPicker(selected: feeling) { feeling = feeling == $0 ? nil : $0 }
                        .frame(maxWidth: .infinity)

                    // Duration fills minute-based rings (without it, a moment counts as 15 min).
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Image(systemName: "timer").foregroundStyle(Theme.inkSoft)
                            ForEach(durationOptions, id: \.self) { minutes in
                                let isSelected = duration == minutes
                                Button {
                                    withAnimation(.snappy) { duration = isSelected ? nil : minutes }
                                } label: {
                                    Text(formatMinutes(minutes))
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(isSelected ? Color.white : Theme.ink)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(isSelected ? Theme.ink : Theme.ink.opacity(0.05), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            }
                        }
                    }
                    .sensoryFeedback(.selection, trigger: duration)

                    HStack {
                        Image(systemName: "clock").foregroundStyle(Theme.inkSoft)
                        DatePicker("When", selection: $date)
                            .labelsHidden()
                        Spacer()
                    }


                    if existing != nil {
                        Button("Delete", role: .destructive) { confirmDelete = true }
                            .font(.subheadline)
                    }
                }
                .padding()
            }
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(repo: repo, experiment: experiment) }
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

    private var durationOptions: [Int] {
        var options = [15, 30, 45, 60, 90, 120]
        if let duration, !options.contains(duration) { options.append(duration); options.sort() }
        return options
    }

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
            duration = activity.durationMinutes
            if let experiment, activity.experimentID == experiment.id {
                linkExperiment = true
                arm = activity.experimentArm ?? .a
                measureRating = activity.rating(experiment.measure)
            }
        } else {
            titleFocused = true
            if let presetAreaID {
                areaID = presetAreaID
                allowSuggestion = false
            }
        }
    }

    private func save(repo: LocalRepository, experiment: Experiment?) {
        guard let areaID else { return }
        var activity = existing ?? Activity(title: "", areaID: areaID, date: date, source: repo.isDemo ? .demo : .manual)
        activity.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        activity.areaID = areaID
        activity.date = date
        activity.enjoyment = feeling
        activity.durationMinutes = duration
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
