import XCTest
@testable import StereoCore

final class ContinuousTrackingTests: XCTestCase {
    private func observation(_ time: Double, lag: Int = 7, status: LagStatus = .candidate) -> TimedLag {
        let analysis = StereoAnalysis(sampleRate: 48_000, sampleCount: 2048, channels: [],
            zeroLagCorrelation: 0, relativeDifference: 1, gainAdjustedResidual: 1,
            duplicateSuspected: false, status: status,
            rightMinusLeftLagSamples: status == .candidate ? lag : nil,
            rightMinusLeftLagSeconds: status == .candidate ? Double(lag) / 48_000 : nil,
            peakCorrelation: 0.9, peakMargin: 0.3, searchLimitSamples: 48)
        return TimedLag(timeSeconds: time, analysis: analysis)
    }

    func testIsolatedOutlierDoesNotMoveMedian() throws {
        var tracker = ContinuousLagTracker()
        for i in 0..<10 { tracker.append(observation(Double(i) * 0.04, lag: i == 8 ? -30 : 7)) }
        let result = tracker.snapshot(at: 0.36)
        XCTAssertEqual(result.state, .tracking)
        XCTAssertEqual(try XCTUnwrap(result.estimateSeconds), 7 / 48_000, accuracy: 1e-9)
    }

    func testStepChangeReplacesOldEstimateWithinHalfSecond() throws {
        var tracker = ContinuousLagTracker()
        for i in 0..<30 { tracker.append(observation(Double(i) * 0.05, lag: i < 20 ? 7 : -9)) }
        let result = tracker.snapshot(at: Double(29) * 0.05)
        XCTAssertEqual(try XCTUnwrap(result.estimateSeconds), -9 / 48_000, accuracy: 1e-9)
    }

    func testSilenceImmediatelyHidesPreviousEstimate() {
        var tracker = ContinuousLagTracker()
        for i in 0..<10 { tracker.append(observation(Double(i) * 0.05)) }
        tracker.append(observation(0.5, status: .silentChannel))
        let result = tracker.snapshot(at: 0.5)
        XCTAssertEqual(result.state, .noReliableSignal)
        XCTAssertNil(result.estimateSeconds)
    }

    func testStaleStoppedAndNewRunDoNotShowOldEstimate() {
        var tracker = ContinuousLagTracker()
        for i in 0..<10 { tracker.append(observation(Double(i) * 0.05)) }
        XCTAssertEqual(tracker.snapshot(at: 1).state, .stale)
        XCTAssertNil(tracker.snapshot(at: 1).estimateSeconds)
        XCTAssertEqual(tracker.snapshot(at: 1, stopped: true).state, .stopped)
        tracker = ContinuousLagTracker()
        tracker.append(observation(1.1, lag: -9))
        XCTAssertEqual(tracker.snapshot(at: 1.1).state, .collecting)
    }

    func testHighScatterIsReportedAsChanging() {
        var tracker = ContinuousLagTracker()
        for i in 0..<10 { tracker.append(observation(Double(i) * 0.04, lag: i.isMultiple(of: 2) ? -20 : 20)) }
        let result = tracker.snapshot(at: 0.36)
        XCTAssertEqual(result.state, .changing)
        XCTAssertGreaterThan(result.spreadSeconds ?? 0, 0.0003)
    }

    func testLowValidFractionDoesNotBecomeConfident() {
        var tracker = ContinuousLagTracker()
        for i in 0..<10 { tracker.append(observation(Double(i) * 0.05, status: i.isMultiple(of: 3) ? .candidate : .ambiguous)) }
        let result = tracker.snapshot(at: 0.45)
        XCTAssertEqual(result.state, .noReliableSignal)
        XCTAssertNil(result.estimateSeconds)
    }

    func testHistoryIsBoundedAndTimestampsCannotGoBackward() {
        var tracker = ContinuousLagTracker()
        for i in 0..<1000 { tracker.append(observation(Double(i) * 0.001)) }
        XCTAssertLessThanOrEqual(tracker.snapshot(at: 1).history.count, 240)
        XCTAssertFalse(tracker.append(observation(0.5)))
        XCTAssertFalse(tracker.append(observation(.nan)))
        XCTAssertTrue(tracker.snapshot(at: 4).history.isEmpty)
    }

    func testPoseMatchingRejectsStaleAndPreservesRotation() throws {
        var poses = OrientationHistory()
        poses.append(try XCTUnwrap(OrientationSample(timestampSeconds: 10, quaternion: [0, 0, 0, 1])))
        poses.append(try XCTUnwrap(OrientationSample(timestampSeconds: 10.1, quaternion: [0, 0, sin(.pi / 4), cos(.pi / 4)])))
        let aligned = try XCTUnwrap(poses.aligned(at: 10.09))
        XCTAssertEqual(aligned.motionMinusAudioSeconds, 0.01, accuracy: 1e-9)
        XCTAssertEqual(aligned.rotationFromStartDegrees, 90, accuracy: 1e-7)
        XCTAssertNil(poses.aligned(at: 11))
        XCTAssertNil(poses.aligned(at: .nan))
    }

    func testQuaternionSignAndScaleDoNotChangeOrientation() throws {
        let a = try XCTUnwrap(OrientationSample(timestampSeconds: 0, quaternion: [0, 0, 0, 2]))
        let b = try XCTUnwrap(OrientationSample(timestampSeconds: 0, quaternion: [0, 0, 0, -1]))
        XCTAssertEqual(a.angularDistanceDegrees(to: b), 0, accuracy: 1e-9)
        XCTAssertNil(OrientationSample(timestampSeconds: 0, quaternion: [0, 0, 0, 0]))
        XCTAssertNil(OrientationSample(timestampSeconds: 0, quaternion: [0, 0, .nan, 1]))
    }

    func testOldPoseCannotOverwriteLatest() throws {
        var poses = OrientationHistory()
        poses.append(try XCTUnwrap(OrientationSample(timestampSeconds: 20, quaternion: [0, 0, 0, 1])))
        poses.append(try XCTUnwrap(OrientationSample(timestampSeconds: 19, quaternion: [0, 0, 1, 0])))
        XCTAssertNil(poses.aligned(at: 19))
        XCTAssertEqual(poses.aligned(at: 20)?.rotationFromStartDegrees, 0)
    }
}
