import XCTest

final class CaptureUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--synthetic-stereo"] + extra
        app.launch()
        XCTAssertTrue(app.staticTexts["syntheticBanner"].waitForExistence(timeout: 10))
        return app
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
        app.swipeUp()
        app.buttons["왼쪽"].tap()
        XCTAssertTrue(app.staticTexts["markCount"].label.contains("1/12"))
        app.swipeDown()
        button.tap()
        XCTAssertEqual(button.label, "스테레오 수음 시작")
        XCTAssertTrue(app.staticTexts["captureStatus"].label.contains("해제"))
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
        app.swipeUp()
        app.buttons["exportButton"].tap()
        // The share sheet is native. Dismiss it by dragging, then verify stop.
        let sheet = app.otherElements["ActivityListView"]
        if sheet.waitForExistence(timeout: 5) { sheet.swipeDown() }
        else { app.swipeDown() }
        app.swipeDown()
        XCTAssertEqual(app.buttons["captureButton"].label, "스테레오 수음 시작")
    }
}
