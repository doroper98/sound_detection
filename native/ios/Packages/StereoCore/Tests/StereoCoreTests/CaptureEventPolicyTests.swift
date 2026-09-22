import XCTest
@testable import StereoCore

final class CaptureEventPolicyTests: XCTestCase {
    func testDelayedOwnSetupNotificationDoesNotStopValidCapture() {
        for event in [CaptureEvent.routeSetupChanged, .engineConfigurationChanged] {
            XCTAssertEqual(CaptureEventPolicy.decide(event, routeMatches: true, engineRunning: true,
                receivedPCM: true, elapsed: 10, restartCount: 0), .continueCapture)
        }
    }

    func testInvalidRouteIsNeverHiddenByStartupGrace() {
        for event in [CaptureEvent.routeSetupChanged, .engineConfigurationChanged] {
            XCTAssertEqual(CaptureEventPolicy.decide(event, routeMatches: false, engineRunning: true,
                receivedPCM: false, elapsed: 0.01, restartCount: 0), .stop)
        }
    }

    func testStartupEngineCanRestartOnlyTwiceBeforeAnyPCM() {
        for count in 0...1 {
            XCTAssertEqual(CaptureEventPolicy.decide(.engineConfigurationChanged, routeMatches: true,
                engineRunning: false, receivedPCM: false, elapsed: 0.2, restartCount: count), .restartStartupEngine)
        }
        for (pcm, elapsed, count) in [(true, 0.2, 0), (false, 2.01, 0), (false, 0.2, 2), (false, -1.0, 0)] {
            XCTAssertEqual(CaptureEventPolicy.decide(.engineConfigurationChanged, routeMatches: true,
                engineRunning: false, receivedPCM: pcm, elapsed: elapsed, restartCount: count), .stop)
        }
    }

    func testExternalChangesAndRealInterruptionsStopEvenDuringStartup() {
        for event in [CaptureEvent.routeDeviceChanged, .routeUnavailable, .routeUnknown,
                      .interruptionBegan, .interruptionUnknown, .mediaServicesLost, .mediaServicesReset] {
            XCTAssertEqual(CaptureEventPolicy.decide(event, routeMatches: true, engineRunning: true,
                receivedPCM: false, elapsed: 0.01, restartCount: 0), .stop)
        }
    }

    func testInterruptionEndDoesNotRequestRestart() {
        XCTAssertEqual(CaptureEventPolicy.decide(.interruptionEnded, routeMatches: true, engineRunning: false,
            receivedPCM: false, elapsed: 0.1, restartCount: 0), .continueCapture)
    }
}
