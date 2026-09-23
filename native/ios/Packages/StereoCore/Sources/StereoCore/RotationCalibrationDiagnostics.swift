import Foundation

public enum RotationCalibrationIssue: String, Codable, Sendable {
    case incomplete, invalidInput, angleMismatch, spectrumChanged
    case insufficientLag, weakResponse, unrepeatable, nonlinearResponse, invalidFit, noUsableResponse
}

/// Bounded statistics from each of the six completed holds; no PCM or images.
public struct RotationStepStatistics: Codable, Sendable {
    public let step: Int
    public let targetDegrees: Double
    public let sampleCount: Int
    public let angleDegrees: Double
    public let levelDbfs: Double
    public let differenceDb: Double
    public let differenceMADDb: Double
    public let lagAvailableFraction: Double
    public let lagSamples: Double?
    public let lagMADSamples: Double?
    public let shape: [Double]
}

public struct RotationResponseDiagnostics: Codable, Sendable {
    public let method: String
    public var issue: RotationCalibrationIssue?
    public var slope: Double?
    public var intercept: Double?
    public let minimumAbsoluteSlope: Double
    public var maximumRepeatErrorDegrees: Double?
    public var rmsErrorDegrees: Double?
    public let repeatErrorLimitDegrees = 6.0
    public let rmsErrorLimitDegrees = 5.0
    public let minimumAvailableFraction = 0.75
    public var accepted: Bool { issue == nil }
}

public struct RotationFitDiagnostics: Codable, Sendable {
    public var issue: RotationCalibrationIssue?
    public var steps: [RotationStepStatistics] = []
    public var responses: [RotationResponseDiagnostics] = []
    public var maximumShapeDifference: Double?
    public let shapeDifferenceLimit = 0.4
    public let thresholdsPhysicallyValidated = false

    public var message: String {
        let reason: String
        switch issue {
        case nil: return "보정 완료 · 같은 소리의 방향 범위를 표시합니다."
        case .incomplete: reason = "보정에 필요한 6단계 측정이 모이지 않았습니다."
        case .invalidInput, .invalidFit: reason = "보정 계산에 사용할 수 없는 측정값이 있습니다."
        case .angleMismatch: reason = "모인 측정 각도가 안내한 각도와 맞지 않습니다."
        case .spectrumChanged: reason = "보정 중 받은 소리의 주파수 구성이 크게 달라졌습니다."
        default:
            // Level is always available; lag may be withheld as ambiguous.
            switch responses.first(where: { $0.method == "levelDifference" })?.issue {
            case .weakResponse: reason = "폰을 돌려도 좌우 소리 크기 차이가 충분히 변하지 않았습니다."
            case .unrepeatable: reason = "같은 방향을 두 번 측정한 결과가 서로 달랐습니다."
            case .nonlinearResponse: reason = "측정값이 현재 앱의 각도 계산 방식에 잘 맞지 않았습니다."
            default: reason = "측정값에서 사용할 수 있는 방향 기준을 만들지 못했습니다."
            }
        }
        return reason + " 측정 상세의 진단 JSON을 공유해 주세요."
    }
}

public struct RotationFitResult: Sendable {
    public let profile: BearingProfile?
    public let diagnostics: RotationFitDiagnostics
}

