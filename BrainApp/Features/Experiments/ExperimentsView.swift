import SwiftUI

struct ExperimentRoute: Hashable {
    let id: UUID
}

struct ExperimentsView: View {
    @Environment(AppModel.self) private var model
    @State private var showNew = false

    var body: some View {
        let repo = model.repository
        let open = repo.snapshot.experiments.filter(\.isOpen)
        let closed = repo.snapshot.experiments
            .filter { !$0.isOpen }
            .sorted { ($0.endDate ?? $0.startDate) > ($1.endDate ?? $1.startDate) }

        List {
            Section {
                Text("An experiment compares two conditions in your own life with one short measure. You can pause or abandon it whenever you want.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("In progress") {
                if open.isEmpty {
                    Button("New experiment", systemImage: "flask") { showNew = true }
                }
                ForEach(open) { experiment in
                    NavigationLink(value: ExperimentRoute(id: experiment.id)) {
                        ExperimentRow(experiment: experiment)
                    }
                }
            }

            if !closed.isEmpty {
                Section("Past") {
                    ForEach(closed) { experiment in
                        NavigationLink(value: ExperimentRoute(id: experiment.id)) {
                            ExperimentRow(experiment: experiment)
                        }
                    }
                }
            }
        }
        .navigationTitle("Experiments")
        .navigationDestination(for: ExperimentRoute.self) { route in ExperimentDetailView(experimentID: route.id) }
        .sheet(isPresented: $showNew) { NewExperimentSheet(template: nil) }
    }
}

struct ExperimentRow: View {
    let experiment: Experiment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(experiment.question).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        let calendar = Calendar.current
        let elapsed = calendar.dateComponents([.day], from: calendar.startOfDay(for: experiment.startDate),
                                              to: calendar.startOfDay(for: .now)).day ?? 0
        let day = min(elapsed + 1, experiment.plannedDays)
        switch experiment.status {
        case .active, .paused:
            return "\(experiment.status.label) · Day \(day) of \(experiment.plannedDays)"
        case .finished, .abandoned:
            return experiment.status.label
        }
    }
}

struct NewExperimentSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let template: ExperimentTemplate?

    @State private var question = ""
    @State private var conditionA = ""
    @State private var conditionB = ""
    @State private var measure: Measure = .focus
    @State private var days = 10
    @State private var loaded = false

    var body: some View {
        let repo = model.repository
        NavigationStack {
            Form {
                if repo.openExperiment != nil {
                    Section {
                        Label("You already have an open experiment. Finish or abandon it before starting another.",
                              systemImage: "exclamationmark.circle")
                    }
                }
                Section("Ideas to get started") {
                    ForEach(ExperimentTemplate.all) { idea in
                        Button(idea.question) { apply(idea) }
                    }
                }
                Section("Question") {
                    TextField("What do you want to find out?", text: $question, axis: .vertical)
                }
                Section("Conditions to compare") {
                    TextField("Condition A", text: $conditionA)
                    TextField("Condition B", text: $conditionB)
                }
                Section {
                    Picker("Short measure", selection: $measure) {
                        ForEach(Measure.allCases) { measure in
                            Label(measure.label, systemImage: measure.symbol).tag(measure)
                        }
                    }
                    Stepper("Duration: \(days) days", value: $days, in: 3...28)
                } footer: {
                    Text("Each time you log a session, pick the condition and rate the measure. When you finish you'll see the comparison, with no causal claims.")
                }
            }
            .navigationTitle("New experiment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { start(repo) }.disabled(!canStart(repo))
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let template { apply(template) }
            }
        }
    }

    private func apply(_ idea: ExperimentTemplate) {
        question = idea.question
        conditionA = idea.conditionA
        conditionB = idea.conditionB
        measure = idea.measure
        days = idea.plannedDays
    }

    private func canStart(_ repo: LocalRepository) -> Bool {
        repo.openExperiment == nil
            && ![question, conditionA, conditionB].contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func start(_ repo: LocalRepository) {
        repo.startExperiment(Experiment(
            question: question.trimmingCharacters(in: .whitespacesAndNewlines),
            conditionA: conditionA.trimmingCharacters(in: .whitespacesAndNewlines),
            conditionB: conditionB.trimmingCharacters(in: .whitespacesAndNewlines),
            measure: measure,
            plannedDays: days,
            isDemo: repo.isDemo
        ))
        dismiss()
    }
}
