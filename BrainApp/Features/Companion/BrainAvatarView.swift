import SwiftUI

/// Convenience wrapper: draws the user's companion (color + accessory) in a given mood.
struct BrainAvatarView: View {
    var appearance: CompanionAppearance
    var stage: Int
    var mood: BrainMood = .idle
    var size: CGFloat = 180
    /// false for thumbnails, the map and the exported image.
    var animated = true
    var showsHalo = true
    var showsStage = false
    var poke = 0

    var body: some View {
        BrainCharacterView(
            mood: mood,
            variant: Theme.brainVariant(appearance.colorIndex),
            outfit: appearance.outfit,
            stage: showsStage ? stage : nil,
            showsHalo: showsHalo,
            animated: animated,
            poke: poke
        )
        .frame(width: size, height: size)
        .accessibilityLabel("\(appearance.name), \(CompanionStage.name(stage)), \(mood.title)")
    }
}