extension RotationCalibrator {
    /// Same acceptance limits as build 7; expose the actual failed predicate.
    public static func evaluate(_ groups: [[RotationCalibrationSample]]) -> RotationFitResult {
        var diagnostics = RotationFitDiagnostics()
        func failed(_ issue: RotationCalibrationIssue) -> RotationFitResult {
            var value = diagnostics
            value.issue = issue
            return .init(profile: nil, diagnostics: value)
        }
        guard groups.count == 6, groups.allSatisfy({ $0.count >= 20 }), let first = groups.first?.first else {
            return failed(.incomplete)
        }
        let all = groups.flatMap { $0 }
        guard all.allSatisfy({ $0.features.valid && $0.features.sampleRate == first.features.sampleRate
            && $0.angle.isFinite && $0.time.isFinite }) else { return failed(.invalidInput) }
        diagnostics.steps = groups.enumerated().map { index, rows in
            let differences = rows.map { $0.features.differenceDb }
            let lags = rows.compactMap { $0.features.lagSamples }
            let difference = calibrationMedian(differences)
            let lag = lags.isEmpty ? nil : calibrationMedian(lags)
            return .init(step: index + 1, targetDegrees: targets[index], sampleCount: rows.count,
                angleDegrees: calibrationMedian(rows.map(\.angle)),
                levelDbfs: calibrationMedian(rows.map { $0.features.levelDbfs }),
                differenceDb: difference, differenceMADDb: calibrationMedian(differences.map { abs($0 - difference) }),
                lagAvailableFraction: Double(lags.count) / Double(rows.count), lagSamples: lag,
                lagMADSamples: lag.map { center in calibrationMedian(lags.map { abs($0 - center) }) },
                shape: (0..<3).map { band in calibrationMedian(rows.map { $0.features.shape[band] }) })
        }
        guard zip(groups, targets).allSatisfy({ abs(calibrationMedian($0.0.map(\.angle)) - $0.1) < 3.1 }) else {
            return failed(.angleMismatch)
        }
        let shape = (0..<3).map { band in calibrationMedian(all.map { $0.features.shape[band] }) }
        let shapeDifference = all.map { row in zip(row.features.shape, shape).reduce(0.0) { $0 + abs($1.0 - $1.1) } }.max()!
        diagnostics.maximumShapeDifference = shapeDifference
        guard shapeDifference < 0.4 else { return failed(.spectrumChanged) }
        var responses: [BearingResponse] = []
        for method in ["levelDifference", "signalLag"] {
            func value(_ sample: RotationCalibrationSample) -> Double? {
                method == "levelDifference" ? sample.features.differenceDb : sample.features.lagSamples
            }
            var check = RotationResponseDiagnostics(method: method,
                minimumAbsoluteSlope: method == "levelDifference" ? 0.04 : 0.12)
            defer { diagnostics.responses.append(check) }
            guard groups.allSatisfy({ Double($0.compactMap(value).count) >= Double($0.count) * 0.75 }) else {
                check.issue = .insufficientLag; continue
            }
            let x = groups.map { calibrationMedian($0.map(\.angle)) }
            let y = groups.map { calibrationMedian($0.compactMap(value)) }
            let mx = x.reduce(0, +) / 6, my = y.reduce(0, +) / 6
            let denominator = x.reduce(0) { $0 + pow($1 - mx, 2) }
            guard denominator > 100 else { check.issue = .invalidFit; continue }
            let slope = zip(x, y).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / denominator
            guard slope.isFinite else { check.issue = .invalidFit; continue }
            check.slope = slope
            guard abs(slope) >= check.minimumAbsoluteSlope else { check.issue = .weakResponse; continue }
            let intercept = my - slope * mx
            guard intercept.isFinite else { check.issue = .invalidFit; continue }
            check.intercept = intercept
            let repeatError = (0..<3).map { abs(y[$0] - y[$0 + 3]) / abs(slope) }.max()!
            guard repeatError.isFinite else { check.issue = .invalidFit; continue }
            check.maximumRepeatErrorDegrees = repeatError
            guard repeatError < 6 else { check.issue = .unrepeatable; continue }
            let errors = all.compactMap { row -> Double? in value(row).map { (($0 - intercept) / slope) - row.angle } }
            let rms = sqrt(errors.reduce(0) { $0 + $1 * $1 } / Double(errors.count))
            guard rms.isFinite else { check.issue = .invalidFit; continue }
            check.rmsErrorDegrees = rms
            guard rms <= 5 else { check.issue = .nonlinearResponse; continue }
            responses.append(.init(method: method, slope: slope, intercept: intercept, errorDegrees: max(2, rms)))
        }
        guard !responses.isEmpty else { return failed(.noUsableResponse) }
        let shapeSum = shape.reduce(0, +)
        let profile = BearingProfile(responses: responses, sampleRate: first.features.sampleRate,
            shape: shape.map { $0 / shapeSum }, referenceLevelDbfs: calibrationMedian(all.map { $0.features.levelDbfs }))
        return .init(profile: profile, diagnostics: diagnostics)
    }
}

private func calibrationMedian(_ values: [Double]) -> Double {
    let sorted = values.sorted(), count = values.count
    // Called only on nonempty, finite validated statistics. Halves avoid overflow.
    return count.isMultiple(of: 2) ? sorted[count / 2 - 1] / 2 + sorted[count / 2] / 2 : sorted[count / 2]
}
