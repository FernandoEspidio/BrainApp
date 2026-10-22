import SwiftUI

/// Share your brain outside the app: animated GIF of your animoji and/or the card as an image.
/// Uses the same choices as the Friends tab; traits can be picked here.
struct ShareCardSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    @State private var image: Image?
    @State private var gifURL: URL?

    var body: some View {
        @Bindable var bindable = model
        let repo = model.repository
        let card = model.makeCard()
        let candidates = BrainCardFactory.candidates(repo.rankedDiscoveries, hunches: repo.snapshot.hunches, options: model.shareOptions)
        let selected = model.shareOptions.selectedDiscoveryIDs
        let hasAnimoji = model.shareOptions.includeAnimoji && !repo.snapshot.animoji.isEmpty

        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    BrainCardView(card: card)
                        .shadow(color: Theme.ink.opacity(0.06), radius: 12, y: 4)

                    HStack(spacing: 12) {
                        if hasAnimoji {
                            if let gifURL {
                                ShareLink(item: gifURL) {
                                    Label("Animoji", systemImage: "face.smiling")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(InkButtonStyle())
                            } else {
                                ProgressView().frame(maxWidth: .infinity)
                            }
                        }
                        if let image {
                            ShareLink(item: image, preview: SharePreview(card.displayName, image: image)) {
                                Label("Card", systemImage: "photo")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(hasAnimoji ? AnyButtonStyle(SoftLargeButtonStyle()) : AnyButtonStyle(InkButtonStyle()))
                        }
                    }

                    if model.shareOptions.includeTraits && !candidates.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Traits", systemImage: "sparkles").font(.headline).foregroundStyle(Theme.ink)
                                Spacer()
                                Text("\(min(selected.count, ShareOptions.maxHighlights))/\(ShareOptions.maxHighlights)")
                                    .font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(Theme.inkSoft)
                            }
                            ForEach(candidates) { discovery in
                                let isOn = selected.contains(discovery.id)
                                Button {
                                    toggle(discovery.id, in: &bindable.shareOptions)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(isOn ? Theme.pinkDeep : Theme.inkSoft)
                                        Text(discovery.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Theme.ink)
                                            .multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(!isOn && selected.count >= ShareOptions.maxHighlights)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardStyle()
                    }

                    Label("Never your moments or health data", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSoft)
                }
                .padding()
            }
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear {
                if model.shareOptions.selectedDiscoveryIDs.isEmpty {
                    model.shareOptions.selectedDiscoveryIDs = BrainCardFactory.defaultSelection(repo.rankedDiscoveries, hunches: repo.snapshot.hunches)
                }
                renderImage()
            }
            .onChange(of: model.shareOptions) { _, _ in renderImage() }
            .task(id: repo.snapshot.animoji) {
                // Let the sheet finish presenting, then build the GIF on device.
                try? await Task.sleep(for: .milliseconds(250))
                gifURL = AnimojiExporter.gif(clip: repo.snapshot.animoji, appearance: repo.snapshot.companion,
                                             mood: repo.companionState().mood)
            }
        }
    }

    private func toggle(_ id: String, in options: inout ShareOptions) {
        if let index = options.selectedDiscoveryIDs.firstIndex(of: id) {
            options.selectedDiscoveryIDs.remove(at: index)
        } else if options.selectedDiscoveryIDs.count < ShareOptions.maxHighlights {
            options.selectedDiscoveryIDs.append(id)
        }
    }

    @MainActor
    private func renderImage() {
        let content = BrainCardView(card: model.makeCard(), animated: false)
            .frame(width: 340)
            .padding(16)
            .background(Theme.cream)
        let renderer = ImageRenderer(content: content)
        renderer.scale = displayScale
        if let uiImage = renderer.uiImage {
            image = Image(uiImage: uiImage)
        }
    }
}

/// Large soft button matching InkButtonStyle's size.
struct SoftLargeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Theme.ink.opacity(0.08), in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Type-erased button style so a style can be chosen at runtime.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
