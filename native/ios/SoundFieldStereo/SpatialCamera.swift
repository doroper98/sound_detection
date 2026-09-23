import ARKit
import SwiftUI
import StereoCore

/// ARKit owns the rear video input in spatial mode. AVCaptureSession is not run
/// concurrently; AR audio capture is disabled and AVAudioEngine owns the mic.
@MainActor
final class SpatialCameraController: NSObject, ARSessionDelegate {
    let session = ARSession()
    private(set) var running = false
    private(set) var latestPose: SpatialPose?
    private var history = SpatialPoseHistory()
    private var camera: ARCamera?
    private var lastPublished = 0.0
    private var acceptAfter = 0.0
    private var trackingState = "starting"
    var onState: ((String) -> Void)?
    var onInterrupted: (() -> Void)?

    override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = .main
    }
    func start() {
        history = SpatialPoseHistory(); latestPose=nil; camera=nil; lastPublished=0; trackingState="starting"
        lastIngestedTime = -Double.infinity
        let configuration=ARWorldTrackingConfiguration()
        configuration.providesAudioData=false
        configuration.worldAlignment = .gravity
        configuration.isLightEstimationEnabled=false
        // Prefer 30 fps video for thermal headroom; audio/display remain independent.
        if let format=ARWorldTrackingConfiguration.supportedVideoFormats.first(where: { $0.framesPerSecond==30 }) {
            configuration.videoFormat=format
        }
        running=true
        acceptAfter=ProcessInfo.processInfo.systemUptime
        session.run(configuration, options: [.resetTracking,.removeExistingAnchors])
    }
    func stop() {
        running=false; trackingState="stopped"; session.pause(); invalidate()
    }
    private func invalidate() { history=SpatialPoseHistory(); latestPose=nil; camera=nil }
    var calibrationPose: SpatialPose? {
        guard running, let pose=latestPose, ProcessInfo.processInfo.systemUptime-pose.time<0.2 else { return nil }
        return pose
    }
    func inspect(midpoint: Double, duration: Double, now: Double) -> PoseAlignmentInspection {
        // A delayed delegate task must not hide an already captured AR frame.
        // The frame's own timestamp is preserved and history still enforces all tolerances.
        if running, let frame=session.currentFrame { ingest(frame,publish: false) }
        return history.inspect(midpoint: midpoint,duration: duration,now: now,
            running: running,trackingState: trackingState)
    }
    func project(_ point: Vector3, size: CGSize) -> CGPoint? {
        guard size.width>0, size.height>0, let camera, let p=latestPose,
              ProcessInfo.processInfo.systemUptime-p.time<0.2, (point-p.origin).dot(p.forward)>0 else { return nil }
        let result=camera.projectPoint(SIMD3<Float>(Float(point.x),Float(point.y),Float(point.z)), orientation: .portrait, viewportSize: size)
        return result.x.isFinite && result.y.isFinite ? result : nil
    }
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Delegate queue is main; an actor hop avoids relying on SDK isolation annotations.
        Task { @MainActor [weak self] in
            self?.ingest(frame,publish: true)
        }
    }
    private var lastIngestedTime = -Double.infinity
    private func ingest(_ frame: ARFrame, publish: Bool) {
        guard running, frame.timestamp>=acceptAfter, frame.timestamp>=lastIngestedTime else { return }
        lastIngestedTime=frame.timestamp
        guard case .normal=frame.camera.trackingState else {
            trackingState=String(describing: frame.camera.trackingState)
            invalidate()
            if publish { onState?("추적 대기 · 밝고 무늬가 있는 주변을 천천히 비추세요.") }
            return
        }
        let transform=frame.camera.viewMatrix(for: .portrait).inverse
        func vector(_ v: SIMD4<Float>) -> Vector3 { .init(Double(v.x),Double(v.y),Double(v.z)) }
        let pose=SpatialPose(time: frame.timestamp,origin: vector(transform.columns.3),
            right: vector(transform.columns.0),up: vector(transform.columns.1),forward: vector(transform.columns.2) * -1)
        guard pose.valid else { trackingState="invalidPose"; invalidate(); return }
        trackingState="normal"; history.append(pose); latestPose=pose; camera=frame.camera
        if publish, frame.timestamp-lastPublished>0.1 {
            lastPublished=frame.timestamp; onState?("AR 이동 추적 중")
        }
    }
    func connectPreview(_ view: ARSCNView) {
        view.session=session
        session.delegate=self; session.delegateQueue = .main
    }
    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor [weak self] in self?.stop(); self?.onInterrupted?() }
    }
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in self?.stop(); self?.onInterrupted?() }
    }
    nonisolated func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool { false }
}

struct SpatialCameraPreview: UIViewRepresentable {
    let controller: SpatialCameraController
    func makeUIView(context: Context) -> ARSCNView {
        let view=ARSCNView(frame: .zero)
        controller.connectPreview(view)
        view.preferredFramesPerSecond=30
        view.automaticallyUpdatesLighting=false
        view.scene=SCNScene()
        view.isAccessibilityElement=true
        view.accessibilityIdentifier="cameraPreview"
        view.accessibilityLabel="소리 방향을 표시하는 전체 화면 AR 카메라"
        return view
    }
    func updateUIView(_ view: ARSCNView, context: Context) {}
    // Only the capture controller owns session start/stop. Rebuilding a SwiftUI
    // preview or presenting a guide must not silently pause the shared session.
}
