import Foundation

public struct WaveformColumn: Equatable, Sendable {
    public let minimum: Float
    public let maximum: Float
}

/// One small display snapshot, intentionally not Codable or part of a report.
/// Both channels share the same scale so a quieter channel stays quieter.
public struct StereoWaveformPreview: Sendable {
    public let left: [WaveformColumn]
    public let right: [WaveformColumn]
    public let amplitudeRange: Float
    public let durationSeconds: Double

    public static func make(left: [Float], right: [Float], sampleRate: Double) -> Self? {
        guard sampleRate.isFinite, (8_000...192_000).contains(sampleRate),
              left.count == right.count, (128...16_384).contains(left.count),
              left.allSatisfy({ $0.isFinite }), right.allSatisfy({ $0.isFinite }) else { return nil }
        let count = min(left.count, Int((sampleRate * 0.01).rounded()))
        let start = left.count - count
        let columns = min(96, count)
        func reduce(_ samples: [Float]) -> [WaveformColumn] {
            (0..<columns).map { i in
                let lower = start + i * count / columns
                let upper = start + (i + 1) * count / columns
                var minimum = samples[lower], maximum = minimum
                for index in lower..<upper {
                    minimum = min(minimum, samples[index])
                    maximum = max(maximum, samples[index])
                }
                return WaveformColumn(minimum: minimum, maximum: maximum)
            }
        }
        let l = reduce(left), r = reduce(right)
        let peak = (l + r).reduce(Float(0)) { max($0, max(abs($1.minimum), abs($1.maximum))) }
        return Self(left: l, right: r, amplitudeRange: max(0.001, peak), durationSeconds: Double(count) / sampleRate)
    }
}
