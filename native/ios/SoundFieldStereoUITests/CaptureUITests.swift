import XCTest
import UIKit

final class CaptureUITests: XCTestCase {
    func testResearchRecordingDefaultOffAndSharedArchive() {
        let app = launch(["--synthetic-foa"], details: false)
        app.buttons["detailsButton"].tap()
        let toggle = app.switches["researchToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertEqual(toggle.value as? String, "0")
        app.buttons["닫기"].tap()
        app.buttons["liveCaptureButton"].tap()
        // Recording must work even while direction is unconfirmed. Heatmap
        // confirmation has its own tests; use actual PCM arrival here.
        awaitLivePCM(app)
        XCTAssertFalse(app.staticTexts["researchREC"].exists)
        app.buttons["liveCaptureButton"].tap()
        app.buttons["detailsButton"].tap()
        toggle.tap()
        app.buttons["닫기"].tap()
        app.buttons["liveCaptureButton"].tap()
        XCTAssertTrue(app.staticTexts["researchREC"].waitForExistence(timeout: 10))
        let badge = app.staticTexts["researchREC"]
        expectation(for: NSPredicate(format: "label MATCHES %@", ".*REC ([2-9]|[1-9][0-9]+)초"), evaluatedWith: badge)
        waitForExpectations(timeout: 30)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "native-build12-research-rec-synthetic"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["liveCaptureButton"].tap()
        app.buttons["detailsButton"].tap()
        let status = app.staticTexts["researchStatus"]
        expectation(for: NSPredicate(format: "label CONTAINS %@", "저장 완료"), evaluatedWith: status)
        waitForExpectations(timeout: 30)
        XCTAssertFalse(app.staticTexts["researchREC"].exists)
        let share = app.buttons["researchShare"]
        reveal(share, in: app)
        share.tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 30))
    }

    func testResearchBackgroundFinalizesAndOptInResetsAfterRelaunch() {
        let app = launch(["--synthetic-foa"], details: false)
        app.buttons["detailsButton"].tap()
        app.switches["researchToggle"].tap()
        app.buttons["닫기"].tap()
        app.buttons["liveCaptureButton"].tap()
        expectation(for: NSPredicate(format: "label MATCHES %@", ".*REC ([2-9]|[1-9][0-9]+)초"), evaluatedWith: app.staticTexts["researchREC"])
        waitForExpectations(timeout: 30)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(app.buttons["liveCaptureButton"].label, "카메라·수음 시작")
        app.buttons["detailsButton"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "저장 완료"), evaluatedWith: app.staticTexts["researchStatus"])
        waitForExpectations(timeout: 30)
        app.terminate()
        app.launch()
        app.buttons["detailsButton"].tap()
        XCTAssertEqual(app.switches["researchToggle"].value as? String, "0")
        XCTAssertTrue(app.buttons["researchShare"].waitForExistence(timeout: 10))
    }

    func testCompactFOACameraKeepsScreenAwakeAndRestoresOnStopAndBackground() {
        let app=launch(["--synthetic-foa"],details: false)
        let button=app.buttons["liveCaptureButton"]
        XCTAssertTrue((button.value as? String ?? "").contains("자동 잠금 기본 설정"))
        button.tap()
        XCTAssertTrue(app.staticTexts["foaFrequency"].waitForExistence(timeout: 30))
        XCTAssertTrue((button.value as? String ?? "").contains("화면 켜짐 유지"))
        let waveform=app.descendants(matching: .any).matching(identifier: "leftWaveform").firstMatch
        XCTAssertGreaterThan(waveform.frame.minY-app.staticTexts["foaStatus"].frame.maxY,app.frame.height*0.55)
        XCTAssertFalse(app.staticTexts["liveLagValue"].exists)
        XCTAssertFalse(app.staticTexts["liveWaveformPerformance"].exists)
        XCTAssertTrue(button.isHittable)
        button.tap()
        XCTAssertTrue((button.value as? String ?? "").contains("자동 잠금 기본 설정"))
        button.tap()
        XCTAssertTrue(app.staticTexts["foaFrequency"].waitForExistence(timeout: 30))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(button.label,"카메라·수음 시작")
        XCTAssertTrue((button.value as? String ?? "").contains("자동 잠금 기본 설정"))
    }
    func testIsolatedFOACandidatesStayHiddenAndTimelineIsAvailable() {
        let app=launch(["--synthetic-foa","--synthetic-foa-isolated"],details: false)
        app.buttons["liveCaptureButton"].tap()
        let status=app.staticTexts["foaStatus"]
        expectation(for: NSPredicate(format: "label CONTAINS %@","방향이 불안정"),evaluatedWith: status)
        waitForExpectations(timeout: 30)
        XCTAssertFalse(app.staticTexts["foaFrequency"].exists)
        app.buttons["liveCaptureButton"].tap()
        app.buttons["detailsButton"].tap()
        XCTAssertTrue(app.staticTexts["foaTimelineSummary"].waitForExistence(timeout: 5))
        let shot=XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name="native-build11-timeline-synthetic"; shot.lifetime = .keepAlways; add(shot)
    }
    func testFOAHeatmapWithoutSixStepCalibration() {
        let app=launch(["--synthetic-foa"],details: false)
        app.buttons["liveCaptureButton"].tap()
        let frequency=app.staticTexts["foaFrequency"]
        XCTAssertTrue(frequency.waitForExistence(timeout: 30))
        XCTAssertTrue(frequency.label.contains("1.5 kHz"))
        XCTAssertFalse(app.staticTexts["rotationCalibrationStep"].exists)
        XCTAssertFalse(app.buttons["calibrationButton"].exists)
        XCTAssertFalse(app.staticTexts["soundPositionCandidate"].exists)
        XCTAssertTrue(app.staticTexts["foaStatus"].label.contains("거리 미측정"))
        attachHeatScreenshot("native-build11-foa-heatmap-synthetic")
        app.buttons["liveCaptureButton"].tap()
        XCTAssertFalse(frequency.exists)
        app.buttons["detailsButton"].tap()
        XCTAssertTrue(app.staticTexts["foaSummary"].waitForExistence(timeout: 5))
    }
    func testFOASilenceClearsHeatmap() {
        let app=launch(["--synthetic-foa","--synthetic-foa-silence"],details: false)
        app.buttons["liveCaptureButton"].tap()
        let status=app.staticTexts["foaStatus"]
        expectation(for: NSPredicate(format: "label CONTAINS %@","소리가 작습니다"),evaluatedWith: status)
        waitForExpectations(timeout: 30)
        XCTAssertFalse(app.staticTexts["foaFrequency"].exists)
    }
    func testPreviousReportSurvivesRestart() {
        let app=launch(["--synthetic-foa"],details: false)
        app.buttons["liveCaptureButton"].tap()
        XCTAssertTrue(app.staticTexts["foaFrequency"].waitForExistence(timeout: 30))
        app.buttons["liveCaptureButton"].tap()
        app.buttons["liveCaptureButton"].tap()
        XCTAssertTrue(app.staticTexts["foaFrequency"].waitForExistence(timeout: 30))
        app.buttons["detailsButton"].tap()
        let heading=app.buttons["savedReportsToggle"]
        reveal(heading,in: app)
        heading.tap()
        XCTAssertEqual(heading.value as? String,"펼침")
        let saved=app.buttons.matching(identifier: "savedReportShare").firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        reveal(saved,in: app)
        saved.tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 10))
    }
    func testLateCameraTimestampsAdvanceFirstStepThroughProductionQueue() {
        let app=launch(["--synthetic-pose-delay"],details: false)
        app.buttons["liveCaptureButton"].tap()
        let step=app.staticTexts["rotationCalibrationStep"]
        expectation(for: NSPredicate(format: "label CONTAINS %@","2/6"),evaluatedWith: step)
        waitForExpectations(timeout: 30)
        XCTAssertTrue(app.staticTexts["rotationMovementInstruction"].label.contains("오른쪽"))
        XCTAssertFalse(app.staticTexts["soundPositionCandidate"].exists)
        let screen=XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screen.name="native-build9-delayed-pose-recovered-synthetic"; screen.lifetime = .keepAlways; add(screen)
        app.buttons["detailsButton"].tap()
        let summary=app.staticTexts["spatialSyncSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertFalse(summary.label.hasSuffix("지연 후 연결 0"))
    }
    func testMissingCameraShowsReasonAndPreservesItAfterStop() {
        let app=launch(["--synthetic-pose-stalled"],details: false)
        app.buttons["liveCaptureButton"].tap()
        let guidance=app.staticTexts["rotationMovementInstruction"]
        expectation(for: NSPredicate(format: "label CONTAINS %@","카메라 자세가 갱신되지"),evaluatedWith: guidance)
        waitForExpectations(timeout: 30)
        XCTAssertTrue(app.staticTexts["rotationCalibrationStep"].label.contains("1/6"))
        XCTAssertFalse(app.staticTexts["soundPositionCandidate"].exists)
        let screen=XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screen.name="native-build9-missing-pose-reason-synthetic"; screen.lifetime = .keepAlways; add(screen)
        app.buttons["liveCaptureButton"].tap()
        app.buttons["detailsButton"].tap()
        let reason=app.staticTexts["lastSpatialCalibration"]
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        XCTAssertTrue(reason.label.contains("카메라 자세가 갱신되지"))
        let export=app.buttons["exportButton"]; reveal(export,in: app)
        XCTAssertTrue(export.isEnabled)
    }
    func testRejectedRotationExplainsCauseAndCannotShowLocation() {
        let app=launch(["--synthetic-bearing","--synthetic-rotation-rejected"],details: false)
        app.buttons["liveCaptureButton"].tap()
        let detail=app.staticTexts["spatialDetail"]
        expectation(for: NSPredicate(format: "label CONTAINS %@","좌우 소리 크기 차이가 충분히 변하지"),evaluatedWith: detail)
        waitForExpectations(timeout: 30)
        XCTAssertTrue(detail.label.contains("진단 JSON"))
        XCTAssertTrue(app.frame.contains(detail.frame))
        XCTAssertFalse(app.staticTexts["soundPositionCandidate"].exists)
        XCTAssertFalse(app.staticTexts["soundHeatFrequency"].exists)
        let screen=XCTAttachment(screenshot: app.screenshot())
        screen.name="native-build8-rejected-synthetic"; screen.lifetime = .keepAlways; add(screen)
        app.buttons["liveCaptureButton"].tap()
        XCTAssertTrue(detail.label.contains("진단 JSON"))
        app.buttons["detailsButton"].tap()
        let export=app.buttons["exportButton"]
        reveal(export,in: app)
        XCTAssertTrue(export.isEnabled)
    }
    func testRotationGuideShowsPhoneMovementAndCanCancel() {
        let app=launch(["--synthetic-bearing","--synthetic-rotation-guide"],details: false)
        app.buttons["liveCaptureButton"].tap()
        let guidance=app.staticTexts["rotationMovementInstruction"]
        XCTAssertTrue(guidance.waitForExistence(timeout: 30))
        XCTAssertTrue(guidance.label.contains("오른쪽"))
        XCTAssertTrue(app.frame.contains(guidance.frame))
        let cancel=app.buttons["rotationCalibrationCancel"]
        XCTAssertTrue(cancel.isHittable)
        let screen=XCTAttachment(screenshot: app.screenshot())
        screen.name="native-build8-rotation-guide-synthetic"; screen.lifetime = .keepAlways; add(screen)
        cancel.tap()
        XCTAssertFalse(guidance.exists)
        XCTAssertFalse(app.staticTexts["soundPositionCandidate"].exists)
    }
    private func attachHeatScreenshot(_ name: String, cool: Bool = false) {
        // A passing AX label can precede a complete rendered frame. Inspect
        // real pixels too, without pausing capture or weakening stale expiry.
        var screenshot=XCUIScreen.main.screenshot()
        var complete=false
        for _ in 0..<6 {
            screenshot=XCUIScreen.main.screenshot()
            if heatPixelsVisible(screenshot,cool: cool) { complete=true; break }
            Thread.sleep(forTimeInterval: 0.3)
        }
        let attachment=XCTAttachment(screenshot: screenshot)
        attachment.name=name; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertTrue(complete,"Heat region and complete header/footer must be present in the captured pixels")
    }
    private func heatPixelsVisible(_ screenshot: XCUIScreenshot, cool: Bool) -> Bool {
        guard let image=UIImage(data: screenshot.pngRepresentation)?.cgImage else { return false }
        let width=201, height=437
        var pixels=[UInt8](repeating: 0,count: width*height*4)
        let drawn=pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context=CGContext(data: raw.baseAddress,width: width,height: height,bitsPerComponent: 8,
                bytesPerRow: width*4,space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image,in: CGRect(x: 0,y: 0,width: width,height: height))
            return true
        }
        guard drawn else { return false }
        var upper=0, lower=0, heat=0
        for y in 0..<height {
            for x in 0..<width {
                let i=(y*width+x)*4
                let r=Int(pixels[i]), g=Int(pixels[i+1]), b=Int(pixels[i+2])
                let fraction=Double(y)/Double(height)
                if g>120 && g>r+20 && g>b+10 {
                    if (0.07...0.17).contains(fraction) { upper+=1 }
                    if (0.83...0.97).contains(fraction) { lower+=1 }
                }
                if (0.3...0.7).contains(fraction) {
                    if cool ? (b>25 && b>r+15 && b>g+8) : (r>65 && g>25 && r>g+8 && g>b+10) { heat+=1 }
                }
            }
        }
        return upper>20 && lower>20 && heat>(cool ? 80 : 40)
    }
    func testHeatIslandShowsMeasuredFrequencyAndLevelForLoudAndQuietInput() {
        for quiet in [false,true] {
            let extra=["--synthetic-bearing","--synthetic-position","--synthetic-heat-tone"]
                + (quiet ? ["--synthetic-heat-quiet"] : [])
            let app=launch(extra,details: false)
            app.buttons["liveCaptureButton"].tap()
            let frequency=app.staticTexts["soundHeatFrequency"]
            // At 48 kHz / 4096, the nearest FFT bin to the 1 kHz fixture is 996.09 Hz.
            expectation(for: NSPredicate(format: "label == %@","주파수 ≈ 996 Hz"),evaluatedWith: frequency)
            let level=app.staticTexts["soundHeatLevel"]
            expectation(for: NSPredicate(format: "label == %@",quiet ? "입력 -57 dBFS" : "입력 -23 dBFS"),evaluatedWith: level)
            waitForExpectations(timeout: 30)
            XCTAssertTrue(app.frame.contains(frequency.frame))
            XCTAssertTrue(app.staticTexts["soundPositionCandidate"].exists)
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "soundHeatLegend").firstMatch.exists)
            attachHeatScreenshot(quiet ? "native-build7-heat-quiet" : "native-build7-heat-tone",cool: quiet)
            app.buttons["liveCaptureButton"].tap()
            XCTAssertFalse(frequency.exists)
            XCTAssertFalse(level.exists)
            app.terminate()
        }
    }
    func testHeatFrequencyAndRegionClearWhenAudioBecomesStale() {
        let app=launch(["--synthetic-bearing","--synthetic-position","--synthetic-heat-tone","--synthetic-waveform-stale"],details: false)
        app.buttons["liveCaptureButton"].tap()
        let frequency=app.staticTexts["soundHeatFrequency"]
        XCTAssertTrue(frequency.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "exists == false"),evaluatedWith: frequency)
        waitForExpectations(timeout: 6)
        XCTAssertFalse(app.staticTexts["soundPositionCandidate"].exists)
        XCTAssertEqual(app.buttons["liveCaptureButton"].label,"계측 중지")
    }
    func testIndependentPoseFixtureProjectsCandidateAndClearsInBackground() {
        let app=launch(["--synthetic-bearing","--synthetic-position"],details: false)
        app.buttons["liveCaptureButton"].tap()
        XCTAssertTrue(app.staticTexts["soundPositionCandidate"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["soundPositionCandidate"].label.contains("위치 후보"))
        XCTAssertTrue(app.staticTexts["soundHeatFrequency"].label.hasPrefix("대역"))
        attachHeatScreenshot("native-build7-position-synthetic")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertFalse(app.staticTexts["soundPositionCandidate"].exists)
        XCTAssertFalse(app.staticTexts["soundHeatFrequency"].exists)
        XCTAssertEqual(app.buttons["liveCaptureButton"].label,"카메라·수음 시작")
    }
    func testBearingOverlayUsesEmpiricalProfileAndClearsOnStop() {
        let app=launch(["--synthetic-bearing"],details: false)
        app.buttons["liveCaptureButton"].tap()
        let status=app.staticTexts["spatialStatus"]
        expectation(for: NSPredicate(format: "label CONTAINS %@","오른쪽 12°"),evaluatedWith: status)
        waitForExpectations(timeout: 30)
        XCTAssertFalse(app.staticTexts["soundPositionCandidate"].exists)
        attachHeatScreenshot("native-build7-bearing-synthetic")
        app.buttons["liveCaptureButton"].tap()
        XCTAssertTrue(status.label.contains("소리 방향·위치 찾기"))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "soundBearingBand").firstMatch.exists)
    }
    func testNoCalibrationOrSilentChannelDoesNotInventSoundDirection() {
        let app=launch(["--synthetic-bearing","--synthetic-silent-right"],details: false)
        app.buttons["liveCaptureButton"].tap()
        awaitLivePCM(app)
        let reticle=app.descendants(matching: .any).matching(identifier: "cameraAlignmentReticle").firstMatch
        XCTAssertTrue(reticle.exists)
        XCTAssertEqual(reticle.frame.midX,app.frame.midX,accuracy: 2)
        XCTAssertEqual(reticle.frame.midY,app.frame.midY,accuracy: 2)
        XCTAssertFalse(app.staticTexts["spatialStatus"].label.contains("방향 추정"))
        XCTAssertFalse(app.staticTexts["soundPositionCandidate"].exists)
        app.buttons["spatialGuideButton"].tap()
        let start=app.buttons["rotationCalibrationStart"]
        reveal(start,in: app)
        XCTAssertFalse(start.isEnabled) // Simulator cannot impersonate a physical AR camera.
        let screen=XCTAttachment(screenshot: app.screenshot())
        screen.name="native-build7-guide-synthetic"; screen.lifetime = .keepAlways; add(screen)
    }
    private func awaitLivePCM(_ app: XCUIApplication) {
        // Startup/lifecycle readiness means a real analysis arrived. A rolling
        // lag estimate may legitimately be withheld under simulator load.
        expectation(for: NSPredicate(format: "value MATCHES %@", "분석 [1-9][0-9]*구간"),
                    evaluatedWith: app.staticTexts["liveCaptureStatus"])
        waitForExpectations(timeout: 30)
    }
    func testFreshWaveformsExceedAnalysisCadence() {
        let app = launch(details: false)
        app.buttons["liveCaptureButton"].tap()
        let performance = app.buttons["liveCaptureButton"]
        expectation(for: NSPredicate(format: "value MATCHES %@", ".*최근 [2-6][0-9] fps.*"), evaluatedWith: performance)
        waitForExpectations(timeout: 30)
        XCTAssertTrue(app.staticTexts["liveCaptureStatus"].label.contains("합성"))
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "native-waveform-cadence-synthetic"
        screen.lifetime = .keepAlways
        add(screen)
        app.buttons["detailsButton"].tap()
        XCTAssertTrue(app.staticTexts["waveformPerformance"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["captureButton"].label, "수음 중지")
        app.buttons["닫기"].tap()
        let left = app.descendants(matching: .any).matching(identifier: "leftWaveform").firstMatch
        expectation(for: NSPredicate(format: "value == %@", "수신 중"), evaluatedWith: left)
        expectation(for: NSPredicate(format: "value MATCHES %@", ".*최근 [2-6][0-9] fps.*"), evaluatedWith: performance)
        waitForExpectations(timeout: 30)
    }

    func testGuidedComparisonCollectsSixTrialsWithoutInventingDirection() {
        let app = launch(details: false)
        app.buttons["liveCaptureButton"].tap()
        awaitLivePCM(app)
        app.buttons["calibrationButton"].tap()
        for step in 1...6 {
            let start = app.buttons["calibrationStart"]
            reveal(start, in: app)
            XCTAssertTrue(app.staticTexts["calibrationStep"].label.contains("\(step)/6"))
            start.tap()
            XCTAssertTrue(app.buttons["calibrationCancel"].waitForExistence(timeout: 3))
            let label = step == 6 ? "6/6 · 비교 완료" : "\(step + 1)/6"
            expectation(for: NSPredicate(format: "label CONTAINS %@", label), evaluatedWith: app.staticTexts["calibrationStep"])
            waitForExpectations(timeout: 30)
        }
        let comparison = app.staticTexts["calibrationComparison"]
        reveal(comparison, in: app)
        // Instrumented simulator delivery can lose PCM coverage. Both outcomes
        // must remain inconclusive; deterministic core tests separately require
        // noClearSeparation when all six trials have sufficient coverage.
        let conclusion = comparison.label
        XCTAssertTrue(conclusion.contains("구분되지") || conclusion.contains("품질이 부족"), conclusion)
        XCTAssertFalse(conclusion.contains("자료가 확보"), conclusion)
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "native-direction-comparison-synthetic"
        screen.lifetime = .keepAlways
        add(screen)
        let export = app.buttons["calibrationExport"]
        reveal(export, in: app)
        export.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5) || app.otherElements["ActivityListView"].exists)
    }

    func testCalibrationCancellationAndBackgroundDoNotAdvanceStep() {
        let app = launch(details: false)
        app.buttons["liveCaptureButton"].tap()
        awaitLivePCM(app)
        app.buttons["calibrationButton"].tap()
        let start = app.buttons["calibrationStart"]
        reveal(start, in: app)
        start.tap()
        app.buttons["calibrationCancel"].tap()
        XCTAssertTrue(app.staticTexts["calibrationStep"].label.contains("1/6"))
        start.tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["calibrationStep"].label.contains("1/6"))
        XCTAssertFalse(start.isEnabled)
        XCTAssertFalse(app.buttons["calibrationCancel"].exists)
    }

    private func launch(_ extra: [String] = [], details: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--synthetic-stereo"] + extra
        app.launch()
        XCTAssertTrue(app.staticTexts["liveSyntheticBanner"].waitForExistence(timeout: 10))
        if details {
            app.buttons["detailsButton"].tap()
            XCTAssertTrue(app.staticTexts["syntheticBanner"].waitForExistence(timeout: 5))
        }
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, downward: Bool = false) {
        for _ in 0..<6 {
            if element.isHittable { return }
            if downward { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }

    func testStartMarkStopAndScreenshot() {
        let app = launch()
        let button = app.buttons["captureButton"]
        XCTAssertEqual(button.label, "스테레오 수음 시작")
        button.tap()
        XCTAssertTrue(app.staticTexts["lagValue"].waitForExistence(timeout: 5))
        let value = NSPredicate(format: "label CONTAINS %@", "+145.8")
        expectation(for: value, evaluatedWith: app.staticTexts["lagValue"])
        waitForExpectations(timeout: 30)
        XCTAssertEqual(app.staticTexts["actualChannels"].label, "실제 2채널")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "native-stereo-synthetic"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let tracked = app.staticTexts["trackedLagValue"]
        reveal(tracked, in: app)
        expectation(for: value, evaluatedWith: tracked)
        waitForExpectations(timeout: 30)
        XCTAssertTrue(app.staticTexts["motionStatus"].label.contains("회전"))
        let continuous = XCTAttachment(screenshot: app.screenshot())
        continuous.name = "native-continuous-synthetic"
        continuous.lifetime = .keepAlways
        add(continuous)
        reveal(app.buttons["왼쪽"], in: app)
        app.buttons["왼쪽"].tap()
        XCTAssertTrue(app.staticTexts["markCount"].label.contains("1/12"))
        reveal(button, in: app, downward: true)
        button.tap()
        XCTAssertEqual(button.label, "스테레오 수음 시작")
        XCTAssertTrue(app.staticTexts["captureStatus"].label.contains("해제"))
        XCTAssertEqual(tracked.label, "—")
    }

    func testCancelPendingPermissionDoesNotStartLater() {
        let app = launch(["--delayed-permission"])
        let button = app.buttons["captureButton"]
        button.tap()
        button.tap()
        // Give the delayed permission fixture time to arrive after cancellation.
        let noStart = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "수음 중지"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [noStart], timeout: 5), .timedOut)
        XCTAssertEqual(button.label, "스테레오 수음 시작")
        XCTAssertEqual(app.staticTexts["lagValue"].label, "—")
    }

    func testMonoInputRefusesAnalysis() {
        let app = launch(["--synthetic-mono"])
        app.buttons["captureButton"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "1채널"), evaluatedWith: app.staticTexts["captureStatus"])
        waitForExpectations(timeout: 30)
        XCTAssertEqual(app.buttons["captureButton"].label, "스테레오 수음 시작")
        XCTAssertEqual(app.staticTexts["lagValue"].label, "—")
    }

    func testBackgroundStopsCapture() {
        let app = launch()
        app.buttons["captureButton"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "+145.8"), evaluatedWith: app.staticTexts["lagValue"])
        waitForExpectations(timeout: 30)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(app.buttons["captureButton"].label, "스테레오 수음 시작")
        XCTAssertTrue(app.staticTexts["captureStatus"].label.contains("백그라운드"))
    }

    func testSharingStopsCapture() {
        let app = launch()
        app.buttons["captureButton"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "+145.8"), evaluatedWith: app.staticTexts["lagValue"])
        waitForExpectations(timeout: 30)
        reveal(app.buttons["exportButton"], in: app)
        app.buttons["exportButton"].tap()
        // Capture must stop before the native share sheet opens. Read the
        // underlying state while it is presented; app swipes target the modal,
        // not the capture scroll view, and cannot reveal the covered button.
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["captureButton"].label, "스테레오 수음 시작")
        XCTAssertTrue(app.staticTexts["captureStatus"].label.contains("공유하기 위해"))
        XCTAssertEqual(app.staticTexts["trackedLagValue"].label, "—")
    }

    func testDelayedSetupAndInterruptionEndKeepCapturing() {
        let app = launch(["--synthetic-route-events"])
        app.buttons["captureButton"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "오디오 알림 2"), evaluatedWith: app.staticTexts["audioEventCount"])
        waitForExpectations(timeout: 30)
        XCTAssertEqual(app.buttons["captureButton"].label, "수음 중지")
        XCTAssertTrue(app.staticTexts["lagValue"].label.contains("+145.8"))
    }

    func testRealInterruptionEventStillStopsCapture() {
        let app = launch(["--synthetic-interruption"])
        app.buttons["captureButton"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "interruptionBegan"), evaluatedWith: app.staticTexts["captureStatus"])
        waitForExpectations(timeout: 30)
        XCTAssertEqual(app.buttons["captureButton"].label, "스테레오 수음 시작")
        XCTAssertEqual(app.staticTexts["trackedLagValue"].label, "—")
    }

    func testStartupOutputOverrideKeepsCameraAndAcceptsFirstPCM() {
        let app = launch(["--synthetic-startup-override"], details: false)
        app.buttons["liveCaptureButton"].tap()
        awaitLivePCM(app)
        XCTAssertEqual(app.buttons["liveCaptureButton"].label, "계측 중지")
        XCTAssertTrue(app.staticTexts["cameraStatus"].label.contains("실제 카메라 영상 없음"))
        app.buttons["detailsButton"].tap()
        XCTAssertTrue(app.staticTexts["lastAudioEvent"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["lastAudioEvent"].label, "마지막 알림 4 · 입력 확인 정상 · 당시 분석 0")
        XCTAssertEqual(app.staticTexts["audioEventCount"].label, "오디오 알림 1 · 초기 재설정 0")
    }

    func testOutputOverrideWithChangedInputStillStopsCameraAndAudio() {
        let app = launch(["--synthetic-startup-override", "--synthetic-override-route-mismatch"], details: false)
        app.buttons["liveCaptureButton"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "routeOutputOverridden(4)"), evaluatedWith: app.staticTexts["liveCaptureStatus"])
        waitForExpectations(timeout: 30)
        XCTAssertEqual(app.buttons["liveCaptureButton"].label, "카메라·수음 시작")
        XCTAssertEqual(app.staticTexts["liveLagValue"].label, "—")
        XCTAssertTrue(app.staticTexts["cameraStatus"].label.contains("카메라를 중지"))
        app.buttons["detailsButton"].tap()
        XCTAssertTrue(app.staticTexts["lastAudioEvent"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["lastAudioEvent"].label, "마지막 알림 4 · 입력 확인 불일치 · 당시 분석 0")
    }

    func testFullscreenCameraControlsAndBackgroundRelease() {
        let app = launch(details: false)
        let button = app.buttons["liveCaptureButton"]
        let leftWaveform = app.descendants(matching: .any).matching(identifier: "leftWaveform").firstMatch
        let rightWaveform = app.descendants(matching: .any).matching(identifier: "rightWaveform").firstMatch
        XCTAssertTrue(button.isHittable)
        XCTAssertEqual(leftWaveform.value as? String, "입력 없음")
        XCTAssertEqual(rightWaveform.value as? String, "입력 없음")
        let preview = app.otherElements["cameraPreview"]
        XCTAssertTrue(preview.exists)
        XCTAssertGreaterThan(preview.frame.height, app.frame.height * 0.9)
        button.tap()
        awaitLivePCM(app)
        XCTAssertTrue(app.staticTexts["cameraStatus"].label.contains("실제 카메라 영상 없음"))
        // DSP can finish before the independent, deliberately delayed preview.
        // The first simulator launch can make AX queries take several seconds.
        // Observe each channel's fresh state separately, as in the silent-channel
        // test, without extending the application's 350 ms stale cutoff.
        expectation(for: NSPredicate(format: "value == %@", "수신 중"), evaluatedWith: leftWaveform)
        waitForExpectations(timeout: 30)
        expectation(for: NSPredicate(format: "value == %@", "수신 중"), evaluatedWith: rightWaveform)
        waitForExpectations(timeout: 30)
        XCTAssertTrue(leftWaveform.isHittable)
        XCTAssertTrue(rightWaveform.isHittable)
        XCTAssertTrue(app.frame.contains(leftWaveform.frame))
        XCTAssertTrue(app.frame.contains(rightWaveform.frame))
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "native-camera-overlay-synthetic"
        screen.lifetime = .keepAlways
        add(screen)
        button.tap()
        XCTAssertEqual(button.label, "카메라·수음 시작")
        XCTAssertEqual(app.staticTexts["liveLagValue"].label, "—")
        XCTAssertEqual(leftWaveform.value as? String, "입력 없음")
        XCTAssertEqual(rightWaveform.value as? String, "입력 없음")
        button.tap()
        awaitLivePCM(app)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(button.label, "카메라·수음 시작")
        XCTAssertEqual(app.staticTexts["liveLagValue"].label, "—")
        XCTAssertEqual(leftWaveform.value as? String, "입력 없음")
        XCTAssertEqual(rightWaveform.value as? String, "입력 없음")
    }

    func testWaveformsKeepSilentRightChannelFlat() {
        let app = launch(["--synthetic-silent-right"], details: false)
        app.buttons["liveCaptureButton"].tap()
        let left = app.descendants(matching: .any).matching(identifier: "leftWaveform").firstMatch, right = app.descendants(matching: .any).matching(identifier: "rightWaveform").firstMatch
        expectation(for: NSPredicate(format: "value == %@", "수신 중"), evaluatedWith: left)
        // A separate AX snapshot can stall the instrumented main loop beyond
        // the intentional 350ms stale cutoff. Wait for each fresh state instead
        // of assuming the later right-hand query shares the left snapshot.
        expectation(for: NSPredicate(format: "value == %@", "평탄"), evaluatedWith: right)
        waitForExpectations(timeout: 30)
        XCTAssertEqual(app.buttons["liveCaptureButton"].label, "계측 중지")
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "native-waveform-silent-right"
        screen.lifetime = .keepAlways
        add(screen)
        app.buttons["liveCaptureButton"].tap()
        XCTAssertEqual(left.value as? String, "입력 없음")
        XCTAssertEqual(right.value as? String, "입력 없음")
    }

    func testStaleWaveformsClearBeforeCaptureWatchdogStops() {
        let app = launch(["--synthetic-waveform-stale"], details: false)
        app.buttons["liveCaptureButton"].tap()
        let left = app.descendants(matching: .any).matching(identifier: "leftWaveform").firstMatch, right = app.descendants(matching: .any).matching(identifier: "rightWaveform").firstMatch
        expectation(for: NSPredicate(format: "value == %@", "수신 중"), evaluatedWith: left)
        waitForExpectations(timeout: 5)
        expectation(for: NSPredicate(format: "value == %@", "입력 없음"), evaluatedWith: left)
        waitForExpectations(timeout: 6)
        XCTAssertEqual(right.value as? String, "입력 없음")
        XCTAssertEqual(app.buttons["liveCaptureButton"].label, "계측 중지")
    }

    func testCameraDeniedDoesNotStartMicrophone() {
        let app = launch(["--synthetic-camera-denied"], details: false)
        app.buttons["liveCaptureButton"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "카메라 권한이 없습니다"), evaluatedWith: app.staticTexts["cameraStatus"])
        waitForExpectations(timeout: 30)
        XCTAssertEqual(app.buttons["liveCaptureButton"].label, "카메라·수음 시작")
        XCTAssertEqual(app.staticTexts["liveCaptureStatus"].label, "대기")
        XCTAssertTrue((app.buttons["liveCaptureButton"].value as? String ?? "").contains("자동 잠금 기본 설정"))
    }

    func testMicrophoneStartupFailureAlsoReleasesCamera() {
        let app = launch(["--synthetic-mono"], details: false)
        app.buttons["liveCaptureButton"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "1채널"), evaluatedWith: app.staticTexts["liveCaptureStatus"])
        waitForExpectations(timeout: 30)
        XCTAssertEqual(app.buttons["liveCaptureButton"].label, "카메라·수음 시작")
        XCTAssertTrue(app.staticTexts["cameraStatus"].label.contains("카메라를 중지"))
        XCTAssertTrue((app.buttons["liveCaptureButton"].value as? String ?? "").contains("자동 잠금 기본 설정"))
    }

    func testCancelCameraPermissionDoesNotStartLater() {
        let app = launch(["--delayed-camera-permission"], details: false)
        let button = app.buttons["liveCaptureButton"]
        button.tap()
        XCTAssertEqual(button.label, "계측 중지")
        button.tap()
        let restarted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "계측 중지"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [restarted], timeout: 4), .timedOut)
        XCTAssertEqual(app.staticTexts["liveLagValue"].label, "—")
    }
}
