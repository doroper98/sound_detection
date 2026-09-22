import Foundation

public struct TimedWaveform: Sendable {
    public let endTimeSeconds: Double
    public let preview: StereoWaveformPreview
}

/// Small views of actual PCM within each tap buffer, never interpolated audio.
/// At 48 kHz a 4800-sample buffer produces six distinct 10 ms snapshots.
public enum WaveformBatch {
    public static func make(left: [Float], right: [Float], sampleRate: Double,
                            startTimeSeconds: Double) -> [TimedWaveform] {
        guard sampleRate.isFinite, (8_000...192_000).contains(sampleRate), startTimeSeconds.isFinite,
              left.count == right.count, (128...16_384).contains(left.count),
              left.allSatisfy({ $0.isFinite }), right.allSatisfy({ $0.isFinite }) else { return [] }
        let steps = max(1, Int(ceil(Double(left.count) / sampleRate * 60)))
        let window = max(128, Int(ceil(sampleRate * 0.01)))
        return (max(1, steps - 23)...steps).compactMap { step in
            let end = step * left.count / steps
            guard end >= 128 else { return nil }
            let start = max(0, end - window)
            guard let preview = StereoWaveformPreview.make(left: Array(left[start..<end]),
                right: Array(right[start..<end]), sampleRate: sampleRate) else { return nil }
            return TimedWaveform(endTimeSeconds: startTimeSeconds + Double(end) / sampleRate, preview: preview)
        }
    }
}

public struct WaveformDisplayStatistics: Codable, Sendable {
    public let targetFPS: Int
    public let presentedFrames: Int
    public let discardedFrames: Int
    public let pendingFrames: Int
    /// Unique PCM snapshots presented in the trailing second; not screen refresh rate.
    public let recentFreshFPS: Int
    public let presentationDelaySeconds: Double
    public let measuredAtUptimeSeconds: Double
}

/// At most 24 reduced snapshots, no PCM. A short display delay absorbs batched
/// tap delivery. Late frames are discarded instead of building display latency.
public struct WaveformPlayback {
    private var queue: [TimedWaveform] = []
    private var current: TimedWaveform?
    private var lastReceivedTime: Double?
    private var presented = 0
    private var discarded = 0
    private var presentationTimes: [Double] = []
    private var delay = 0.12
    public init() {}

    public mutating func append(_ frames: [TimedWaveform], bufferDuration: Double) {
        guard bufferDuration.isFinite, bufferDuration > 0 else { return }
        delay = min(0.3, max(0.12, bufferDuration + 0.02))
        for frame in frames where frame.endTimeSeconds.isFinite {
            guard lastReceivedTime.map({ frame.endTimeSeconds > $0 }) ?? true else { continue }
            lastReceivedTime = frame.endTimeSeconds
            queue.append(frame)
        }
        if queue.count > 24 { discarded += queue.count - 24; queue.removeFirst(queue.count - 24) }
    }

    public mutating func frame(at now: Double) -> TimedWaveform? {
        guard now.isFinite else { return nil }
        presentationTimes.removeAll { $0 <= now - 1 }
        guard let latest = lastReceivedTime, now - latest <= 0.35 else {
            discarded += queue.count; queue.removeAll(); current = nil
            return nil
        }
        let due = queue.prefix { $0.endTimeSeconds <= now - delay }.count
        if due > 0 {
            current = queue[due - 1]
            discarded += due - 1
            queue.removeFirst(due)
            presented += 1
            presentationTimes.append(now)
            if presentationTimes.count > 120 { presentationTimes.removeFirst(presentationTimes.count - 120) }
        }
        return current
    }

    public func statistics(at now: Double) -> WaveformDisplayStatistics {
        WaveformDisplayStatistics(targetFPS: 60, presentedFrames: presented, discardedFrames: discarded,
            pendingFrames: queue.count, recentFreshFPS: presentationTimes.filter { now - $0 < 1 && now >= $0 }.count,
            presentationDelaySeconds: delay, measuredAtUptimeSeconds: now)
    }

    public mutating func clear() {
        queue.removeAll(); current = nil; lastReceivedTime = nil; presentationTimes.removeAll()
    }
}
