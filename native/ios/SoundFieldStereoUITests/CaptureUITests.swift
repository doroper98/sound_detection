import XCTest

final class CaptureUITests: XCTestCase {
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
        waitForExpectations(timeout: 10)
        XCTAssertEqual(app.staticTexts["actualChannels"].label, "실제 2채널")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "native-stereo-synthetic"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let tracked = app.staticTexts["trackedLagValue"]
        reveal(tracked, in: app)
        expectation(for: value, evaluatedWith: tracked)
        waitForExpectations(timeout: 10)
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
        waitForExpectations(timeout: 10)
        XCTAssertEqual(app.buttons["captureButton"].label, "스테레오 수음 시작")
        XCTAssertEqual(app.staticTexts["lagValue"].label, "—")
    }

    func testBackgroundStopsCapture() {
        let app = launch()
        app.buttons["captureButton"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "+145.8"), evaluatedWith: app.staticTexts["lagValue"])
        waitForExpectations(timeout: 10)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(app.buttons["captureButton"].label, "스테레오 수음 시작")
        XCTAssertTrue(app.staticTexts["captureStatus"].label.contains("백그라운드"))
    }

    func testSharingStopsCapture() {
        let app = launch()
        app.buttons["captureButton"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "+145.8"), evaluatedWith: app.staticTexts["lagValue"])
        waitForExpectations(timeout: 10)
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
        waitForExpectations(timeout: 10)
        XCTAssertEqual(app.buttons["captureButton"].label, "수음 중지")
        XCTAssertTrue(app.staticTexts["lagValue"].label.contains("+145.8"))
    }

    func testRealInterruptionEventStillStopsCapture() {
        let app = launch(["--synthetic-interruption"])
        app.buttons["captureButton"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "interruptionBegan"), evaluatedWith: app.staticTexts["captureStatus"])
        waitForExpectations(timeout: 10)
        XCTAssertEqual(app.buttons["captureButton"].label, "스테레오 수음 시작")
        XCTAssertEqual(app.staticTexts["trackedLagValue"].label, "—")
    }

    func testFullscreenCameraControlsAndBackgroundRelease() {
        let app = launch(details: false)
        let button = app.buttons["liveCaptureButton"]
        XCTAssertTrue(button.isHittable)
        let preview = app.otherElements["cameraPreview"]
        XCTAssertTrue(preview.exists)
        XCTAssertGreaterThan(preview.frame.height, app.frame.height * 0.9)
        button.tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "+145.8"), evaluatedWith: app.staticTexts["liveLagValue"])
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.staticTexts["cameraStatus"].label.contains("실제 카메라 영상 없음"))
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "native-camera-overlay-synthetic"
        screen.lifetime = .keepAlways
        add(screen)
        button.tap()
        XCTAssertEqual(button.label, "카메라·수음 시작")
        XCTAssertEqual(app.staticTexts["liveLagValue"].label, "—")
        button.tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "+145.8"), evaluatedWith: app.staticTexts["liveLagValue"])
        waitForExpectations(timeout: 10)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(button.label, "카메라·수음 시작")
        XCTAssertEqual(app.staticTexts["liveLagValue"].label, "—")
    }

    func testCameraDeniedDoesNotStartMicrophone() {
        let app = launch(["--synthetic-camera-denied"], details: false)
        app.buttons["liveCaptureButton"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "카메라 권한이 없습니다"), evaluatedWith: app.staticTexts["cameraStatus"])
        waitForExpectations(timeout: 10)
        XCTAssertEqual(app.buttons["liveCaptureButton"].label, "카메라·수음 시작")
        XCTAssertEqual(app.staticTexts["liveCaptureStatus"].label, "대기")
    }

    func testMicrophoneStartupFailureAlsoReleasesCamera() {
        let app = launch(["--synthetic-mono"], details: false)
        app.buttons["liveCaptureButton"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "1채널"), evaluatedWith: app.staticTexts["liveCaptureStatus"])
        waitForExpectations(timeout: 10)
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
