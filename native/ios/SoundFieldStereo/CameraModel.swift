import AVFoundation
import ARKit
import SwiftUI

private struct CameraFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Video-only capture, serialized away from the UI. Never adds an audio input
/// or lets AVCaptureSession reconfigure the microphone's AVAudioSession.
private final class CameraController: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "soundfield.camera", qos: .userInitiated)
    private let lock = NSLock()
    private var revision = 0

    func nextRequest() -> Int {
        lock.lock(); defer { lock.unlock() }
        revision += 1
        return revision
    }

    private func isCurrent(_ request: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return request == revision
    }

    func start(position: AVCaptureDevice.Position, request: Int) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard isCurrent(request) else { continuation.resume(returning: false); return }
                do {
                    try configure(position: position)
                    guard isCurrent(request) else { continuation.resume(returning: false); return }
                    session.startRunning()
                    guard isCurrent(request) else {
                        session.stopRunning()
                        continuation.resume(returning: false); return
                    }
                    guard session.isRunning else { throw CameraFailure(message: "카메라를 시작하지 못했습니다. 다시 시도하세요.") }
                    continuation.resume(returning: true)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func configure(position: AVCaptureDevice.Position) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.automaticallyConfiguresApplicationAudioSession = false
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        session.inputs.forEach(session.removeInput)
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw CameraFailure(message: "선택한 방향의 카메라를 찾지 못했습니다.")
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraFailure(message: "카메라 입력을 연결하지 못했습니다.") }
        session.addInput(input)
        // AVCaptureVideoPreviewLayer is the only consumer; no recording/data output.
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }
}

@MainActor
final class CameraModel: ObservableObject {
    enum Phase { case idle, starting, running }
    @Published private(set) var phase: Phase = .idle {
        didSet { updateIdleTimer() }
    }
    @Published private(set) var status = "카메라와 마이크를 시작하면 실시간 화면이 표시됩니다."
    @Published private(set) var usesSpatialCamera = false
    @Published private(set) var trackingStatus = "AR 이동 추적 대기"
    let spatialCamera = SpatialCameraController()
    var onTrackingLost: (() -> Void)?
    var onInterrupted: (@MainActor () -> Void)?
    private let controller = CameraController()
    private var request = 0
    private var observers: [NSObjectProtocol] = []
    private var applicationActive = true
    private var previousIdleTimerSetting: Bool?
    var screenAwake: Bool { UIApplication.shared.isIdleTimerDisabled }
    var session: AVCaptureSession { controller.session }
    var isBusy: Bool { phase != .idle }

    var isSynthetic: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--synthetic-stereo")
        #else
        return false
        #endif
    }

    init() {
        spatialCamera.onState = { [weak self] text in
            guard let self else { return }
            if self.trackingStatus != text { self.trackingStatus = text }
            if self.spatialCamera.latestPose == nil { self.onTrackingLost?() }
        }
        spatialCamera.onInterrupted = { [weak self] in
            guard let self, self.isBusy else { return }
            self.stop(reason: "AR 카메라가 중단되었습니다. 다시 시작하세요.")
            self.onInterrupted?()
        }
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: controller.session, queue: nil) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isBusy else { return }
                    self.stop(reason: "카메라가 중단되었습니다. 다른 카메라 앱을 닫고 다시 시작하세요.")
                    self.onInterrupted?()
                }
            })
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func setApplicationActive(_ active: Bool) {
        applicationActive = active
        updateIdleTimer()
    }

    private func updateIdleTimer() {
        if phase == .running && applicationActive {
            if previousIdleTimerSetting == nil {
                previousIdleTimerSetting = UIApplication.shared.isIdleTimerDisabled
            }
            UIApplication.shared.isIdleTimerDisabled = true
        } else if let previous = previousIdleTimerSetting {
            UIApplication.shared.isIdleTimerDisabled = previous
            previousIdleTimerSetting = nil
        }
    }

    func start(front: Bool) async -> Bool {
        guard !isBusy else { return phase == .running }
        request = controller.nextRequest()
        let token = request
        phase = .starting
        status = "카메라 권한과 입력을 확인하고 있습니다."
        let allowed: Bool
        if isSynthetic {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            try? await Task.sleep(nanoseconds: args.contains("--delayed-camera-permission") ? 3_000_000_000 : 100_000_000)
            allowed = !args.contains("--synthetic-camera-denied")
            #else
            allowed = false
            #endif
        } else {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: allowed = true
            case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
            default: allowed = false
            }
        }
        guard request == token else { return false }
        guard allowed else {
            phase = .idle
            status = "카메라 권한이 없습니다. 아이폰 설정에서 SoundField Stereo의 카메라를 허용하세요."
            return false
        }
        do {
            let started: Bool
            if isSynthetic { started = true }
            else if !front && ARWorldTrackingConfiguration.isSupported {
                usesSpatialCamera = true
                spatialCamera.start()
                // Wait for video/tracking before touching the working audio route.
                for _ in 0..<100 {
                    if request != token || spatialCamera.latestPose != nil { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                guard request == token else { return false }
                guard spatialCamera.latestPose != nil else {
                    throw CameraFailure(message: "AR 카메라 추적을 시작하지 못했습니다. 밝은 곳에서 무늬가 있는 주변을 비추고 다시 시작하세요.")
                }
                started = true
            } else {
                usesSpatialCamera = false
                started = try await controller.start(position: front ? .front : .back, request: token)
            }
            guard request == token, started else { return false }
            phase = .running
            status = isSynthetic ? "합성 UI 검사 · 실제 카메라 영상 없음" : "실시간 카메라 · 촬영 파일 저장 안 함"
            return true
        } catch {
            guard request == token else { return false }
            stop(reason: error.localizedDescription)
            return false
        }
    }

    func stop(reason: String = "카메라를 중지했습니다.") {
        request = controller.nextRequest() // A late permission response cannot start capture.
        controller.stop()
        spatialCamera.stop()
        trackingStatus = "AR 이동 추적 중지"
        phase = .idle
        status = reason
    }
}
