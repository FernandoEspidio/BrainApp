import SwiftUI

/// Areas around the brain. Every size, outline and line is explainable (see legend).
struct RadialMapView: View {
    let summaries: [AreaSummary]
    let connections: [MapConnection]
    let selectedAreaID: String?
    let appearance: CompanionAppearance
    let stage: Int
    var onSelect: (String) -> Void

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let positions = nodePositions(in: geometry.size)

            ZStack {
                // Spokes: neutral structure (area ↔ you).
                Path { path in
                    for point in positions.values {
                        path.move(to: center)
                        path.addLine(to: point)
                    }
                }
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)

                // Observed associations: only those of the selected area.
                if let selected = selectedAreaID {
                    ForEach(connections.filter { $0.involves(selected) }) { connection in
                        if let from = positions[connection.fromAreaID], let to = positions[connection.toAreaID] {
                            Path { path in
                                path.move(to: from)
                                path.addLine(to: to)
                            }
                            .stroke(Theme.pinkDeep, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 5]))
                        }
                    }
                }

                BrainAvatarView(appearance: appearance, stage: stage, size: 56, animated: false)
                    .position(center)
                    .accessibilityHidden(true)

                ForEach(summaries) { summary in
                    AreaNodeView(summary: summary, isSelected: summary.area.id == selectedAreaID) {
                        onSelect(summary.area.id)
                    }
                    .position(positions[summary.area.id] ?? center)
                }
            }
        }
    }

    private func nodePositions(in size: CGSize) -> [String: CGPoint] {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = max(min(size.width, size.height) / 2 - 64, 60)
        var result: [String: CGPoint] = [:]
        for (index, summary) in summaries.enumerated() {
            let angle = CGFloat(index) / CGFloat(max(summaries.count, 1)) * 2 * .pi - .pi / 2
            result[summary.area.id] = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
        return result
    }
}

struct AreaNodeView: View {
    let summary: AreaSummary
    let isSelected: Bool
    let action: () -> Void

    /// Explicit scale: 44 pt + 2 pt per entry in 14 days, up to 20 entries.
    static func diameter(for count: Int) -> CGFloat { 44 + CGFloat(min(count, 20)) * 2 }

    var body: some View {
        let diameter = Self.diameter(for: summary.recentCount)
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle().fill(summary.area.tint)
                    if summary.priority.rawValue >= Priority.important.rawValue {
                        Circle().strokeBorder(Theme.ink.opacity(0.45), lineWidth: 2)
                    }
                    Image(systemName: summary.area.symbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                }
                .frame(width: diameter, height: diameter)
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Theme.pinkDeep, lineWidth: 2.5).padding(-4)
                    }
                }
                Text(summary.area.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 96)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(summary.area.name): \(countLabel(summary.recentCount, "moment", "moments")) in 14 days. Priority: \(summary.priority.label).")
        .accessibilityHint("Shows its relationships and a link to the detail")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
