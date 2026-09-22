import Foundation

public enum StereoAnalysisError: Error, Equatable {
    case invalidSampleRate, invalidFrame, nonFiniteSample
}

public struct ChannelLevel: Codable, Equatable, Sendable {
    public let rmsDbfs: Double?
    public let peak: Double
    public let active: Bool
    public let clipped: Bool
}

public enum LagStatus: String, Codable, Sendable {
    case silentChannel, clipped, duplicate, ambiguous, weakCorrelation, searchBoundary, candidate
}

public struct StereoAnalysis: Codable, Sendable {
    public let sampleRate: Double
    public let sampleCount: Int
    public let channels: [ChannelLevel]
    public let zeroLagCorrelation: Double?
    public let relativeDifference: Double?
    public let gainAdjustedResidual: Double?
    public let duplicateSuspected: Bool
    public let status: LagStatus
    /// Positive means channel 1 (right) arrives later than channel 0 (left).
    /// This is a processed-signal lag, NOT a calibrated physical TDOA.
    public let rightMinusLeftLagSamples: Int?
    public let rightMinusLeftLagSeconds: Double?
    public let peakCorrelation: Double?
    public let peakMargin: Double?
    public let searchLimitSamples: Int
}

/// Independent of AVFoundation, device geometry, source coordinates, and UI.
public enum StereoAnalyzer {
    public static func analyze(left: [Float], right: [Float], sampleRate: Double) throws -> StereoAnalysis {
        guard sampleRate.isFinite, (8_000...192_000).contains(sampleRate) else {
            throw StereoAnalysisError.invalidSampleRate
        }
        guard left.count == right.count, (128...16_384).contains(left.count) else {
            throw StereoAnalysisError.invalidFrame
        }
        guard left.allSatisfy({ $0.isFinite }), right.allSatisfy({ $0.isFinite }) else {
            throw StereoAnalysisError.nonFiniteSample
        }
        let n = left.count
        let xMean = left.reduce(0.0) { $0 + Double($1) } / Double(n)
        let yMean = right.reduce(0.0) { $0 + Double($1) } / Double(n)
        let x = left.map { Double($0) - xMean }
        let y = right.map { Double($0) - yMean }
        let levels = [level(left), level(right)]
        var xx = 0.0, yy = 0.0, xy = 0.0, difference = 0.0
        for i in 0..<n {
            xx += x[i] * x[i]
            yy += y[i] * y[i]
            xy += x[i] * y[i]
            difference += pow(x[i] - y[i], 2)
        }
        let hasAC = xx / Double(n) > 1e-10 && yy / Double(n) > 1e-10
        let correlation: Double? = hasAC ? max(-1, min(1, xy / sqrt(xx * yy))) : nil
        let relativeDifference: Double? = hasAC ? sqrt(difference / max(xx, yy)) : nil
        // Also reject exact gain-scaled / polarity-inverted copies. Ordinary high
        // acoustic correlation alone is not proof of duplicate physical inputs.
        let residual = correlation.map { sqrt(max(0, 1 - $0 * $0)) }
        let duplicate = residual.map { $0 < 1e-5 } ?? false
        let limit = min(Int((sampleRate * 0.001).rounded()), n / 4)

        func result(_ status: LagStatus, lag: Int? = nil, peak: Double? = nil, margin: Double? = nil) -> StereoAnalysis {
            StereoAnalysis(
                sampleRate: sampleRate, sampleCount: n, channels: levels,
                zeroLagCorrelation: correlation, relativeDifference: relativeDifference,
                gainAdjustedResidual: residual, duplicateSuspected: duplicate, status: status,
                rightMinusLeftLagSamples: lag,
                rightMinusLeftLagSeconds: lag.map { Double($0) / sampleRate },
                peakCorrelation: peak, peakMargin: margin, searchLimitSamples: limit
            )
        }
        guard hasAC else { return result(.silentChannel) }
        guard !levels.contains(where: { $0.clipped }) else { return result(.clipped) }
        guard !duplicate else { return result(.duplicate) }

        var scores: [(lag: Int, score: Double)] = []
        for lag in -limit...limit {
            var numerator = 0.0, energyX = 0.0, energyY = 0.0
            let start = max(0, -lag)
            let end = min(n, n - lag)
            for i in start..<end {
                let a = x[i], b = y[i + lag]
                numerator += a * b
                energyX += a * a
                energyY += b * b
            }
            let denominator = sqrt(energyX * energyY)
            scores.append((lag, denominator > 1e-20 ? min(1, abs(numerator / denominator)) : 0))
        }
        let peak = scores.max { $0.score < $1.score }!
        // Exclude only the adjacent two samples of the main peak. Periodic
        // signals with repeated peaks must not become confident directions.
        let runnerUp = scores.filter { abs($0.lag - peak.lag) > 2 }.map(\.score).max() ?? 0
        let margin = peak.score - runnerUp
        guard peak.score >= 0.35 else { return result(.weakCorrelation, peak: peak.score, margin: margin) }
        guard abs(peak.lag) < limit else { return result(.searchBoundary, peak: peak.score, margin: margin) }
        guard margin >= 0.08 else { return result(.ambiguous, peak: peak.score, margin: margin) }
        return result(.candidate, lag: peak.lag, peak: peak.score, margin: margin)
    }

    private static func level(_ samples: [Float]) -> ChannelLevel {
        let power = samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)
        let peak = samples.reduce(0.0) { max($0, abs(Double($1))) }
        return ChannelLevel(rmsDbfs: power > 0 ? 10 * log10(power) : nil, peak: peak,
                            active: power > 1e-10, clipped: peak >= 0.999)
    }
}
