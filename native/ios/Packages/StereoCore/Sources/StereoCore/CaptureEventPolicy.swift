import Foundation

public enum CaptureEvent: String, Codable, Sendable {
    case routeSetupChanged, routeOutputOverridden, routeDeviceChanged, routeUnavailable, routeUnknown
    case engineConfigurationChanged, interruptionBegan, interruptionEnded, interruptionUnknown
    case mediaServicesLost, mediaServicesReset
}

public enum CaptureEventDecision: String, Codable, Sendable {
    case continueCapture, restartStartupEngine, stop
}

public enum CaptureEventPolicy {
    /// A startup notification is never ignored on a timer alone. The selected
    /// built-in stereo route and the original PCM format must still match.
    public static func decide(_ event: CaptureEvent, routeMatches: Bool, engineRunning: Bool,
                              receivedPCM: Bool, elapsed: Double, restartCount: Int) -> CaptureEventDecision {
        switch event {
        case .interruptionEnded:
            return .continueCapture // No automatic resumption after a real interruption.
        case .routeSetupChanged, .routeOutputOverridden, .engineConfigurationChanged:
            guard routeMatches else { return .stop }
            if engineRunning { return .continueCapture }
            if !receivedPCM, elapsed.isFinite, (0...2).contains(elapsed), restartCount < 2 {
                return .restartStartupEngine
            }
            return .stop
        default:
            return .stop
        }
    }
}
