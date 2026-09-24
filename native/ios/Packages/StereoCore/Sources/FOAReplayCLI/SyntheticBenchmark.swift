import Foundation
import StereoCore

private struct BenchmarkRow: Codable {
    let snrDb: String
    let reflectionGain: Double
    let azimuthDegrees: Int
    let seed: Int
    let state: String
    let errorDegrees: Double?
    let rejectedBands: Int
}

private struct BenchmarkDistribution: Codable {
    let snrDb: String
    let reflectionGain: Double
    let count: Int
    let held: Int
    let heldFraction: Double
    let acceptedMedianDegrees: Double?
    let acceptedP90Degrees: Double?
    let acceptedMaxDegrees: Double?
    let errorHistogram5Degrees: [Int]
}

private struct BenchmarkReport: Codable {
    let experiment = "EXP-025"
    let requirement = "REQ-NATIVE-035"
    let successCriterion = "SC-58"
    let kind = "Synthetic ideal ACN/SN3D through production Swift FOAAnalyzer; not iPhone accuracy or a gate threshold"
    let engine = "StereoCore.FOAAnalyzer; unchanged production Hann/FFT/band/rejection logic"
    let model = "4096 samples at 48000 Hz; W,Y,Z,X; 750/1500/3000/6000 Hz; same-phase reflection at source azimuth +90 degrees; independent uniform channel noise; SNR relative to direct W power before reflection; 10 reproducible seeds. No Apple encoder/room/camera model."
    let physicalAccuracyVerified = false
    let conditions: Int
    let distributions: [BenchmarkDistribution]
    let rows: [BenchmarkRow]
}

func syntheticBenchmark() throws -> Data {
    let n = 4096
    let bins = [64.0, 128.0, 256.0, 512.0]
    let wave = (0..<n).map { i in
        bins.reduce(0.0) { $0 + sin(2 * Double.pi * $1 * Double(i) / Double(n)) } * 0.04
    }
    let power = wave.reduce(0) { $0 + $1 * $1 } / Double(n)
    var rows = [BenchmarkRow]()
    for snr in ["inf", "20", "10", "0"] {
        for reflection in [0.0, 0.7, 1.4] {
            for azimuth in stride(from: -180, to: 180, by: 30) {
                let angle = Double(azimuth) * Double.pi / 180
                let direct = [1.0, sin(angle), 0.0, cos(angle)]
                let reflected = [1.0, sin(angle + Double.pi / 2), 0.0, cos(angle + Double.pi / 2)]
                for seed in 1...10 {
                    let noiseScale = snr == "inf" ? 0 : sqrt(power / pow(10, Double(snr)! / 10))
                    var random = UInt32(seed)
                    var channels = Array(repeating: [Float](repeating: 0, count: n), count: 4)
                    for c in 0..<4 {
                        for i in 0..<n {
                            random = 1664525 &* random &+ 1013904223
                            let noise = (Double(random) / 4294967296 - 0.5) * sqrt(12) * noiseScale
                            channels[c][i] = Float(wave[i] * (direct[c] + reflection * reflected[c]) + noise)
                        }
                    }
                    let result = FOAAnalyzer.analyze(channels, sampleRate: 48000)
                    var vector = Vector3.zero
                    for region in result.regions {
                        vector = vector + region.direction * pow(10, region.levelDbfs / 10)
                    }
                    var error: Double?
                    if vector.length > 1e-12 {
                        let estimated = atan2(vector.y, vector.x) * 180 / Double.pi
                        let delta = abs(estimated - Double(azimuth)).truncatingRemainder(dividingBy: 360)
                        error = min(delta, 360 - delta)
                    }
                    rows.append(.init(snrDb: snr, reflectionGain: reflection, azimuthDegrees: azimuth,
                        seed: seed, state: result.state, errorDegrees: error, rejectedBands: result.rejectedBands))
                }
            }
        }
    }
    var summaries = [BenchmarkDistribution]()
    for snr in ["inf", "20", "10", "0"] {
        for reflection in [0.0, 0.7, 1.4] {
            let selected = rows.filter { $0.snrDb == snr && $0.reflectionGain == reflection }
            let errors = selected.compactMap(\.errorDegrees).sorted()
            let held = selected.count - errors.count
            var histogram = [Int](repeating: 0, count: 37)
            for value in errors { histogram[min(36, Int(value / 5))] += 1 }
            summaries.append(.init(snrDb: snr, reflectionGain: reflection, count: selected.count, held: held,
                heldFraction: Double(held) / Double(selected.count),
                acceptedMedianDegrees: errors.isEmpty ? nil : errors[(errors.count - 1) / 2],
                acceptedP90Degrees: errors.isEmpty ? nil : errors[Int(ceil(Double(errors.count) * 0.9)) - 1],
                acceptedMaxDegrees: errors.last, errorHistogram5Degrees: histogram))
        }
    }
    return try DiagnosticExport.encoder().encode(BenchmarkReport(conditions: rows.count, distributions: summaries, rows: rows))
}
