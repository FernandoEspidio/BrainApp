import SwiftUI

/// When a connection is tapped: what it represents, the evidence and the uncertainty. Never presented as a cause.
struct ConnectionDetailSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let connection: MapConnection

    var body: some View {
        let repo = model.repository
        let from = repo.area(id: connection.fromAreaID)
        let to = repo.area(id: connection.toAreaID)

        NavigationStack {
            List {
                Section("What this line represents") {
                    Text("An association observed between \(from.name.lowercased()) and \(to.name.lowercased()) in your entries. It is not a proven cause.")
                }
                if let discovery = repo.report.discovery(id: connection.discoveryID) {
                    Section(discovery.title) {
                        Text(discovery.summary)
                        StatusBadge(status: discovery.status)
                    }
                    Section("Evidence") {
                        EvidenceBlock(evidence: discovery.evidence, generatedAt: repo.report.generatedAt)
                    }
                    Section("Uncertainty") {
                        ForEach(discovery.evidence.limitations, id: \.self) { limitation in
                            Text(limitation)
                        }
                    }
                } else {
                    Text("This association no longer appears with your current entries.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
