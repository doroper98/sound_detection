import XCTest
@testable import StereoCore

final class DirectionCalibrationTests: XCTestCase {
    private func analysis(lag: Int = 6, status: LagStatus = .candidate, rate: Double = 48_000) -> StereoAnalysis {
        StereoAnalysis(sampleRate: rate, sampleCount: Int(rate / 10), channels: [
            ChannelLevel(rmsDbfs: -30, peak: 0.1, active: true, clipped: false),
            ChannelLevel(rmsDbfs: -33, peak: 0.07, active: true, clipped: false)],
            zeroLagCorrelation: 0.2, relativeDifference: 0.4, gainAdjustedResidual: 0.4,
            duplicateSuspected: false, status: status, rightMinusLeftLagSamples: status == .candidate ? lag : nil,
            rightMinusLeftLagSeconds: status == .candidate ? Double(lag) / rate : nil,
            peakCorrelation: 0.9, peakMargin: status == .candidate ? 0.4 : 0.001, searchLimitSamples: 48)
    }
    private func pose(at time: Double, degrees: Double = 0) -> AlignedOrientation {
        AlignedOrientation(sample: OrientationSample(timestampSeconds: time,
            quaternion: [0, 0, sin(degrees * .pi / 360), cos(degrees * .pi / 360)])!,
            motionMinusAudioSeconds: 0, rotationFromStartDegrees: degrees)
    }
    private func trial(_ session: inout DirectionCalibration, at start: Double, lag: Int,
                       status: LagStatus = .candidate, degrees: Double = 0, motion: Bool = true) {
        XCTAssertTrue(session.begin(at: start))
        for i in 0..<49 {
            let midpoint = start + 3.06 + Double(i) * 0.1
            session.append(analysis: analysis(lag: lag, status: status), midpoint: midpoint,
                orientation: motion ? pose(at: midpoint, degrees: degrees) : nil)
        }
        session.tick(at: start + 8.3)
    }

    func testSixTrialsCanObserveRepeatableOrderButNeverVerifyPhysicalCalibration() throws {
        var session = DirectionCalibration()
        for (i, lag) in [-12, 0, 12, -11, 1, 13].enumerated() { trial(&session, at: Double(i) * 10, lag: lag) }
        let report = session.snapshot(at: 60)
        XCTAssertEqual(report.state, "complete")
        XCTAssertEqual(report.comparison, "repeatableSeparation")
        XCTAssertFalse(report.acousticCalibrationVerified)
        XCTAssertEqual(report.trials.count, 6)
        XCTAssertTrue(report.trials.allSatisfy(\.usable))
        XCTAssertEqual(report.trials[0].medianRightMinusLeftDb, -3)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as! [String: Any]
        XCTAssertEqual(json["acousticCalibrationVerified"] as? Bool, false)
        XCTAssertEqual((json["trials"] as? [[String: Any]])?.count, 6)
    }

    func testIdenticalLagEverywhereIsNotDirectionalEvidence() {
        var session = DirectionCalibration()
        for i in 0..<6 { trial(&session, at: Double(i) * 10, lag: 7) }
        XCTAssertEqual(session.snapshot(at: 60).comparison, "noClearSeparation")
    }

    func testAmbiguousFramesPreservedWithoutPromotingThemToCandidates() {
        var session = DirectionCalibration()
        for i in 0..<6 { trial(&session, at: Double(i) * 10, lag: 0, status: .ambiguous) }
        let report = session.snapshot(at: 60)
        XCTAssertEqual(report.comparison, "insufficientQuality")
        XCTAssertEqual(report.trials[0].statusCounts["ambiguous"], 49)
        XCTAssertNil(report.trials[0].medianLagSeconds)
        XCTAssertTrue(report.trials[0].qualityIssues.contains("insufficientLagCandidates"))
    }

    func testPhoneMotionAcrossTrialsAndMissingSensorBlockComparison() {
        var session = DirectionCalibration()
        trial(&session, at: 0, lag: -12)
        trial(&session, at: 10, lag: 0, degrees: 15)
        trial(&session, at: 20, lag: 12, motion: false)
        let report = session.snapshot(at: 30)
        XCTAssertTrue(report.trials[1].qualityIssues.contains("phoneMoved"))
        XCTAssertTrue(report.trials[2].qualityIssues.contains("missingOrientation"))
    }

    func testCancellationPreservesPartialTrialWithoutAdvancingAndResetClearsIt() {
        var session = DirectionCalibration()
        XCTAssertTrue(session.begin(at: 0))
        session.append(analysis: analysis(), midpoint: 3.1, orientation: pose(at: 3.1))
        session.cancel(reason: "background")
        session.tick(at: 20)
        XCTAssertEqual(session.snapshot(at: 20).nextStep, 0)
        XCTAssertFalse(session.snapshot(at: 20).trials[0].completed)
        XCTAssertEqual(session.snapshot(at: 20).trials[0].interruptionReason, "background")
        XCTAssertTrue(session.begin(at: 21))
        session = DirectionCalibration()
        XCTAssertTrue(session.snapshot(at: 22).trials.isEmpty)
    }

    func testSettlingOverlappingLateAndSparseBuffersDoNotCountAsFiveSeconds() {
        var session = DirectionCalibration()
        XCTAssertTrue(session.begin(at: 0))
        for time in [1.0, 2.0, 3.02, 3.1, 3.1, 7.99, 9.0] {
            session.append(analysis: analysis(), midpoint: time, orientation: pose(at: time))
        }
        session.tick(at: 8.3)
        let result = session.snapshot(at: 9).trials[0]
        XCTAssertEqual(result.observations.count, 1)
        XCTAssertTrue(result.qualityIssues.contains("insufficientCoverage"))
    }

    func testInconsistentRepeatsAndSamplingRateChangesAreRejected() {
        var session = DirectionCalibration()
        for (i, lag) in [-12, 0, 12, 0, 12, 24].enumerated() { trial(&session, at: Double(i) * 10, lag: lag) }
        XCTAssertEqual(session.snapshot(at: 60).comparison, "notRepeatable")
        session = DirectionCalibration()
        trial(&session, at: 0, lag: 7)
        XCTAssertTrue(session.begin(at: 10))
        session.append(analysis: analysis(rate: 44_100), midpoint: 13.1, orientation: pose(at: 13.1))
        session.tick(at: 18.3)
        XCTAssertTrue(session.snapshot(at: 19).trials[1].qualityIssues.contains("sampleRateChanged"))
    }
}
