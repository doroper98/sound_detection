import XCTest
@testable import StereoCore

final class SpatialSynchronizationTests: XCTestCase {
    private func pose(_ time: Double, x: Double = 0) -> SpatialPose {
        .init(time: time,origin: .init(x,0,0),right: .init(1,0,0),up: .init(0,1,0),forward: .init(0,0,-1))
    }
    private var feature: AcousticFeatures {
        .init(sampleRate: 48000,levelDbfs: -38,differenceDb: -0.35,lagSamples: -5,shape: [0.05,0.13,0.82])
    }
    func testLateCameraDeliveryRecoversAndAdvancesFirstCalibrationStep() {
        var history=SpatialPoseHistory(), queue=SpatialAudioSynchronizer(), calibration=RotationCalibrator()
        calibration.begin(pose: pose(10))
        var recovered=0
        for i in 0..<28 {
            let middle=10.2+Double(i)*0.1
            // At audio delivery the camera is 110 ms behind the buffer's END.
            history.append(pose(middle-0.06))
            queue.append(.init(features: feature,midpoint: middle,duration: 0.1),at: middle+0.06)
            XCTAssertTrue(queue.drain(at: middle+0.06) {
                history.inspect(midpoint: $0,duration: $1,now: $2)
            }.isEmpty)
            history.append(pose(middle)); history.append(pose(middle+0.05))
            let delivered=queue.drain(at: middle+0.15) {
                history.inspect(midpoint: $0,duration: $1,now: $2)
            }
            XCTAssertEqual(delivered.count,1)
            for item in delivered {
                XCTAssertEqual(item.inspection.issue,.matched)
                XCTAssertTrue(item.waitedForCamera)
                recovered+=1
                if let p=item.inspection.pose { calibration.append(features: item.sample.features,pose: p) }
            }
        }
        XCTAssertEqual(recovered,28)
        XCTAssertEqual(calibration.snapshot().step,1)
    }
    func testMissingCameraExpiresInsteadOfSilentlyWaitingForever() throws {
        var queue=SpatialAudioSynchronizer(), calibration=RotationCalibrator()
        calibration.begin(pose: pose(10))
        queue.append(.init(features: feature,midpoint: 10.1,duration: 0.1),at: 10.16)
        let inspect: (Double,Double,Double)->PoseAlignmentInspection = { _,_,_ in .init(issue: .cameraStale) }
        XCTAssertTrue(queue.drain(at: 10.16,inspect: inspect).isEmpty)
        let item=try XCTUnwrap(queue.drain(at: 10.45,inspect: inspect).first)
        XCTAssertEqual(item.inspection.issue,.audioTooOld)
        XCTAssertEqual(item.inspection.waitingForCameraIssue,.cameraStale)
        calibration.waitForPose(item.inspection.instruction,at: 10.45)
        XCTAssertTrue(calibration.snapshot().movementInstruction.contains("카메라 자세가 갱신되지"))
        XCTAssertEqual(calibration.snapshot().progress,0)
        XCTAssertNil(calibration.profile)
        let encoded=try JSONEncoder().encode(calibration.snapshot())
        XCTAssertEqual(try JSONDecoder().decode(RotationCalibrationState.self,from: encoded).blockingReason,"poseUnavailable")
        calibration.tick(at: 191)
        XCTAssertFalse(calibration.active)
    }
    func testProviderCannotBypassFreshnessAndOldPoseCannotReplaceMissingHistory() {
        var queue=SpatialAudioSynchronizer(), history=SpatialPoseHistory()
        history.append(pose(9))
        XCTAssertEqual(history.inspect(midpoint: 10,duration: 0.1,now: 10.1).issue,.cameraStale)
        queue.append(.init(features: feature,midpoint: 10,duration: 0.1),at: 10.1)
        let items=queue.drain(at: 10.31) { _,_,_ in .init(issue: .matched,pose: self.pose(10)) }
        XCTAssertEqual(items.first?.inspection.issue,.audioTooOld)
        XCTAssertNil(items.first?.inspection.pose)
    }
    func testRejectionsDistinguishTrackingTimingAndActualMovement() {
        var history=SpatialPoseHistory()
        for i in 0...10 { history.append(pose(10+Double(i)/100,x: Double(i)*0.01)) }
        XCTAssertEqual(history.inspect(midpoint: 10.05,duration: 0.1,now: 10.12).issue,.movementDuringAudio)
        XCTAssertEqual(history.inspect(midpoint: 10.05,duration: 0.1,now: 10.12,trackingState: "limited").issue,.trackingUnavailable)
        XCTAssertEqual(history.inspect(midpoint: 10.05,duration: 0.1,now: 10.12,running: false).issue,.cameraStopped)
        XCTAssertEqual(history.inspect(midpoint: 12,duration: 0.1,now: 10.12).issue,.audioInFuture)
        XCTAssertEqual(history.inspect(midpoint: 10.05,duration: .nan,now: 10.12).issue,.invalidTiming)
    }
    func testQueueIsBoundedAndClearDropsOldSessionSummaries() {
        var queue=SpatialAudioSynchronizer()
        for i in 0..<100 { queue.append(.init(features: feature,midpoint: Double(i),duration: 0.1),at: Double(i)) }
        XCTAssertEqual(queue.pendingCount,4); XCTAssertEqual(queue.overflowCount,96)
        queue.clear()
        XCTAssertTrue(queue.drain(at: 100) { _,_,_ in .init(issue: .missingCameraFrames) }.isEmpty)
    }
    func testHeadlineExplainsAudioAndTranslationBlocksEvenAtCorrectAngle() {
        var calibration=RotationCalibrator()
        calibration.begin(pose: pose(10))
        calibration.append(features: nil,pose: pose(10.1))
        XCTAssertTrue(calibration.snapshot().movementInstruction.contains("소리가 약하거나"))
        calibration.append(features: feature,pose: pose(10.2,x: 0.1))
        XCTAssertTrue(calibration.snapshot().movementInstruction.contains("폰 위치가 움직였습니다"))
        calibration.append(features: feature,pose: pose(10.3))
        XCTAssertTrue(calibration.snapshot().movementInstruction.contains("멈추세요"))
    }
}
