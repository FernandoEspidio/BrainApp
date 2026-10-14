import SwiftUI

/// Selective sharing: preview, choice of discoveries and default exclusion
/// of health and schedules. The image is generated offline; sending it depends on the chosen destination.
struct ShareCardSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    @State private var options = ShareOptions()
    @State private var loaded = false
    @State private var rendered: Image?

    var body: some View {
        let candidates = model.repository.rankedDiscoveries
        let card = model.makeCard(options: options)
        let atLimit = options.selectedDiscoveryIDs.count >= ShareOptions.maxHighlights

        NavigationStack {
            Form {
                Section("Preview") {
                    BrainCardView(card: card)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }

                Section {
                    Toggle("Include time-of-day patterns", isOn: $options.includeSchedulePatterns)
                    if candidates.isEmpty {
                        Text("No discoveries to include yet.").foregroundStyle(.secondary)
                    }
                    ForEach(candidates) { discovery in
                        let isSelected = options.selectedDiscoveryIDs.contains(discovery.id)
                        let blocked = discovery.usesHealthData || (discovery.revealsSchedule && !options.includeSchedulePatterns)
                        Toggle(isOn: selectionBinding(for: discovery.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(discovery.title)
                                if discovery.usesHealthData {
                                    Text("Refers to sleep or health: never shared.").font(.caption).foregroundStyle(.secondary)
                                } else if discovery.revealsSchedule && !options.includeSchedulePatterns {
                                    Text("Reveals your schedule: turn on the option above to include it.").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(blocked || (!isSelected && atLimit))
                    }
                } header: {
                    Text("What to include (up to \(ShareOptions.maxHighlights))")
                } footer: {
                    Text("Entries, specific times, ratings, notes and health data are never included.")
                }

                Section {
                    if let rendered {
                        ShareLink(item: rendered, preview: SharePreview("My companion", image: rendered)) {
                            Label("Share image", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        ProgressView()
                    }
                } footer: {
                    Text("The image is created on the device. Sending it depends on the destination app you choose.")
                }
            }
            .navigationTitle("Shareable card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear {
                if !loaded {
                    options.selectedDiscoveryIDs = BrainCardFactory.defaultSelection(candidates)
                    loaded = true
                }
                render()
            }
            .onChange(of: options) { oldValue, newValue in
                if oldValue.includeSchedulePatterns && !newValue.includeSchedulePatterns {
                    let scheduleIDs = Set(candidates.filter(\.revealsSchedule).map(\.id))
                    options.selectedDiscoveryIDs.removeAll { scheduleIDs.contains($0) }
                }
                render()
            }
        }
    }

    private func selectionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { options.selectedDiscoveryIDs.contains(id) },
            set: { isOn in
                if isOn {
                    guard !options.selectedDiscoveryIDs.contains(id),
                          options.selectedDiscoveryIDs.count < ShareOptions.maxHighlights else { return }
                    options.selectedDiscoveryIDs.append(id)
                } else {
                    options.selectedDiscoveryIDs.removeAll { $0 == id }
                }
            }
        )
    }

    @MainActor
    private func render() {
        let content = BrainCardView(card: model.makeCard(options: options))
            .frame(width: 340)
            .padding(16)
            .background(Color(uiColor: .systemBackground))
        let renderer = ImageRenderer(content: content)
        renderer.scale = displayScale
        if let image = renderer.uiImage {
            rendered = Image(uiImage: image)
        }
    }
}
