import Foundation

public enum PoseAlignmentIssue: String, Codable, Sendable {
    case matched, invalidTiming, audioTooOld, audioInFuture, cameraStopped
    case trackingUnavailable, cameraStale, missingCameraFrames, poseTimeMismatch
    case movementDuringAudio, poseProviderUnavailable

    public var instruction: String {
        switch self {
        case .matched: return "소리와 카메라 자세가 연결됐습니다."
        case .movementDuringAudio: return "폰이 움직이는 중입니다. 잠시 멈추면 측정이 이어집니다."
        case .trackingUnavailable: return "카메라가 주변을 인식하지 못했습니다. 밝고 무늬가 있는 곳을 비춰 주세요."
        case .cameraStopped, .cameraStale, .missingCameraFrames:
            return "카메라 자세가 갱신되지 않습니다. 계속 이 상태면 계측을 중지하고 다시 시작하세요."
        case .poseTimeMismatch: return "소리와 카메라 시각을 연결하는 중입니다. 계속 이 상태면 진단 JSON을 공유해 주세요."
        default: return "측정값 연결에 문제가 있습니다. 계측을 중지하고 진단 JSON을 공유해 주세요."
        }
    }
    var canWaitForCamera: Bool {
        self == .cameraStale || self == .missingCameraFrames || self == .poseTimeMismatch
    }
}

/// Actual timestamps only; never substitutes the current pose for missing history.
public struct PoseAlignmentInspection: Codable, Sendable {
    public let issue: PoseAlignmentIssue
    public let pose: SpatialPose?
    public let audioAgeSeconds: Double?
    public let latestCameraAgeSeconds: Double?
    public let nearestCameraMinusAudioSeconds: Double?
    public let cameraFrameCount: Int
    public let trackingState: String
    public let waitingForCameraIssue: PoseAlignmentIssue?
    public var instruction: String { (waitingForCameraIssue ?? issue).instruction }
    public init(issue: PoseAlignmentIssue, pose: SpatialPose? = nil, audioAgeSeconds: Double? = nil,
                latestCameraAgeSeconds: Double? = nil, nearestCameraMinusAudioSeconds: Double? = nil,
                cameraFrameCount: Int = 0, trackingState: String = "unavailable",
                waitingForCameraIssue: PoseAlignmentIssue? = nil) {
        self.issue=issue; self.pose=pose
        self.audioAgeSeconds=audioAgeSeconds.flatMap { $0.isFinite ? $0 : nil }
        self.latestCameraAgeSeconds=latestCameraAgeSeconds.flatMap { $0.isFinite ? $0 : nil }
        self.nearestCameraMinusAudioSeconds=nearestCameraMinusAudioSeconds.flatMap { $0.isFinite ? $0 : nil }
        self.cameraFrameCount=cameraFrameCount; self.trackingState=trackingState
        self.waitingForCameraIssue=waitingForCameraIssue
    }
}

/// At most four feature summaries (no PCM). Late camera delivery gets a bounded
/// retry, while the original 60 ms pose tolerance and 300 ms freshness stay intact.
public struct SpatialAudioSample: Sendable {
    public let features: AcousticFeatures?
    public let spectrum: SoundSpectrum?
    public let midpoint: Double
    public let duration: Double
    public init(features: AcousticFeatures?, spectrum: SoundSpectrum? = nil, midpoint: Double, duration: Double) {
        self.features=features; self.spectrum=spectrum; self.midpoint=midpoint; self.duration=duration
    }
}

public struct SpatialAudioDelivery: Sendable {
    public let sample: SpatialAudioSample
    public let inspection: PoseAlignmentInspection
    public let waitedForCamera: Bool
}

public struct SpatialAudioSynchronizer {
    private struct Pending {
        let sample: SpatialAudioSample
        let receivedAt: Double
        var waited=false
        var waitingIssue: PoseAlignmentIssue?
    }
    private var pending: [Pending]=[]
    public private(set) var overflowCount=0
    public private(set) var latestInspection: PoseAlignmentInspection?
    public var pendingCount: Int { pending.count }
    public init() {}
    public mutating func append(_ sample: SpatialAudioSample, at now: Double) {
        pending.append(Pending(sample: sample,receivedAt: now))
        if pending.count>4 { pending.removeFirst(); overflowCount+=1 }
    }
    public mutating func drain(at now: Double,
        inspect: (Double, Double, Double) -> PoseAlignmentInspection) -> [SpatialAudioDelivery] {
        var delivered: [SpatialAudioDelivery]=[]
        while var first=pending.first {
            var result=inspect(first.sample.midpoint,first.sample.duration,now)
            // Independently enforce freshness even if a provider returns an old pose.
            let age=now-first.sample.midpoint
            if !now.isFinite || !first.sample.midpoint.isFinite {
                result = .init(issue: .invalidTiming)
            } else if age>=0.3 || age < -0.06 {
                result = .init(issue: age>=0.3 ? .audioTooOld : .audioInFuture,audioAgeSeconds: age,
                    latestCameraAgeSeconds: result.latestCameraAgeSeconds,
                    nearestCameraMinusAudioSeconds: result.nearestCameraMinusAudioSeconds,
                    cameraFrameCount: result.cameraFrameCount,trackingState: result.trackingState,
                    waitingForCameraIssue: first.waitingIssue)
            }
            latestInspection=result
            if result.issue.canWaitForCamera, now-first.receivedAt<0.18, age<0.3 {
                first.waited=true; first.waitingIssue=result.issue; pending[0]=first; break
            }
            pending.removeFirst()
            delivered.append(.init(sample: first.sample,inspection: result,waitedForCamera: first.waited))
        }
        return delivered
    }
    public mutating func clear() { pending=[] }
}
