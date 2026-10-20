import SwiftUI

struct DemoBanner: View {
    var body: some View {
        Label("Demo · fictional data", systemImage: "theatermasks")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.Tint.butter, in: Capsule())
    }
}

struct LevelBadge: View {
    let level: Discovery.Level

    var body: some View {
        Text(level.label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.ink.opacity(0.06), in: Capsule())
    }
}

struct StatusBadge: View {
    let status: Discovery.Status

    var body: some View {
        Label(status.label, systemImage: status.symbol)
            .font(.caption)
            .foregroundStyle(Theme.inkSoft)
    }
}

struct TagChip: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.inkSoft)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.ink.opacity(0.06), in: Capsule())
    }
}

/// Icon on a soft tinted circle (area identity without loud colors).
struct TintedIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .background(tint, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Basis of an observation: period, n, sources and last update. Used inside a `Section`.
struct EvidenceBlock: View {
    let evidence: Evidence
    let generatedAt: Date

    var body: some View {
        LabeledContent("Period", value: periodText)
        LabeledContent("Moments used", value: "\(evidence.usableCount) of \(evidence.totalCount)")
        LabeledContent("Sources", value: evidence.sources.map(\.label).joined(separator: ", "))
        LabeledContent("Updated", value: generatedAt.formatted(date: .abbreviated, time: .shortened))
    }

    private var periodText: String {
        let start = evidence.periodStart.formatted(date: .abbreviated, time: .omitted)
        let end = evidence.periodEnd.formatted(date: .abbreviated, time: .omitted)
        return start == end ? start : "\(start) – \(end)"
    }
}

/// Simple horizontal bars for a discovery's comparison.
struct ComparisonBars: View {
    let rows: [Evidence.Row]
    var tint: Color = Theme.pink

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row.label).font(.subheadline)
                        Spacer()
                        Text(row.value).font(.subheadline.weight(.semibold))
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.ink.opacity(0.06))
                            Capsule().fill(tint)
                                .frame(width: max(8, geometry.size.width * min(max(row.fraction, 0), 1)))
                        }
                    }
                    .frame(height: 10)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct ActivityRow: View {
    let activity: Activity
    let area: LifeArea

    var body: some View {
        HStack(spacing: 12) {
            TintedIcon(symbol: activity.symbol(area: area), tint: area.tint, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title).font(.body.weight(.medium))
                Text(detailLine).font(.caption).foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 0)
            if let feeling = activity.enjoyment {
                Text(Feeling.emoji(for: feeling)).accessibilityLabel("Felt \(Feeling.label(for: feeling))")
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var detailLine: String {
        var parts = [activity.date.formatted(date: .omitted, time: .shortened)]
        if let minutes = activity.durationMinutes { parts.append(formatMinutes(minutes)) }
        if activity.isDetected { parts.append("detected") }
        if activity.source == .demo { parts.append("fictional") }
        return parts.joined(separator: " · ")
    }
}

/// The only rating we ask for: three faces.
enum Feeling: Int, CaseIterable, Identifiable {
    case meh = 2, good = 4, great = 5

    var id: Int { rawValue }

    var emoji: String {
        switch self {
        case .meh: return "😕"
        case .good: return "🙂"
        case .great: return "😄"
        }
    }

    var label: String {
        switch self {
        case .meh: return "meh"
        case .good: return "good"
        case .great: return "great"
        }
    }

    static func emoji(for value: Int) -> String { value >= 5 ? "😄" : (value >= 4 ? "🙂" : "😕") }
    static func label(for value: Int) -> String { value >= 5 ? "great" : (value >= 4 ? "good" : "meh") }
}

/// Three big face buttons.
struct FeelingPicker: View {
    var selected: Int?
    var onPick: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Feeling.allCases) { feeling in
                Button {
                    onPick(feeling.rawValue)
                } label: {
                    Text(feeling.emoji)
                        .font(.system(size: 30))
                        .frame(width: 56, height: 56)
                        .background(selected == feeling.rawValue ? Theme.Tint.rose : Theme.ink.opacity(0.05), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(feeling.label)
                .accessibilityAddTraits(selected == feeling.rawValue ? .isSelected : [])
            }
        }
    }
}

/// Navigation tile used on the Connections tab.
struct Tile: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TintedIcon(symbol: symbol, tint: tint, size: 36)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .cardStyle(padding: 14)
    }
}
