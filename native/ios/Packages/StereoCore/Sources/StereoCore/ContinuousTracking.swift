import Foundation

public struct OrientationSample: Codable, Sendable {
    public let timestampSeconds: Double
    /// Core Motion CMAttitude quaternion, preserved as x, y, z, w.
    public let quaternion: [Double]

    public init?(timestampSeconds: Double, quaternion: [Double]) {
        guard timestampSeconds.isFinite, quaternion.count == 4,
              quaternion.allSatisfy({ $0.isFinite }) else { return nil }
        let norm = sqrt(quaternion.reduce(0) { $0 + $1 * $1 })
        guard norm > 1e-8, norm.isFinite else { return nil }
        self.timestampSeconds = timestampSeconds
        self.quaternion = quaternion.map { $0 / norm }
    }

    /// Magnitude only; does not assume an acoustic axis, compass heading, or position.
    public func angularDistanceDegrees(to other: OrientationSample) -> Double {
        let dot = abs(zip(quaternion, other.quaternion).reduce(0) { $0 + $1.0 * $1.1 })
        return 2 * acos(min(1, max(0, dot))) * 180 / .pi
    }
}

public struct AlignedOrientation: Codable, Sendable {
    public let sample: OrientationSample
    public let motionMinusAudioSeconds: Double
    public let rotationFromStartDegrees: Double
}

public struct OrientationHistory {
    private var samples: [OrientationSample] = []
    private var reference: OrientationSample?
    public init() {}

    public mutating func append(_ sample: OrientationSample) {
        guard samples.last.map({ sample.timestampSeconds > $0.timestampSeconds }) ?? true else { return }
        if reference == nil { reference = sample }
        samples.append(sample)
        samples.removeAll { $0.timestampSeconds < sample.timestampSeconds - 4 }
        if samples.count > 256 { samples.removeFirst(samples.count - 256) }
    }

    public func aligned(at audioTime: Double) -> AlignedOrientation? {
        guard audioTime.isFinite, let reference,
              let nearest = samples.min(by: {
                  abs($0.timestampSeconds - audioTime) < abs($1.timestampSeconds - audioTime)
              }), abs(nearest.timestampSeconds - audioTime) <= 0.06 else { return nil }
        return AlignedOrientation(sample: nearest,
            motionMinusAudioSeconds: nearest.timestampSeconds - audioTime,
            rotationFromStartDegrees: nearest.angularDistanceDegrees(to: reference))
    }
}

public struct TimedLag: Codable, Sendable {
    public let timeSeconds: Double
    public let sampleRate: Double
    public let lagSeconds: Double?
    public let frameStatus: LagStatus
    public let orientation: AlignedOrientation?

    public init(timeSeconds: Double, analysis: StereoAnalysis, orientation: AlignedOrientation? = nil) {
        self.timeSeconds = timeSeconds
        sampleRate = analysis.sampleRate
        lagSeconds = analysis.status == .candidate ? analysis.rightMinusLeftLagSeconds : nil
        frameStatus = analysis.status
        self.orientation = orientation
    }
}

public enum TrendState: String, Codable, Sendable {
    case collecting, tracking, changing, noReliableSignal, stale, stopped
}

public struct LagTrend: Codable, Sendable {
    public let state: TrendState
    public let estimateSeconds: Double?
    /// 1.4826 * median absolute deviation; descriptive spread, not a confidence interval.
    public let spreadSeconds: Double?
    public let recentAccepted: Int
    public let recentTotal: Int
    public let history: [TimedLag]
    public let historyWindowSeconds: Double
    public let estimateWindowSeconds: Double
}

public struct ContinuousLagTracker {
    private var history: [TimedLag] = []
    private var lastTime: Double?
    public init() {}

    /// Returns false for out-of-order / malformed observations. Memory is bounded.
    @discardableResult
    public mutating func append(_ observation: TimedLag) -> Bool {
        guard observation.timeSeconds.isFinite,
              observation.sampleRate.isFinite, (8_000...192_000).contains(observation.sampleRate),
              observation.lagSeconds.map({ $0.isFinite && abs($0) <= 0.001 }) ?? true,
              lastTime.map({ observation.timeSeconds > $0 }) ?? true else { return false }
        lastTime = observation.timeSeconds
        history.append(observation)
        trim(at: observation.timeSeconds)
        return true
    }

    public mutating func snapshot(at now: Double, stopped: Bool = false) -> LagTrend {
        guard now.isFinite else { return result(.stale, recent: []) }
        trim(at: now)
        let recent = history.filter { $0.timeSeconds >= now - 0.5 && $0.timeSeconds <= now }
        guard !stopped else { return result(.stopped, recent: recent) }
        guard let latest = history.last, latest.timeSeconds <= now, now - latest.timeSeconds <= 0.35 else {
            return result(.stale, recent: recent)
        }
        guard latest.lagSeconds != nil else { return result(.noReliableSignal, recent: recent) }
        let valid = recent.filter { $0.lagSeconds != nil }
        guard valid.count >= 3, let first = valid.first,
              latest.timeSeconds - first.timeSeconds >= 0.15 else { return result(.collecting, recent: recent) }
        guard Double(valid.count) / Double(recent.count) >= 0.6 else {
            return result(.noReliableSignal, recent: recent)
        }
        let values = valid.compactMap(\.lagSeconds)
        let center = median(values)
        let spread = 1.4826 * median(values.map { abs($0 - center) })
        let state: TrendState = spread > 3 / latest.sampleRate ? .changing : .tracking
        return result(state, recent: recent, estimate: center, spread: spread)
    }

    private mutating func trim(at now: Double) {
        history.removeAll { $0.timeSeconds < now - 2 }
        if history.count > 240 { history.removeFirst(history.count - 240) }
    }

    private func result(_ state: TrendState, recent: [TimedLag], estimate: Double? = nil, spread: Double? = nil) -> LagTrend {
        LagTrend(state: state, estimateSeconds: estimate, spreadSeconds: spread,
                 recentAccepted: recent.filter { $0.lagSeconds != nil }.count,
                 recentTotal: recent.count, history: history,
                 historyWindowSeconds: 2, estimateWindowSeconds: 0.5)
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted(), middle = values.count / 2
        return values.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
