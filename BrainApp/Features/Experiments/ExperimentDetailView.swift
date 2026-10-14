import SwiftUI

/// Short follow-up and review at the end. If the data isn't enough, it says so.
struct ExperimentDetailView: View {
    @Environment(AppModel.self) private var model
    let experimentID: UUID

    @State private var showLog = false
    @State private var reflection = ""
    @State private var confirmAbandon = false
    @State private var loaded = false

    var body: some View {
        let repo = model.repository
        if let experiment = repo.experiment(id: experimentID) {
            let review = ExperimentAnalyzer.review(experiment, activities: repo.snapshot.activities)
            List {
                Section {
                    Text(experiment.question).font(.title3.bold())
                    LabeledContent("Status", value: experiment.status.label)
                    LabeledContent("Measure", value: experiment.measure.label)
                    LabeledContent("Agreed period",
                                   value: "\(experiment.plannedDays) days from \(experiment.startDate.formatted(date: .abbreviated, time: .omitted))")
                }

                Section("Entries per condition") {
                    ArmStatsRow(stats: review.a)
                    ArmStatsRow(stats: review.b)
                }

                Section("Honest reading") {
                    Text(review.verdict)
                }

                if experiment.isOpen {
                    Section {
                        if experiment.status == .active {
                            Button("Log session", systemImage: "plus.circle") { showLog = true }
                        }
                        Button(experiment.status == .paused ? "Resume" : "Pause",
                               systemImage: experiment.status == .paused ? "play" : "pause") {
                            var updated = experiment
                            updated.status = experiment.status == .paused ? .active : .paused
                            repo.updateExperiment(updated)
                        }
                        Button("Finish and review", systemImage: "checkmark.circle") {
                            var updated = experiment
                            updated.status = .finished
                            updated.endDate = .now
                            repo.updateExperiment(updated)
                        }
                        Button("Abandon", systemImage: "xmark.circle", role: .destructive) {
                            confirmAbandon = true
                        }
                    }
                } else {
                    Section {
                        TextField("What did you learn? What would you change?", text: $reflection, axis: .vertical)
                        Button("Save reflection") {
                            var updated = experiment
                            updated.reflection = reflection
                            repo.updateExperiment(updated)
                        }
                        .disabled(reflection == experiment.reflection)
                    } header: {
                        Text("Your reflection")
                    } footer: {
                        Text("What stays, what changes and what you'd like to explore next.")
                    }
                }
            }
            .navigationTitle("Experiment")
            .onAppear {
                guard !loaded else { return }
                reflection = experiment.reflection
                loaded = true
            }
            .sheet(isPresented: $showLog) { LogActivitySheet(existing: nil, presetExperimentID: experiment.id) }
            .confirmationDialog("Abandon the experiment?", isPresented: $confirmAbandon, titleVisibility: .visible) {
                Button("Abandon", role: .destructive) {
                    var updated = experiment
                    updated.status = .abandoned
                    updated.endDate = .now
                    repo.updateExperiment(updated)
                }
            } message: {
                Text("Your entries are kept. Abandoning is a valid decision too.")
            }
        } else {
            ContentUnavailableView("Experiment not found", systemImage: "flask")
        }
    }
}

private struct ArmStatsRow: View {
    let stats: ExperimentReview.ArmStats

    var body: some View {
        LabeledContent(stats.label) {
            Text(detail)
        }
    }

    private var detail: String {
        let sessions = countLabel(stats.count, "session", "sessions")
        guard let mean = stats.mean else { return "\(sessions) · no ratings" }
        return "\(sessions) · mean \(mean.formatted(.number.precision(.fractionLength(1)))) (n = \(stats.ratedCount))"
    }
}
