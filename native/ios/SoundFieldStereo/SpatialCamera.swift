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
    var onState: ((String) -> Void)?
    var onInterrupted: (() -> Void)?

    override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = .main
    }
    func start() {
        history = SpatialPoseHistory(); latestPose=nil; camera=nil; lastPublished=0
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
        running=false; session.pause(); invalidate()
    }
    private func invalidate() { history=SpatialPoseHistory(); latestPose=nil; camera=nil }
    func aligned(midpoint: Double, duration: Double) -> SpatialPose? {
        guard running, latestPose.map({ ProcessInfo.processInfo.systemUptime-$0.time<0.2 }) ?? false else { return nil }
        return history.aligned(midpoint: midpoint,duration: duration)
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
            guard let self, self.running, frame.timestamp >= self.acceptAfter else { return }
            guard case .normal = frame.camera.trackingState else {
                self.invalidate(); self.onState?("추적 대기 · 밝고 무늬가 있는 주변을 천천히 비추세요."); return
            }
            let transform=frame.camera.viewMatrix(for: .portrait).inverse
            func vector(_ v: SIMD4<Float>) -> Vector3 { .init(Double(v.x),Double(v.y),Double(v.z)) }
            let pose=SpatialPose(time: frame.timestamp,origin: vector(transform.columns.3),
                right: vector(transform.columns.0),up: vector(transform.columns.1),forward: vector(transform.columns.2) * -1)
            guard pose.valid else { self.invalidate(); return }
            self.history.append(pose); self.latestPose=pose; self.camera=frame.camera
            if frame.timestamp-self.lastPublished>0.1 {
                self.lastPublished=frame.timestamp; self.onState?("AR 이동 추적 중")
            }
        }
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
    let session: ARSession
    func makeUIView(context: Context) -> ARSCNView {
        let view=ARSCNView(frame: .zero)
        view.session=session
        view.preferredFramesPerSecond=30
        view.automaticallyUpdatesLighting=false
        view.scene=SCNScene()
        view.isAccessibilityElement=true
        view.accessibilityIdentifier="cameraPreview"
        view.accessibilityLabel="소리 방향을 표시하는 전체 화면 AR 카메라"
        return view
    }
    func updateUIView(_ view: ARSCNView, context: Context) {}
    static func dismantleUIView(_ view: ARSCNView, coordinator: ()) { view.session.pause() }
}
