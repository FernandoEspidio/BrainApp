import SwiftUI

/// The single card on Home. Short text, at most one action.
struct HomeCardView: View {
    let card: HomeCard
    var onOpenDiscovery: (Discovery) -> Void
    var onFeeling: (Activity, Int) -> Void
    var onSkip: (Activity) -> Void
    var onOpenExperiment: (Experiment) -> Void

    var body: some View {
        Group {
            switch card {
            case .newDiscovery(let discovery):
                discoveryRow(discovery, eyebrow: "New about you")

            case .changedDiscovery(let discovery):
                discoveryRow(discovery, eyebrow: "Something changed")

            case .checkIn(let activity):
                VStack(spacing: 12) {
                    HStack {
                        Text("How was your \(activity.title.lowercased())?")
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Button {
                            onSkip(activity)
                        } label: {
                            Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(Theme.inkSoft)
                        }
                        .accessibilityLabel("Skip")
                    }
                    FeelingPicker(selected: nil) { onFeeling(activity, $0) }
                }

            case .experiment(let experiment, let logged):
                Button {
                    onOpenExperiment(experiment)
                } label: {
                    row(symbol: "flask", tint: Theme.Tint.butter, eyebrow: "Your experiment",
                        title: experiment.question, detail: "\(countLabel(logged, "session", "sessions")) so far")
                }
                .buttonStyle(.plain)

            case .gettingToKnowYou:
                row(symbol: "leaf", tint: Theme.Tint.mint, eyebrow: "Getting to know you",
                    title: "Just live your day.", detail: "Your phone notices the moments. Patterns show up after a few days.")

            case .allQuiet:
                row(symbol: "checkmark", tint: Theme.Tint.mint, eyebrow: "All quiet",
                    title: "Nothing new today.", detail: "That's a valid result too.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func discoveryRow(_ discovery: Discovery, eyebrow: String) -> some View {
        Button {
            onOpenDiscovery(discovery)
        } label: {
            HStack {
                row(symbol: discovery.symbol, tint: Theme.Tint.rose, eyebrow: eyebrow,
                    title: discovery.title, detail: nil)
                Text("Why?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.pinkDeep)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the evidence")
    }

    private func row(symbol: String, tint: Color, eyebrow: String, title: String, detail: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            TintedIcon(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.inkSoft)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                if let detail {
                    Text(detail).font(.subheadline).foregroundStyle(Theme.inkSoft)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
