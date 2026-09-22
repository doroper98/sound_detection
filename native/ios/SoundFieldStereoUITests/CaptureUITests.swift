import XCTest

final class CaptureUITests: XCTestCase {
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
        let performance = app.staticTexts["liveWaveformPerformance"]
        expectation(for: NSPredicate(format: "label MATCHES %@", ".*최근 [2-6][0-9] fps.*"), evaluatedWith: performance)
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
        expectation(for: NSPredicate(format: "label MATCHES %@", ".*최근 [2-6][0-9] fps.*"), evaluatedWith: performance)
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
        expectation(for: NSPredicate(format: "value == %@", "수신 중"), evaluatedWith: leftWaveform)
        expectation(for: NSPredicate(format: "value == %@", "수신 중"), evaluatedWith: rightWaveform)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(leftWaveform.value as? String, "수신 중")
        XCTAssertEqual(rightWaveform.value as? String, "수신 중")
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
        waitForExpectations(timeout: 30)
        XCTAssertEqual(right.value as? String, "평탄")
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
    }

    func testMicrophoneStartupFailureAlsoReleasesCamera() {
        let app = launch(["--synthetic-mono"], details: false)
        app.buttons["liveCaptureButton"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "1채널"), evaluatedWith: app.staticTexts["liveCaptureStatus"])
        waitForExpectations(timeout: 30)
        XCTAssertEqual(app.buttons["liveCaptureButton"].label, "카메라·수음 시작")
        XCTAssertTrue(app.staticTexts["cameraStatus"].label.contains("카메라를 중지"))
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
