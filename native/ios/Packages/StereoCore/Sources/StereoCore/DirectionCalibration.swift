import Foundation

public struct CalibrationObservation: Codable, Sendable {
    public let timeSeconds: Double
    public let frameDurationSeconds: Double
    public let sampleRate: Double
    public let status: LagStatus
    public let lagSeconds: Double?
    public let leftDbfs: Double?
    public let rightDbfs: Double?
    public let rightMinusLeftDb: Double?
    public let peakMargin: Double?
    public let rotationFromReferenceDegrees: Double?
}

public struct CalibrationTrial: Codable, Sendable, Identifiable {
    public let id: Int
    public let step: Int
    public let declaredSide: String
    public let repetition: Int
    public let completed: Bool
    public let interruptionReason: String?
    public let observations: [CalibrationObservation]
    public let statusCounts: [String: Int]
    public let coveredSeconds: Double
    public let candidateFraction: Double
    public let medianLagSeconds: Double?
    public let lagSpreadSeconds: Double?
    public let medianRightMinusLeftDb: Double?
    public let maxRotationDegrees: Double?
    public let qualityIssues: [String]
    public var usable: Bool { completed && qualityIssues.isEmpty }
}

public struct DirectionCalibrationReport: Codable, Sendable {
    public let state: String
    public let nextStep: Int
    public let secondsRemaining: Double
    public let trials: [CalibrationTrial]
    public let comparison: String
    public let directionDependentLagObserved: Bool
    public let setup = "Phone fixed portrait; one broadband source; left/center/right relative to rear-camera view, twice; similar distance and sound level. Positions are user declarations."
    public let protocolVersion = 1
    public let settleSeconds = 3
    public let trialSeconds = 5
    public let acousticCalibrationVerified = false
}

/// A measurement protocol, not a physical TDOA/angle calibration. It preserves
/// complete bounded statistical trials, including failures, for later review.
public struct DirectionCalibration {
    private var trials: [CalibrationTrial] = []
    private var rows: [CalibrationObservation] = []
    private var collectAt: Double?
    private var lastEnd: Double?
    private var reference: OrientationSample?
    private var step = 0
    private var referenceRate: Double?
    private var overflowed = false
    public var isMeasuring: Bool { collectAt != nil }
    public init() {}

    @discardableResult
    public mutating func begin(at now: Double) -> Bool {
        guard now.isFinite, collectAt == nil, step < 6, trials.count < 12 else { return false }
        collectAt = now + 3; rows = []; lastEnd = nil; overflowed = false
        return true
    }

    public mutating func append(analysis: StereoAnalysis, midpoint: Double, orientation: AlignedOrientation?) {
        guard let start = collectAt, midpoint.isFinite else { return }
        let duration = Double(analysis.sampleCount) / analysis.sampleRate
        let lower = midpoint - duration / 2, upper = midpoint + duration / 2
        guard duration.isFinite, duration > 0, lower >= start, upper <= start + 5,
              lastEnd.map({ lower >= $0 - 0.0001 }) ?? true else { return }
        guard rows.count < 600 else { overflowed = true; return }
        lastEnd = upper
        if reference == nil { reference = orientation?.sample }
        if referenceRate == nil { referenceRate = analysis.sampleRate }
        let rotation = orientation.flatMap { pose in reference.map { pose.sample.angularDistanceDegrees(to: $0) } }
        let l = analysis.channels[0].rmsDbfs, r = analysis.channels[1].rmsDbfs
        let difference: Double? = l.flatMap { left in r.map { $0 - left } }
        rows.append(CalibrationObservation(timeSeconds: midpoint - start, frameDurationSeconds: duration,
            sampleRate: analysis.sampleRate, status: analysis.status,
            lagSeconds: analysis.status == .candidate ? analysis.rightMinusLeftLagSeconds : nil,
            leftDbfs: l, rightDbfs: r, rightMinusLeftDb: difference, peakMargin: analysis.peakMargin,
            rotationFromReferenceDegrees: rotation))
    }

