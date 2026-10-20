import Foundation

/// What the brain says when tapped: one short line + a matching reaction.
/// Every line comes from real data (rings, today's moments, discoveries).
struct BrainLine: Equatable {
    let text: String
    let reaction: BrainReaction
    /// When set, the bubble opens that ring's detail.
    var ringID: String? = nil
}

enum BrainTalk {
    @MainActor
    static func lines(repo: LocalRepository, mood: BrainMood) -> [BrainLine] {
        var lines: [BrainLine] = []
        let rings = repo.rings()

        if mood == .resting {
            lines.append(BrainLine(text: "Recharging… zzz", reaction: .yawn))
        }
        for ring in rings where ring.isComplete {
            lines.append(BrainLine(text: "\(ring.area.name) ring closed!", reaction: .proud, ringID: ring.area.id))
        }

        let open = rings.filter { !$0.isComplete }.sorted { $0.fraction > $1.fraction }
        if let closest = open.first, closest.value > 0 {
            lines.append(BrainLine(text: "\(closest.area.name) \(closest.percent)% · \(closest.goal.format(closest.remaining)) to go",
                                   reaction: .nod, ringID: closest.area.id))
        }
        if let lowest = open.last, lowest.id != open.first?.id || lowest.value == 0 {
            lines.append(BrainLine(text: "\(lowest.area.name) next?", reaction: .puff, ringID: lowest.area.id))
        }

        let count = repo.todayMoments().count
        lines.append(count == 0
                     ? BrainLine(text: "Fresh day!", reaction: .wiggle)
                     : BrainLine(text: "\(countLabel(count, "moment", "moments")) today", reaction: .giggle))

        if let discovery = repo.rankedDiscoveries.first {
            lines.append(BrainLine(text: discovery.title, reaction: .surprised))
        }
        lines.append(BrainLine(text: "Hehe, that tickles!", reaction: .cheeky))
        return lines
    }
}
