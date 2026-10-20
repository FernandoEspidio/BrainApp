import Foundation

/// Features parked while the app focuses on its promise:
/// "BrainApp shows you how the things you do affect each other."
/// Their code stays; only the entry points are hidden. The switch is in Settings, in Debug builds only.
/// Parked: nearby friends (swap and throw), 3D buddy, animoji, share card, custom areas, priorities.
enum Lab {
    /// `@AppStorage` key. Off by default.
    static let parkedFeaturesKey = "lab.parkedFeatures"
}