    public mutating func tick(at now: Double) {
        if let start = collectAt, now.isFinite, now >= start + 5 + 0.2 { finish(interruption: nil) }
    }

    public mutating func cancel(reason: String) {
        if collectAt != nil { finish(interruption: reason) }
    }

    public func snapshot(at now: Double) -> DirectionCalibrationReport {
        let phase: String
        var remaining = 0.0
        if let start = collectAt {
            phase = now < start ? "preparing" : "measuring"
            remaining = max(0, (now < start ? start : start + 5) - now)
        } else { phase = step == 6 ? "complete" : (trials.count >= 12 ? "attemptLimit" : "ready") }
        let comparison = compare()
        return DirectionCalibrationReport(state: phase, nextStep: step, secondsRemaining: remaining,
            trials: trials, comparison: comparison,
            directionDependentLagObserved: comparison == "repeatableSeparation")
    }

    private mutating func finish(interruption: String?) {
        var counts: [String: Int] = [:]
        for row in rows { counts[row.status.rawValue, default: 0] += 1 }
        let lags = rows.compactMap(\.lagSeconds)
        let center = median(lags)
        let spread = center.flatMap { c in median(lags.map { abs($0 - c) }).map { 1.4826 * $0 } }
        let covered = rows.reduce(0) { $0 + $1.frameDurationSeconds }
        let fraction = rows.isEmpty ? 0 : Double(lags.count) / Double(rows.count)
        let rotations = rows.compactMap(\.rotationFromReferenceDegrees)
        var issues: [String] = []
        if interruption != nil { issues.append("interrupted") }
        if rows.count < 20 || covered < 3.5 { issues.append("insufficientCoverage") }
        if lags.count < 10 || fraction < 0.6 { issues.append("insufficientLagCandidates") }
        if Double(rotations.count) < Double(rows.count) * 0.9 || rotations.isEmpty { issues.append("missingOrientation") }
        if (rotations.max() ?? 0) > 5 { issues.append("phoneMoved") }
        if rows.contains(where: { $0.sampleRate != referenceRate }) { issues.append("sampleRateChanged") }
        if let spread, let rate = referenceRate, spread > 3 / rate { issues.append("unstableLag") }
        if overflowed { issues.append("observationLimit") }
        trials.append(CalibrationTrial(id: trials.count, step: step, declaredSide: ["left", "center", "right"][step % 3],
            repetition: step / 3 + 1, completed: interruption == nil, interruptionReason: interruption,
            observations: rows, statusCounts: counts, coveredSeconds: covered, candidateFraction: fraction,
            medianLagSeconds: center, lagSpreadSeconds: spread,
            medianRightMinusLeftDb: median(rows.compactMap(\.rightMinusLeftDb)), maxRotationDegrees: rotations.max(),
            qualityIssues: issues))
        if interruption == nil { step += 1 }
        rows = []; collectAt = nil; lastEnd = nil
    }

    private func compare() -> String {
        guard step == 6 else { return "pending" }
        let completed = trials.filter(\.completed)
        guard completed.count == 6, completed.allSatisfy(\.usable), let rate = referenceRate else { return "insufficientQuality" }
        let values = completed.compactMap(\.medianLagSeconds)
        guard values.count == 6 else { return "insufficientQuality" }
        let tolerance = max(3 / rate, 2 * (completed.compactMap(\.lagSpreadSeconds).max() ?? 0))
        guard (0..<3).allSatisfy({ abs(values[$0] - values[$0 + 3]) <= tolerance }) else { return "notRepeatable" }
        let increasing = values[1] - values[0] > tolerance && values[2] - values[1] > tolerance
            && values[4] - values[3] > tolerance && values[5] - values[4] > tolerance
        let decreasing = values[0] - values[1] > tolerance && values[1] - values[2] > tolerance
            && values[3] - values[4] > tolerance && values[4] - values[5] > tolerance
        return increasing || decreasing ? "repeatableSeparation" : "noClearSeparation"
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted(), middle = values.count / 2
        return values.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
