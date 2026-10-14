import Foundation

/// Suggests an area from the description. Explainable (keywords) and always correctable.
enum CategorySuggester {
    /// Order = priority on ties. Keywords are lowercase stems matched as substrings.
    private static let keywords: [(areaID: String, words: [String])] = [
        (LifeArea.rest.id, ["sleep", "slept", "nap", "rest", "meditat", "relax"]),
        (LifeArea.learning.id, ["study", "studied", "read", "book", "course", "class", "learn", "homework", "lecture", "research", "review", "coding", "program"]),
        (LifeArea.movement.id, ["run", "ran", "walk", "gym", "yoga", "swim", "bike", "cycl", "workout", "train", "soccer", "football", "dance", "lift", "hike"]),
        (LifeArea.creativity.id, ["draw", "paint", "write", "wrote", "music", "guitar", "piano", "design", "photo", "cook", "compos", "sketch"]),
        (LifeArea.social.id, ["friend", "family", "coffee with", "call", "meeting", "team", "party", "dinner with", "lunch with", "visit", "hang out"])
    ]

    static func suggest(for text: String, customAreas: [LifeArea]) -> String? {
        let normalized = normalize(text)
        guard normalized.count >= 3 else { return nil }

        // Custom areas win if their name appears in the text.
        if let custom = customAreas.first(where: { normalized.contains(normalize($0.name)) }) {
            return custom.id
        }

        var best: (areaID: String, score: Int)?
        for entry in keywords {
            let score = entry.words.filter { normalized.contains($0) }.count
            if score > (best?.score ?? 0) { best = (entry.areaID, score) }
        }
        return best?.areaID
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
    }
}
