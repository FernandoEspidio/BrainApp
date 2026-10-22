import Foundation

/// A "brain move": a few seconds of facial poses, never video or camera images.
///
/// Memory/size budget (why it's cheap enough to keep one per friend):
/// - Recorded at 20 fps for 3 s → 60 frames.
/// - Each frame is quantized to 1 byte per channel (21 channels) → ~1.3 KB per move on disk / on the wire
///   (vs ~25 KB as plain JSON, and megabytes as video).
/// - Playback interpolates between frames, so 20 fps looks as smooth as the screen's refresh rate.
struct BrainClip: Hashable, Sendable {
    static let recordFPS: Double = 20
    static let recordSeconds: Double = 3
    static let maxSeconds: Double = 4

    var fps: Double
    var frames: [FacePose]

    init(fps: Double = BrainClip.recordFPS, frames: [FacePose]) {
        self.fps = min(max(fps, 5), 30)
        self.frames = Array(frames.prefix(Int(self.fps * Self.maxSeconds)))
    }

    static let empty = BrainClip(frames: [])

    var isEmpty: Bool { frames.isEmpty }
    var duration: TimeInterval { Double(frames.count) / fps }

    /// Pose at `time` seconds into the clip, interpolated between recorded frames.
    /// Returns nil past the end (the caller decides whether to loop or idle).
    func pose(at time: TimeInterval) -> FacePose? {
        guard !frames.isEmpty, time >= 0 else { return nil }
        let position = time * fps
        let index = Int(position)
        guard index < frames.count else { return nil }
        let next = min(index + 1, frames.count - 1)
        return FacePose.mix(frames[index], frames[next], Float(position - Double(index)))
    }

    /// Looping playback with a short rest between loops that eases from the last frame back to `rest`
    /// (so the loop never "jumps").
    func loopingPose(at time: TimeInterval, rest: FacePose, gap: TimeInterval = 1.0) -> FacePose {
        guard !frames.isEmpty else { return rest }
        let cycle = duration + gap
        let t = time.truncatingRemainder(dividingBy: cycle)
        if let pose = pose(at: t) { return pose }
        // In the gap: ease out of the last frame into the resting face, then into the first frame.
        let g = Float((t - duration) / gap)
        let last = frames[frames.count - 1]
        if g < 0.5 { return FacePose.mix(last, rest, smoothstep(g * 2)) }
        return FacePose.mix(rest, frames[0], smoothstep((g - 0.5) * 2))
    }

    /// What to draw at `date`: loops when `start` is nil; otherwise plays once from `start`
    /// and eases back into `rest` (the idle face) over a quarter second.
    func playback(at date: Date, start: Date?, rest: FacePose) -> FacePose {
        guard !frames.isEmpty else { return rest }
        guard let start else { return loopingPose(at: date.timeIntervalSinceReferenceDate, rest: rest) }
        let elapsed = date.timeIntervalSince(start)
        if elapsed < 0 { return rest }
        if let pose = pose(at: elapsed) { return pose }
        let settle = Float(min(max((elapsed - duration) / 0.25, 0), 1))
        return FacePose.mix(frames[frames.count - 1], rest, smoothstep(settle))
    }

    private func smoothstep(_ x: Float) -> Float {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Received clips are untrusted.
    func sanitized() -> BrainClip {
        BrainClip(fps: fps.isFinite ? fps : Self.recordFPS, frames: frames.map { $0.clamped() })
    }

    // MARK: - Compact bytes

    /// 1 byte per channel per frame, channels in `FacePose.channels` order.
    var packed: Data {
        let channels = FacePose.channels
        var data = Data(capacity: frames.count * channels.count)
        for frame in frames {
            for channel in channels {
                let value = frame[keyPath: channel.path]
                let range = channel.range
                let normalized = (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound)
                    / (range.upperBound - range.lowerBound)
                data.append(UInt8((normalized * 255).rounded()))
            }
        }
        return data
    }

    init(fps: Double, packed: Data, channelCount: Int) {
        let channels = FacePose.channels
        guard channelCount > 0 else { self.init(fps: fps, frames: []); return }
        let bytes = [UInt8](packed)
        var frames: [FacePose] = []
        frames.reserveCapacity(bytes.count / channelCount)
        var offset = 0
        while offset + channelCount <= bytes.count {
            var pose = FacePose()
            // Older senders may have fewer channels, newer ones more: read what we both know.
            for (index, channel) in channels.enumerated() where index < channelCount {
                let range = channel.range
                let normalized = Float(bytes[offset + index]) / 255
                pose[keyPath: channel.path] = range.lowerBound + normalized * (range.upperBound - range.lowerBound)
            }
            frames.append(pose)
            offset += channelCount
        }
        self.init(fps: fps, frames: frames)
    }
}

/// Stored and sent as `{"fps": 20, "ch": 21, "q": "<base64>"}`.
/// Also reads the first prototype's format (a plain JSON array of poses at 15 fps) so nothing saved is lost.
extension BrainClip: Codable {
    private enum CodingKeys: String, CodingKey { case fps, ch, q }

    init(from decoder: Decoder) throws {
        if var legacy = try? decoder.unkeyedContainer() {
            var frames: [FacePose] = []
            while !legacy.isAtEnd {
                frames.append(try legacy.decode(FacePose.self))
            }
            self.init(fps: 15, frames: frames)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fps = try c.decodeIfPresent(Double.self, forKey: .fps) ?? Self.recordFPS
        let channelCount = try c.decodeIfPresent(Int.self, forKey: .ch) ?? FacePose.channels.count
        let data = try c.decodeIfPresent(Data.self, forKey: .q) ?? Data()
        // Hard cap before decoding anything big (4 s × 30 fps × 64 channels).
        guard data.count <= 30 * 4 * 64, (1...64).contains(channelCount) else {
            self.init(fps: fps, frames: [])
            return
        }
        self.init(fps: fps, packed: data, channelCount: channelCount)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fps, forKey: .fps)
        try c.encode(FacePose.channels.count, forKey: .ch)
        try c.encode(packed, forKey: .q)
    }
}
