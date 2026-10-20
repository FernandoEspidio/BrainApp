import SwiftUI

/// Vivid ring colors (one per life area), brighter than the pastel tints so rings pop like Fitness rings.
extension LifeArea {
    var ringColor: Color {
        switch id {
        case LifeArea.rest.id: return Color(hex: 0x7B6CF6)
        case LifeArea.learning.id: return Color(hex: 0x3D8BFD)
        case LifeArea.movement.id: return Color(hex: 0x22C38E)
        case LifeArea.creativity.id: return Color(hex: 0xF5A623)
        case LifeArea.social.id: return Color(hex: 0xF2547D)
        default: return Color(hex: 0xE59A6B)
        }
    }
}
