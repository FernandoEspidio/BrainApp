import SwiftUI

/// The single card on Home. One line, one action. Details live behind ⓘ.
struct HomeCardView: View {
    let card: HomeCard
    var onOpenDiscovery: (Discovery) -> Void
    var onFeeling: (Activity, Int) -> Void
    var onSkip: (Activity) -> Void
    var onOpenExperiment: (Experiment) -> Void

    var body: some View {
        Group {
            switch card {
            case .newDiscovery(let discovery), .changedDiscovery(let discovery):
                Button {
                    onOpenDiscovery(discovery)
                } label: {
                    row(symbol: discovery.symbol, tint: Theme.Tint.rose, title: discovery.title, trailing: "info.circle")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the evidence")

            case .checkIn(let activity):
                VStack(spacing: 12) {
                    HStack {
                        Text("\(activity.title)?")
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
                    row(symbol: "flask", tint: Theme.Tint.butter, title: experiment.question, trailing: nil, badge: "\(logged)")
                }
                .buttonStyle(.plain)

            case .gettingToKnowYou, .allQuiet:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func row(symbol: String, tint: Color, title: String, trailing: String?, badge: String? = nil) -> some View {
        HStack(spacing: 12) {
            TintedIcon(symbol: symbol, tint: tint, size: 36)
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            Spacer(minLength: 0)
            if let badge {
                Text(badge)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.Tint.butter, in: Capsule())
            }
            if let trailing {
                Image(systemName: trailing).foregroundStyle(Theme.pinkDeep)
            }
        }
    }
}
