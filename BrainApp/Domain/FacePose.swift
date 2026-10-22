import Foundation

/// The few facial values the brain uses (0…1; head and gaze in -1…1).
/// Recording these instead of video is what makes sharing "brain moves" cheap:
/// a frame is 21 numbers, stored as 21 bytes (see `BrainClip`).
struct FacePose: Hashable, Sendable {
    /// Eyes as they appear ON SCREEN (mirrored like a selfie): left = screen left.
    var leftEyeOpen: Float = 1
    var rightEyeOpen: Float = 1
    var jawOpen: Float = 0
    var smile: Float = 0
    /// Inner brows (worried / surprised).
    var browUp: Float = 0
    var browDown: Float = 0
    var cheekPuff: Float = 0
    var tongueOut: Float = 0
    var pucker: Float = 0
    var headRoll: Float = 0
    var headYaw: Float = 0
    var headPitch: Float = 0
    /// Where the eyes look, on screen: -1 left … 1 right, -1 up … 1 down.
    var gazeX: Float = 0
    var gazeY: Float = 0
    /// Outer brows per side (one raised brow = "really?").
    var leftBrowRaise: Float = 0
    var rightBrowRaise: Float = 0
    /// Smiling eyes (^ ^) when combined with a smile.
    var squint: Float = 0
    var eyeWide: Float = 0
    var frown: Float = 0
    /// Mouth pulled to one side: -1 screen left … 1 screen right.
    var mouthShift: Float = 0
    /// "Ooh" mouth.
    var funnel: Float = 0

    /// Exponential smoothing to remove jitter.
    func blended(toward target: FacePose, amount t: Float) -> FacePose {
        var result = self
        for key in Self.channels {
            let a = self[keyPath: key.path]
            result[keyPath: key.path] = a + (target[keyPath: key.path] - a) * t
        }
        return result
    }

    /// Received poses are untrusted: keep every value in its valid range.
    func clamped() -> FacePose {
        var result = self
        for key in Self.channels {
            let v = self[keyPath: key.path]
            result[keyPath: key.path] = v.isFinite ? min(max(v, key.range.lowerBound), key.range.upperBound) : key.neutral
        }
        return result
    }

    // MARK: - Channels

    struct Channel: Sendable {
        let name: String
        let path: WritableKeyPath<FacePose, Float> & Sendable
        let range: ClosedRange<Float>
        let neutral: Float
    }

    private static let unit: ClosedRange<Float> = 0...1
    private static let signed: ClosedRange<Float> = -1...1

    /// Fixed order: this IS the wire/storage format. Only ever append new channels at the end.
    static let channels: [Channel] = [
        Channel(name: "leftEyeOpen", path: \.leftEyeOpen, range: unit, neutral: 1),
        Channel(name: "rightEyeOpen", path: \.rightEyeOpen, range: unit, neutral: 1),
        Channel(name: "jawOpen", path: \.jawOpen, range: unit, neutral: 0),
        Channel(name: "smile", path: \.smile, range: unit, neutral: 0),
        Channel(name: "browUp", path: \.browUp, range: unit, neutral: 0),
        Channel(name: "browDown", path: \.browDown, range: unit, neutral: 0),
        Channel(name: "cheekPuff", path: \.cheekPuff, range: unit, neutral: 0),
        Channel(name: "tongueOut", path: \.tongueOut, range: unit, neutral: 0),
        Channel(name: "pucker", path: \.pucker, range: unit, neutral: 0),
        Channel(name: "headRoll", path: \.headRoll, range: signed, neutral: 0),
        Channel(name: "headYaw", path: \.headYaw, range: signed, neutral: 0),
        Channel(name: "headPitch", path: \.headPitch, range: signed, neutral: 0),
        Channel(name: "gazeX", path: \.gazeX, range: signed, neutral: 0),
        Channel(name: "gazeY", path: \.gazeY, range: signed, neutral: 0),
        Channel(name: "leftBrowRaise", path: \.leftBrowRaise, range: unit, neutral: 0),
        Channel(name: "rightBrowRaise", path: \.rightBrowRaise, range: unit, neutral: 0),
        Channel(name: "squint", path: \.squint, range: unit, neutral: 0),
        Channel(name: "eyeWide", path: \.eyeWide, range: unit, neutral: 0),
        Channel(name: "frown", path: \.frown, range: unit, neutral: 0),
        Channel(name: "mouthShift", path: \.mouthShift, range: signed, neutral: 0),
        Channel(name: "funnel", path: \.funnel, range: unit, neutral: 0)
    ]

    /// Linear blend between two poses (used to play clips smoothly between recorded frames).
    static func mix(_ a: FacePose, _ b: FacePose, _ t: Float) -> FacePose {
        a.blended(toward: b, amount: t)
    }
}

/// Tolerant coding: missing keys (older data, older app versions) take their neutral value.
extension FacePose: Codable {
    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        self.init()
        for channel in Self.channels {
            if let value = try container.decodeIfPresent(Float.self, forKey: Key(stringValue: channel.name)) {
                self[keyPath: channel.path] = value
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        for channel in Self.channels {
            try container.encode(self[keyPath: channel.path], forKey: Key(stringValue: channel.name))
        }
    }
}
