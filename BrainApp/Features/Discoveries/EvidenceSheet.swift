import SwiftUI

/// "Why?": the discovery in one sentence, a simple comparison, and the fine print folded away.
/// The user's opinion is stored separately from the evidence.
struct EvidenceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let discoveryID: String

    @State private var context = ""
    @State private var notRepresentative = false
    @State private var loaded = false

    var body: some View {
        let repo = model.repository
        NavigationStack {
            ScrollView {
                if let discovery = repo.report.discovery(id: discoveryID) {
                    content(discovery, repo: repo)
                        .padding()
                        .onAppear { repo.markSeen(discovery) }
                } else {
                    ContentUnavailableView(
                        "This one faded",
                        systemImage: "eye.slash",
                        description: Text("Your recent moments no longer support it. That's a valid result too.")
                    )
                    .padding(.top, 60)
                }
            }
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("Why?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveFeedback(repo)
                        dismiss()
                    }
                }
            }
        }
        .onAppear { loadFeedback(repo) }
        .onDisappear { saveFeedback(repo) }
    }

    private func content(_ discovery: Discovery, repo: LocalRepository) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                TintedIcon(symbol: discovery.symbol, tint: Theme.Tint.rose, size: 48)
                Text(discovery.title).font(.title2.weight(.bold)).foregroundStyle(Theme.ink)
                Text(discovery.summary).font(.body).foregroundStyle(Theme.inkSoft)
                Text("\(discovery.level.label) · \(discovery.status.label)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("Based on \(countLabel(discovery.evidence.usableCount, "moment", "moments"))")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                ComparisonBars(rows: discovery.evidence.comparison)
            }
            .cardStyle()

            // Quick reaction instead of a form.
            HStack(spacing: 10) {
                Button {
                    notRepresentative = false
                    saveFeedback(repo)
                    dismiss()
                } label: {
                    Label("That's me", systemImage: "hand.thumbsup")
                }
                .buttonStyle(InkButtonStyle())

                Button {
                    notRepresentative.toggle()
                } label: {
                    Label("Not me", systemImage: notRepresentative ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(Theme.ink.opacity(notRepresentative ? 0.14 : 0.06), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(notRepresentative ? .isSelected : [])
            }

            testItButton(discovery, repo: repo)

            VStack(alignment: .leading, spacing: 0) {
                DisclosureGroup("What we can't tell yet") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(discovery.evidence.limitations, id: \.self) { limitation in
                            Text("• \(limitation)").font(.subheadline).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider().padding(.vertical, 12)
                DisclosureGroup("Add context") {
                    TextField("Type of task, place, who you were with…", text: $context, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .padding(.top, 8)
                }
                Divider().padding(.vertical, 12)
                DisclosureGroup("Details") {
                    VStack(alignment: .leading, spacing: 8) {
                        EvidenceBlock(evidence: discovery.evidence, generatedAt: repo.report.generatedAt)
                        NavigationLink("See the moments used") {
                            ActivityListView(filterIDs: Set(discovery.evidence.activityIDs), title: "Moments used")
                        }
                        .foregroundStyle(Theme.pinkDeep)
                    }
                    .font(.subheadline)
                    .padding(.top, 8)
                }
            }
            .tint(Theme.ink)
            .cardStyle()
        }
    }

    /// "Test it": turn what the app saw into a hunch you check yourself for a few days.
    @ViewBuilder
    private func testItButton(_ discovery: Discovery, repo: LocalRepository) -> some View {
        let existing = repo.snapshot.hunches.first { $0.statement == discovery.title }
        if let existing {
            Label(existing.status == .testing ? "You're testing this as a hunch" : "You checked this as a hunch: \(existing.status.label.lowercased())",
                  systemImage: "lightbulb.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Deep.butter)
        } else {
            Button {
                repo.addHunch(HunchTemplate.from(discovery).make(isDemo: repo.isDemo))
            } label: {
                Label("Test it: check it myself for 5 days", systemImage: "lightbulb")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(Theme.ink)
                    .background(Theme.Tint.butter, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func loadFeedback(_ repo: LocalRepository) {
        guard !loaded else { return }
        let stored = repo.feedback(for: discoveryID)
        context = stored.context
        notRepresentative = stored.notRepresentative
        loaded = true
    }

    private func saveFeedback(_ repo: LocalRepository) {
        guard loaded else { return }
        let stored = repo.feedback(for: discoveryID)
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != stored.context || notRepresentative != stored.notRepresentative else { return }
        repo.setFeedback(DiscoveryFeedback(context: trimmed, notRepresentative: notRepresentative, updatedAt: .now),
                         for: discoveryID)
    }
}
