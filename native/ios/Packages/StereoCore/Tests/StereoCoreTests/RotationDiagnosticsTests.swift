import XCTest
@testable import StereoCore

final class RotationDiagnosticsTests: XCTestCase {
    private func groups(_ feature: (Double, Int, Int) -> AcousticFeatures) -> [[RotationCalibrationSample]] {
        RotationCalibrator.targets.enumerated().map { step, angle in
            (0..<25).map { i in .init(angle: angle, features: feature(angle, step, i), time: Double(step * 30 + i) / 10) }
        }
    }
    private func feature(_ difference: Double, lag: Double? = nil, shape: [Double] = [0.1, 0.2, 0.7]) -> AcousticFeatures {
        .init(sampleRate: 48000, levelDbfs: -24, differenceDb: difference, lagSamples: lag, shape: shape)
    }
    private func pose(_ time: Double, bearing: Double = 0) -> SpatialPose {
        let yaw = -bearing * .pi / 180
        return .init(time: time, origin: .zero, right: .init(cos(yaw), 0, sin(yaw)), up: .init(0, 1, 0),
            forward: .init(sin(yaw), 0, -cos(yaw)))
    }
    func testFlatResponseReportsSixHoldsAndMissingLagWithoutInventingProfile() throws {
        let result = RotationCalibrator.evaluate(groups { _, _, _ in self.feature(1) })
        XCTAssertNil(result.profile)
        XCTAssertEqual(result.diagnostics.issue, .noUsableResponse)
        XCTAssertEqual(result.diagnostics.responses.map(\.issue), [.weakResponse, .insufficientLag])
        XCTAssertEqual(result.diagnostics.steps.count, 6)
        XCTAssertEqual(result.diagnostics.steps.reduce(0) { $0 + $1.sampleCount }, 150)
        XCTAssertTrue(result.diagnostics.message.contains("차이가 충분히 변하지"))
        let encoded = try JSONEncoder().encode(result.diagnostics)
        XCTAssertNotNil(String(data: encoded, encoding: .utf8))
    }
    func testRepeatedDirectionMismatchIsDistinctFromFlatResponse() {
        let result = RotationCalibrator.evaluate(groups { angle, step, _ in self.feature(angle * 0.2 + (step >= 3 ? 2 : 0)) })
        XCTAssertNil(result.profile)
        XCTAssertEqual(result.diagnostics.responses[0].issue, .unrepeatable)
        XCTAssertEqual(result.diagnostics.responses[0].maximumRepeatErrorDegrees!, 10, accuracy: 0.01)
        XCTAssertTrue(result.diagnostics.message.contains("두 번 측정한 결과"))
    }
    func testWithinHoldScatterReportsFitErrorWithoutWeakeningLimit() {
        let result = RotationCalibrator.evaluate(groups { angle, _, i in self.feature(angle * 0.2 + Double(i % 3 - 1) * 2) })
        XCTAssertNil(result.profile)
        XCTAssertEqual(result.diagnostics.responses[0].issue, .nonlinearResponse)
        XCTAssertGreaterThan(result.diagnostics.responses[0].rmsErrorDegrees!, 5)
        XCTAssertEqual(result.diagnostics.responses[0].rmsErrorLimitDegrees, 5)
    }
    func testSpectrumChangeKeepsStepEvidenceAndDistinctCause() {
        let result = RotationCalibrator.evaluate(groups { angle, step, _ in
            self.feature(angle * 0.2, shape: step < 3 ? [0.8, 0.1, 0.1] : [0.1, 0.2, 0.7])
        })
        XCTAssertNil(result.profile)
        XCTAssertEqual(result.diagnostics.issue, .spectrumChanged)
        XCTAssertEqual(result.diagnostics.steps.count, 6)
        XCTAssertGreaterThan(result.diagnostics.maximumShapeDifference!, 0.4)
    }
    func testValidLevelResponseStillPassesWhenLagIsUnavailable() throws {
        let result = RotationCalibrator.evaluate(groups { angle, _, _ in self.feature(angle * -0.2 + 1) })
        let profile = try XCTUnwrap(result.profile)
        XCTAssertNil(result.diagnostics.issue)
        XCTAssertTrue(result.diagnostics.responses[0].accepted)
        XCTAssertEqual(result.diagnostics.responses[1].issue, .insufficientLag)
        XCTAssertEqual(try XCTUnwrap(profile.estimate(feature(-1), at: 1)).degrees, 10, accuracy: 0.001)
    }
    func testMalformedInputReturnsEncodableFailureAndWrongAnglesAreNamed() throws {
        XCTAssertEqual(RotationCalibrator.evaluate([]).diagnostics.issue, .incomplete)
        let invalid = RotationCalibrator.evaluate(groups { _, _, _ in self.feature(.nan) })
        XCTAssertEqual(invalid.diagnostics.issue, .invalidInput)
        _ = try JSONEncoder().encode(invalid.diagnostics)
        let wrongAngles = groups { angle, _, _ in self.feature(angle * 0.2) }.map { rows in
            rows.map { RotationCalibrationSample(angle: 0, features: $0.features, time: $0.time) }
        }
        XCTAssertEqual(RotationCalibrator.evaluate(wrongAngles).diagnostics.issue, .angleMismatch)
    }
    func testRejectedStateRetainsDiagnosticsForExportAndNewRunClearsThem() throws {
        var calibrator = RotationCalibrator()
        calibrator.begin(pose: pose(1))
        var time = 1.0
        for angle in RotationCalibrator.targets {
            for _ in 0..<28 {
                time += 0.1
                calibrator.append(features: feature(1), pose: pose(time, bearing: angle))
            }
        }
        let state = calibrator.snapshot()
        XCTAssertEqual(state.phase, "rejected")
        XCTAssertEqual(state.step, 6)
        XCTAssertEqual(state.progress, 1)
        XCTAssertEqual(state.diagnostics?.steps.count, 6)
        XCTAssertNil(state.profile)
        let decoded = try JSONDecoder().decode(RotationCalibrationState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.diagnostics?.responses.first?.issue, .weakResponse)
        // SpatialModel.stop only cancels an active collection; rejected data remains.
        XCTAssertFalse(calibrator.active)
        calibrator.begin(pose: pose(time + 1))
        XCTAssertNil(calibrator.snapshot().diagnostics)
    }
    func testMotionPromptUsesPhoneTurnSignAndProgressRequiresElapsedTime() {
        var calibrator = RotationCalibrator()
        calibrator.begin(pose: pose(1))
        for i in 0..<50 { calibrator.append(features: feature(0), pose: pose(1 + Double(i) * 0.01)) }
        XCTAssertEqual(calibrator.snapshot().step, 0)
        XCTAssertLessThan(calibrator.snapshot().progress, 0.25)
        for i in 0..<30 { calibrator.append(features: feature(0), pose: pose(1.5 + Double(i) * 0.1)) }
        XCTAssertEqual(calibrator.snapshot().step, 1)
        XCTAssertTrue(calibrator.snapshot().movementInstruction.contains("오른쪽"))
        calibrator.append(features: feature(-5), pose: pose(4.5, bearing: -25))
        XCTAssertTrue(calibrator.snapshot().movementInstruction.contains("멈추세요"))
        calibrator.append(features: feature(-7), pose: pose(4.6, bearing: -35))
        XCTAssertTrue(calibrator.snapshot().movementInstruction.contains("왼쪽"))
    }
}
