import AVFoundation
import CoreMotion
import SwiftUI
import StereoCore

struct InputSourceInfo: Codable {
    let name: String
    let orientation: String?
    let supportedPolarPatterns: [String]
}

struct FrameReading: Codable {
    let sequence: Int
    let sampleTime: Int64?
    let hostTime: UInt64?
    let skippedBuffers: Int
    let analyzedTimelineGaps: Int
    let analysis: StereoAnalysis
    var acousticFeatures: AcousticFeatures? = nil
    var soundSpectrum: SoundSpectrum? = nil
}

struct MarkedReading: Codable, Identifiable {
    let id: UUID
    let declaredSoundSide: String
    let markedAt: Date
    let reading: FrameReading
}

struct AudioEventReading: Encodable {
    let time: Date
    let event: CaptureEvent
    let reasonCode: UInt?
    let decision: CaptureEventDecision
    let routeMatches: Bool
    let engineRunning: Bool
    let inputPort: String?
    let sessionChannels: Int
    let sampleRate: Double
    let analyzedFramesBeforeEvent: Int
    let routeInspection: AudioRouteInspection
}

/// Values read at the notification, before teardown; no device identifiers.
struct AudioRouteInspection: Encodable {
    let inputPort: String?
    let category: String
    let mode: String
    let sourceOrientation: String?
    let polarPattern: String?
    let inputOrientation: Int
    let sessionChannels: Int
    let sampleRate: Double
    let hardwareChannels: UInt32?
    let tapChannels: UInt32?
    let hardwareSampleRate: Double?
    let tapSampleRate: Double?
    let checks: [String: Bool]
    var matches: Bool { !checks.isEmpty && checks.values.allSatisfy { $0 } }
}

struct NativeReport: Encodable {
    let sessionID=UUID()
    var schemaVersion = 11
    var appVersion = "0.4.0-native-foa-stability-build11"
    var foa: FOAReport?
    var inputOrigin = "AVAudioEngine.inputNode"
    var operatingSystem = UIDevice.current.systemVersion
    var startedAt: Date?
    var stoppedAt: Date?
    var status = "대기"
    var requestedChannels = 2
    var requestedSampleRate = 48_000.0
    var requestedSource = "back"
    var requestedOrientation = "portrait"
    var availableSources: [InputSourceInfo] = []
    var sessionChannels: Int?
    var hardwareChannels: UInt32?
    var tapFormatChannels: UInt32?
    var actualSampleRate: Double?
    var selectedSource: String?
    var selectedPolarPattern: String?
    var actualOrientation: Int?
    var actualInputPort: String?
    var latest: FrameReading?
    var markedReadings: [MarkedReading] = []
    var analyzedFrames = 0
    var activeLeftFrames = 0
    var activeRightFrames = 0
    var duplicateFrames = 0
    var candidateLagFrames = 0
    var waveformDisplay: WaveformDisplayStatistics?
    var calibration: DirectionCalibrationReport?
    var spatial: SpatialReport?
    var trend: LagTrend?
    var motionStatus = "회전 측정 대기"
    var latestOrientation: AlignedOrientation?
    var audioEvents: [AudioEventReading] = []
    var startupEngineRestarts = 0
    var cameraSessionRunningAtAudioStart = false
    var startControl = "audioDetails"
    let attitudeReferenceFrame = "CoreMotion.xArbitraryZVertical; quaternion x,y,z,w"
    var positionTrackingEnabled = false
    let acousticCalibrationVerified = false
    let physicalMicrophonesVerified = false
    let hardwareSynchronizationVerified = false
    var localizationEnabled = false
    let lagConvention = "right-minus-left; positive means right arrives later"
    let note = "Experimental FOA band directions or legacy empirical stereo bearing; physical acoustic accuracy unverified. FOA camera-axis mapping is assumed, not validated, and no FOA range is inferred. Statistics and relative AR poses only. No PCM, audio files, camera images, saved world map, device IDs or ground-truth source coordinates."
}

@MainActor
private final class MotionRecorder {
    private let manager = CMMotionManager()
    private var timer: Timer?
    private var history = OrientationHistory()

    func start() -> Bool {
        stop()
        history = OrientationHistory()
        guard manager.isDeviceMotionAvailable,
              CMMotionManager.availableAttitudeReferenceFrames().contains(.xArbitraryZVertical) else { return false }
        manager.deviceMotionUpdateInterval = 1 / 50
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
        let poller = Timer(timeInterval: 1 / 50, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
        timer = poller
        RunLoop.main.add(poller, forMode: .common)
        return true
    }

    private func poll() {
        guard let motion = manager.deviceMotion else { return }
        let q = motion.attitude.quaternion
        if let sample = OrientationSample(timestampSeconds: motion.timestamp, quaternion: [q.x, q.y, q.z, q.w]) {
            history.append(sample)
        }
    }

    func aligned(at hostSeconds: Double) -> AlignedOrientation? {
        poll()
        return history.aligned(at: hostSeconds)
    }

    func stop() {
        timer?.invalidate(); timer = nil
        manager.stopDeviceMotionUpdates()
    }
}

enum CaptureFailure: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

private final class NotificationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int?
    func set(_ token: Int?) { lock.lock(); value = token; lock.unlock() }
    func read() -> Int? { lock.lock(); defer { lock.unlock() }; return value }
}

/// Independent bounded preview and analysis deliveries. Slow DSP cannot hold
/// the preview gate, and the display link never drives analysis or audio I/O.
private final class TapPipeline: @unchecked Sendable {
    private let gate = DispatchSemaphore(value: 1)
    private let previewGate = DispatchSemaphore(value: 1)
    private let queue = DispatchQueue(label: "soundfield.stereo.analysis", qos: .userInitiated)
    private let previewQueue = DispatchQueue(label: "soundfield.stereo.preview", qos: .userInteractive)
    private let lock = NSLock()
    private var skipped = 0
    private var sequence = 0
    private var gaps = 0
    private var nextSampleTime: Int64?
    private let deliver: @MainActor (Result<FrameReading, Error>) -> Void
    private let deliverPreview: @MainActor ([TimedWaveform], Double) -> Void

    init(deliverPreview: @escaping @MainActor ([TimedWaveform], Double) -> Void,
         deliver: @escaping @MainActor (Result<FrameReading, Error>) -> Void) {
        self.deliver = deliver
        self.deliverPreview = deliverPreview
    }

    func submit(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        guard buffer.format.channelCount == 2,
              buffer.format.commonFormat == .pcmFormatFloat32,
              let pointers = buffer.floatChannelData,
              (128...16_384).contains(Int(buffer.frameLength)) else {
            if gate.wait(timeout: .now()) == .success {
                finish(.failure(CaptureFailure.message("실제 PCM이 분석 가능한 2채널 Float32 형식이 아닙니다. 수음을 중지했습니다.")))
            }
            return
        }
        let analysisReady = gate.wait(timeout: .now()) == .success
        let previewReady = previewGate.wait(timeout: .now()) == .success
        if !analysisReady { lock.lock(); skipped += 1; lock.unlock() }
        guard analysisReady || previewReady else { return }
        let count = Int(buffer.frameLength), stride = buffer.stride
        let left = (0..<count).map { pointers[0][$0 * stride] }
        let right = buffer.format.isInterleaved
            ? (0..<count).map { pointers[0][$0 * stride + 1] }
            : (0..<count).map { pointers[1][$0 * stride] }
        process(left: left, right: right, sampleRate: buffer.format.sampleRate,
            sampleTime: time.isSampleTimeValid ? time.sampleTime : nil,
            hostTime: time.isHostTimeValid ? time.hostTime : nil,
            analysisReady: analysisReady, previewReady: previewReady)
    }

    func submitExternal(left: [Float], right: [Float], rate: Double, start: Double) {
        let analysisReady=gate.wait(timeout: .now()) == .success
        let previewReady=previewGate.wait(timeout: .now()) == .success
        if !analysisReady { lock.lock(); skipped+=1; lock.unlock() }
        process(left: left,right: right,sampleRate: rate,sampleTime: nil,
            hostTime: AVAudioTime.hostTime(forSeconds: start),analysisReady: analysisReady,previewReady: previewReady)
    }

    #if DEBUG
    func submitSynthetic(left: [Float], right: [Float], sampleTime: Int64, bufferStart: Double) {
        let analysisReady = gate.wait(timeout: .now()) == .success
        let previewReady = previewGate.wait(timeout: .now()) == .success
        process(left: left, right: right, sampleRate: 48_000, sampleTime: sampleTime,
            hostTime: AVAudioTime.hostTime(forSeconds: bufferStart),
            analysisReady: analysisReady, previewReady: previewReady)
    }
    #endif

    private func process(left: [Float], right: [Float], sampleRate: Double, sampleTime: Int64?,
                         hostTime: UInt64?, analysisReady: Bool, previewReady: Bool) {
        if previewReady {
            let duration = Double(left.count) / sampleRate
            let start = hostTime.map { AVAudioTime.seconds(forHostTime: $0) }
                ?? ProcessInfo.processInfo.systemUptime - duration
            previewQueue.async { [self] in
                let frames = WaveformBatch.make(left: left, right: right, sampleRate: sampleRate, startTimeSeconds: start)
                Task { @MainActor [self] in
                    deliverPreview(frames, duration)
                    previewGate.signal()
                }
            }
        }
        guard analysisReady else { return }
        queue.async { [self] in
            do {
                let analysis = try StereoAnalyzer.analyze(left: left, right: right, sampleRate: sampleRate)
                sequence += 1
                if let expected = nextSampleTime, let actual = sampleTime, expected != actual { gaps += 1 }
                nextSampleTime = sampleTime.map { $0 + Int64(left.count) }
                lock.lock(); let skippedCount = skipped; lock.unlock()
                finish(.success(FrameReading(sequence: sequence, sampleTime: sampleTime, hostTime: hostTime,
                    skippedBuffers: skippedCount, analyzedTimelineGaps: gaps, analysis: analysis,
                    acousticFeatures: AcousticFeatures.measure(left: left,right: right,analysis: analysis),
                    soundSpectrum: SoundSpectrumAnalyzer.measure(left: left,right: right,sampleRate: sampleRate))))
            } catch { finish(.failure(error)) }
        }
    }

    private func finish(_ result: Result<FrameReading, Error>) {
        Task { @MainActor [self] in deliver(result); gate.signal() }
    }
}

@MainActor
final class WaveformDisplayModel: NSObject, ObservableObject {
    @Published private(set) var preview: StereoWaveformPreview?
    private var playback = WaveformPlayback()
    private var displayLink: CADisplayLink?
    private var displayedTime: Double?
    private var active = false
    private var visible = true
    private var lastVisibleStatistics: WaveformDisplayStatistics?

    func start() {
        stop(); playback = WaveformPlayback()
        active = true; lastVisibleStatistics = nil
        if visible { startDisplayLink() }
    }

    private func startDisplayLink() {
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func receive(_ frames: [TimedWaveform], duration: Double) {
        guard visible else { return }
        playback.append(frames, bufferDuration: duration)
    }

    @objc private func tick() {
        let frame = playback.frame(at: ProcessInfo.processInfo.systemUptime)
        if frame?.endTimeSeconds != displayedTime {
            displayedTime = frame?.endTimeSeconds
            preview = frame?.preview
        }
    }

    var statistics: WaveformDisplayStatistics {
        if !visible, let lastVisibleStatistics { return lastVisibleStatistics }
        return playback.statistics(at: ProcessInfo.processInfo.systemUptime)
    }

    func setVisible(_ value: Bool) {
        guard value != visible else { return }
        if !value { lastVisibleStatistics = statistics }
        visible = value
        displayLink?.invalidate(); displayLink = nil
        playback.clear(); displayedTime = nil; preview = nil
        if visible && active { startDisplayLink() }
    }

    func stop() {
        active = false
        displayLink?.invalidate(); displayLink = nil
        playback.clear(); displayedTime = nil; preview = nil
    }
}

@MainActor
final class CaptureModel: ObservableObject {
    enum Phase { case idle, requestingPermission, running }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var report = NativeReport()
    let waveformDisplay = WaveformDisplayModel()
    let spatial = SpatialModel()
    let foa = FOADirectionModel()
    @Published private(set) var usesFOA=false
    @Published private(set) var savedReports=[SavedNativeReport]()
    private var foaCapture: FOACapture?
    private var calibration = DirectionCalibration()
    @Published var source = "back"
    @Published var exportError: String?
    var onStopped: (@MainActor () -> Void)?
    private var engine: AVAudioEngine?
    private var pipeline: TapPipeline?
    private var tapInstalled = false
    private var ownsSession = false
    private var generation = 0
    private var observers: [NSObjectProtocol] = []
    private let notificationGate = NotificationGate()
    private var watchdog: Timer?
    private var syntheticTimer: Timer?
    private var trackingTimer: Timer?
    private var tracker = ContinuousLagTracker()
    private var timeOrigin: Double?
    private let motion = MotionRecorder()
    private var syntheticOrientation = OrientationHistory()
    private var lastFrameAt = Date()
    private var exportURL: URL?
    private var captureStartedUptime = 0.0
    private var configuredSampleRate: Double?
    #if DEBUG
    private var syntheticPCMEnabled = true
    #endif

    var isBusy: Bool { phase != .idle }
    var prefersFOA: Bool {
        source=="back" && (!isSynthetic || ProcessInfo.processInfo.arguments.contains("--synthetic-foa"))
    }
    var isSynthetic: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--synthetic-stereo")
        #else
        return false
        #endif
    }

    init() {
        if let data=UserDefaults.standard.data(forKey: "soundfield.savedReports"),
           let saved=try? JSONDecoder().decode([SavedNativeReport].self,from: data) { savedReports=Array(saved.prefix(5)) }
        let gate = notificationGate
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVAudioSession.mediaServicesWereLostNotification, AVAudioSession.mediaServicesWereResetNotification,
                     Notification.Name.AVAudioEngineConfigurationChange] {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] notification in
                guard let epoch = gate.read() else { return }
                let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
                let interruption = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
                let origin = (notification.object as? AVAudioEngine).map(ObjectIdentifier.init)
                Task { @MainActor [weak self] in
                    guard let self, self.generation == epoch, self.phase == .running else { return }
                    if name == .AVAudioEngineConfigurationChange,
                       origin != self.engine.map(ObjectIdentifier.init) { return }
                    self.handleAudioEvent(name: name, reason: reason, interruption: interruption)
                }
            }
            observers.append(token)
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        watchdog?.invalidate()
        syntheticTimer?.invalidate()
        trackingTimer?.invalidate()
    }

    func start(cameraPreviewActive: Bool = false, startControl: String = "audioDetails") {
        guard !isBusy else { return }
        archiveReport()
        generation += 1
        let token = generation
        report = NativeReport()
        usesFOA=prefersFOA && startControl=="cameraAndAudio"
        if usesFOA {
            foa.start(); report.foa=foa.report
            report.inputOrigin="AVCaptureAudioDataOutput.FOA+Stereo"
            report.requestedChannels=4
        }
        waveformDisplay.stop()
        calibration = DirectionCalibration()
        spatial.start()
        report.cameraSessionRunningAtAudioStart = cameraPreviewActive
        report.startControl = startControl
        configuredSampleRate = nil
        tracker = ContinuousLagTracker()
        timeOrigin = nil
        syntheticOrientation = OrientationHistory()
        report.requestedSource = source
        if usesFOA { report.requestedSource="systemBuiltInFOA"; report.requestedOrientation="portraitCamera; FOA system orientation unverified" }
        report.status = "마이크 권한을 확인하고 있습니다."
        phase = .requestingPermission
        Task { [weak self] in
            guard let self else { return }
            let allowed: Bool
            if isSynthetic {
                // An explicitly labelled DEBUG-only fixture; never a device result.
                let delay: UInt64 = ProcessInfo.processInfo.arguments.contains("--delayed-permission") ? 4_000_000_000 : 200_000_000
                try? await Task.sleep(nanoseconds: delay)
                allowed = true
            } else {
                allowed = await AVAudioApplication.requestRecordPermission()
            }
            guard token == generation, phase == .requestingPermission else { return }
            guard allowed else {
                stop(reason: "마이크 권한이 없습니다. 아이폰 설정에서 SoundField Stereo의 마이크를 허용하세요.")
                return
            }
            do {
                let processor = TapPipeline(deliverPreview: { [weak self] frames, duration in
                    guard let self, self.generation == token, self.phase == .running else { return }
                    self.waveformDisplay.receive(frames, duration: duration)
                }) { [weak self] result in
                    guard let self, self.generation == token, self.phase == .running else { return }
                    switch result {
                    case .success(let reading): self.accept(reading)
                    case .failure(let error): self.stop(reason: error.localizedDescription)
                    }
                }
                pipeline = processor
                report.motionStatus = isSynthetic ? "합성 회전 데이터" : (motion.start() ? "회전 센서 대기" : "회전 센서 미지원 · 수음은 계속")
                if isSynthetic {
                    #if DEBUG
                    try startSynthetic(processor)
                    #endif
                } else {
                    if usesFOA {
                        let capture=FOACapture(stereo: { left,right,rate,start in
                            processor.submitExternal(left: left,right: right,rate: rate,start: start)
                        },deliver: { [weak self] analysis,midpoint,duration,diagnostics in
                            guard let self, self.generation==token, self.phase == .running else { return }
                            self.lastFOAFrameAt=Date()
                            self.foa.receive(analysis,midpoint: midpoint,duration: duration,capture: diagnostics)
                            self.report.foa=self.foa.report
                            self.report.actualInputPort=diagnostics.inputPort
                            self.report.tapFormatChannels=diagnostics.foaFormat?.channels
                            self.report.actualSampleRate=diagnostics.foaFormat?.sampleRate
                        },failure: { [weak self] message,diagnostics in
                            guard let self, self.generation==token else { return }
                            self.foa.failure(message,capture: diagnostics); self.report.foa=self.foa.report
                            self.stop(reason: message)
                        })
                        foaCapture=capture
                        try await capture.start()
                        guard token==generation, phase == .requestingPermission else { capture.stop(); return }
                    } else { try startHardware(processor) }
                }
                phase = .running
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--synthetic-bearing") { spatial.prepareSyntheticCalibration() }
                if isSynthetic && ProcessInfo.processInfo.arguments.contains("--synthetic-pose-delay") {
                    spatial.prepareSyntheticSynchronization(stalled: false)
                }
                if isSynthetic && ProcessInfo.processInfo.arguments.contains("--synthetic-pose-stalled") {
                    spatial.prepareSyntheticSynchronization(stalled: true)
                }
                #endif
                waveformDisplay.start()
                captureStartedUptime = ProcessInfo.processInfo.systemUptime
                notificationGate.set(token)
                report.startedAt = Date()
                report.status = isSynthetic ? "합성 테스트 입력 · 실기기 결과 아님" :
                    (usesFOA ? "공간 오디오 수음 중 · 6단계 보정 없이 방향 후보를 계산합니다." : "스테레오 수음 중 · 세로 방향을 유지하세요.")
                lastFrameAt = Date()
                lastFOAFrameAt=Date()
                let trendTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.refreshTrend() }
                }
                trackingTimer = trendTimer
                RunLoop.main.add(trendTimer, forMode: .common)
                watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.phase == .running else { return }
                        if self.usesFOA && Date().timeIntervalSince(self.lastFOAFrameAt)>5 {
                            self.foa.failure("5초 동안 4채널 공간 오디오가 도착하지 않았습니다.")
                            self.stop(reason: "4채널 입력 대기 시간 초과 · 진단 기록을 확인해 주세요.")
                        } else if Date().timeIntervalSince(self.lastFrameAt)>5 {
                            self.stop(reason: "5초 동안 스테레오 PCM이 들어오지 않아 수음을 중지했습니다.")
                        }
                    }
                }
                #if DEBUG
                scheduleSyntheticNotifications(token: token)
                #endif
            } catch { if token==generation { stop(reason: error.localizedDescription) } }
        }
    }
    private var lastFOAFrameAt=Date()

    private func startHardware(_ processor: TapPipeline) throws {
        let session = AVAudioSession.sharedInstance()
        // measurement mode can select the primary mono microphone. Use the
        // documented stereo configuration; do not claim unprocessed raw PCM.
        try session.setCategory(.record, mode: .default, options: [])
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true)
        ownsSession = true
        // Preserve actual session metadata even when a preferred route request
        // is rejected before the engine is created.
        defer {
            let port = session.currentRoute.inputs.first
            report.sessionChannels = session.inputNumberOfChannels
            report.actualInputPort = port?.portType.rawValue
            report.selectedSource = port?.selectedDataSource?.dataSourceName
            report.selectedPolarPattern = port?.selectedDataSource?.selectedPolarPattern?.rawValue
            report.actualOrientation = session.inputOrientation.rawValue
        }
        guard let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else {
            throw CaptureFailure.message("내장 마이크를 찾지 못했습니다. 외부 오디오 장치를 분리하고 다시 시도하세요.")
        }
        report.availableSources = (builtIn.dataSources ?? []).map {
            InputSourceInfo(name: $0.dataSourceName, orientation: $0.orientation?.rawValue,
                            supportedPolarPatterns: ($0.supportedPolarPatterns ?? []).map(\.rawValue))
        }
        let desired: AVAudioSession.Orientation = source == "back" ? .back : .front
        guard let dataSource = builtIn.dataSources?.first(where: {
            $0.orientation == desired && ($0.supportedPolarPatterns ?? []).contains(.stereo)
        }) else {
            throw CaptureFailure.message("선택한 방향에서 내장 스테레오 입력을 지원하지 않습니다. 다른 방향을 선택해 다시 검사하세요.")
        }
        try session.setPreferredInput(builtIn)
        try dataSource.setPreferredPolarPattern(.stereo)
        try builtIn.setPreferredDataSource(dataSource)
        try session.setPreferredInputOrientation(.portrait)
        try session.setPreferredInputNumberOfChannels(2)

        let audioEngine = AVAudioEngine()
        engine = audioEngine
        let input = audioEngine.inputNode
        let hardware = input.inputFormat(forBus: 0)
        let actual = input.outputFormat(forBus: 0)
        recordRoute(session: session, hardware: hardware, tap: actual)
        guard session.inputNumberOfChannels == 2, hardware.channelCount == 2, actual.channelCount == 2,
              actual.sampleRate > 0, hardware.sampleRate > 0,
              session.currentRoute.inputs.first?.portType == .builtInMic,
              session.currentRoute.inputs.first?.selectedDataSource?.selectedPolarPattern == .stereo,
              session.currentRoute.inputs.first?.selectedDataSource?.orientation == desired,
              session.inputOrientation == .portrait else {
            throw CaptureFailure.message("요청한 스테레오 경로가 실제 입력에 적용되지 않았습니다. 보고서의 실제 채널 수와 선택 패턴을 확인하세요.")
        }
        configuredSampleRate = actual.sampleRate
        // nil keeps the input node's actual format. No mono-to-stereo converter,
        // channel duplicator, mixer, or speaker output is installed.
        input.installTap(onBus: 0, bufferSize: 2048, format: nil) { @Sendable buffer, time in
            processor.submit(buffer, at: time)
        }
        tapInstalled = true
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func inspectRoute() -> AudioRouteInspection {
        let session = AVAudioSession.sharedInstance()
        let port = session.currentRoute.inputs.first
        let input = engine?.inputNode
        let hardware = input?.inputFormat(forBus: 0), tap = input?.outputFormat(forBus: 0)
        let desired: AVAudioSession.Orientation = source == "back" ? .back : .front
        let inputPort = isSynthetic ? AVAudioSession.Port.builtInMic.rawValue : port?.portType.rawValue
        let category = isSynthetic ? AVAudioSession.Category.record.rawValue : session.category.rawValue
        let mode = isSynthetic ? AVAudioSession.Mode.default.rawValue : session.mode.rawValue
        let orientation = isSynthetic ? desired.rawValue : port?.selectedDataSource?.orientation?.rawValue
        let pattern = isSynthetic ? AVAudioSession.PolarPattern.stereo.rawValue : port?.selectedDataSource?.selectedPolarPattern?.rawValue
        let inputOrientation = isSynthetic ? AVAudioSession.StereoOrientation.portrait.rawValue : session.inputOrientation.rawValue
        var sessionChannels = isSynthetic ? 2 : session.inputNumberOfChannels
        let rate = isSynthetic ? 48_000 : session.sampleRate
        let hardwareChannels: UInt32? = isSynthetic ? 2 : hardware?.channelCount
        let tapChannels: UInt32? = isSynthetic ? 2 : tap?.channelCount
        let hardwareRate: Double? = isSynthetic ? 48_000 : hardware?.sampleRate
        let tapRate: Double? = isSynthetic ? 48_000 : tap?.sampleRate
        let expectedRate: Double? = isSynthetic ? 48_000 : configuredSampleRate
        #if DEBUG
        if isSynthetic && ProcessInfo.processInfo.arguments.contains("--synthetic-override-route-mismatch") {
            sessionChannels = 1
        }
        #endif
        let checks: [String: Bool] = [
            "engineAvailable": isSynthetic || engine != nil,
            "categoryRecord": category == AVAudioSession.Category.record.rawValue,
            "modeDefault": mode == AVAudioSession.Mode.default.rawValue,
            "builtInMic": inputPort == AVAudioSession.Port.builtInMic.rawValue,
            "stereoPattern": pattern == AVAudioSession.PolarPattern.stereo.rawValue,
            "requestedSource": orientation == desired.rawValue,
            "portraitOrientation": inputOrientation == AVAudioSession.StereoOrientation.portrait.rawValue,
            "sessionStereo": sessionChannels == 2,
            "hardwareStereo": hardwareChannels == 2,
            "tapStereo": tapChannels == 2,
            "tapFloat32": isSynthetic || tap?.commonFormat == .pcmFormatFloat32,
            "sampleRateConfigured": (expectedRate ?? 0) > 0,
            "sessionSampleRateUnchanged": expectedRate != nil && rate == expectedRate,
            "hardwareSampleRateUnchanged": expectedRate != nil && hardwareRate == expectedRate,
            "tapSampleRateUnchanged": expectedRate != nil && tapRate == expectedRate
        ]
        return AudioRouteInspection(inputPort: inputPort, category: category, mode: mode,
            sourceOrientation: orientation, polarPattern: pattern, inputOrientation: inputOrientation,
            sessionChannels: sessionChannels, sampleRate: rate, hardwareChannels: hardwareChannels,
            tapChannels: tapChannels, hardwareSampleRate: hardwareRate, tapSampleRate: tapRate, checks: checks)
    }

    private func handleAudioEvent(name: Notification.Name, reason: UInt?, interruption: UInt?) {
        if usesFOA {
            foa.noteEvent("\(name.rawValue):\(reason ?? interruption ?? 0)")
            let fatal=name==AVAudioSession.mediaServicesWereLostNotification || name==AVAudioSession.mediaServicesWereResetNotification
                || (name==AVAudioSession.interruptionNotification && interruption != AVAudioSession.InterruptionType.ended.rawValue)
            if fatal {
                foa.failure("오디오 서비스 또는 다른 앱이 공간 오디오를 중단했습니다.")
                stop(reason: "공간 오디오 중단 · 진단 JSON에 알림을 기록했습니다.")
            }
            return
        }
        let event: CaptureEvent
        switch name {
        case AVAudioSession.routeChangeNotification:
            switch reason.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:)) {
            case .categoryChange, .routeConfigurationChange: event = .routeSetupChanged
            case .override: event = .routeOutputOverridden
            case .newDeviceAvailable, .oldDeviceUnavailable: event = .routeDeviceChanged
            case .noSuitableRouteForCategory: event = .routeUnavailable
            default: event = .routeUnknown
            }
        case AVAudioSession.interruptionNotification:
            switch interruption.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) {
            case .began: event = .interruptionBegan
            case .ended: event = .interruptionEnded
            default: event = .interruptionUnknown
            }
        case AVAudioSession.mediaServicesWereLostNotification: event = .mediaServicesLost
        case AVAudioSession.mediaServicesWereResetNotification: event = .mediaServicesReset
        default: event = .engineConfigurationChanged
        }
        // Always inspect, including unknown/fatal notifications. Build 2's
        // short-circuit wrote false for reason 4 without examining the input.
        let inspection = inspectRoute()
        let matches = inspection.matches
        let running = isSynthetic || engine?.isRunning == true
        let decision = CaptureEventPolicy.decide(event, routeMatches: matches, engineRunning: running,
            receivedPCM: report.analyzedFrames > 0, elapsed: ProcessInfo.processInfo.systemUptime - captureStartedUptime,
            restartCount: report.startupEngineRestarts)
        report.audioEvents.append(AudioEventReading(time: Date(), event: event, reasonCode: reason ?? interruption,
            decision: decision, routeMatches: matches, engineRunning: running,
            inputPort: inspection.inputPort, sessionChannels: inspection.sessionChannels,
            sampleRate: inspection.sampleRate, analyzedFramesBeforeEvent: report.analyzedFrames,
            routeInspection: inspection))
        if report.audioEvents.count > 32 { report.audioEvents.removeFirst() }
        #if DEBUG
        if isSynthetic && event == .routeOutputOverridden { syntheticPCMEnabled = true }
        #endif
        switch decision {
        case .continueCapture: break
        case .restartStartupEngine:
            do { try restartStartupEngine() }
            catch { stop(reason: "초기 오디오 엔진 재설정 실패: \(error.localizedDescription)") }
        case .stop:
            let cause: String
            switch event {
            case .interruptionBegan, .interruptionUnknown: cause = "다른 오디오 작업이 수음을 중단했습니다."
            case .mediaServicesLost, .mediaServicesReset: cause = "iOS 오디오 서비스가 재시작되었습니다."
            case .routeDeviceChanged: cause = "오디오 장치 연결 상태가 바뀌었습니다."
            default: cause = "선택한 스테레오 입력 또는 오디오 엔진 상태가 바뀌었습니다."
            }
            stop(reason: "\(cause) 수음 중지 · \(event.rawValue)(\(reason.map(String.init) ?? "—")). 진단 JSON에 원인을 기록했습니다.")
        }
    }

    private func restartStartupEngine() throws {
        guard let engine, let pipeline, inspectRoute().matches else {
            throw CaptureFailure.message("요청한 내장 스테레오 입력을 확인할 수 없습니다.")
        }
        report.startupEngineRestarts += 1
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
        tapInstalled = false
        engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: nil) { @Sendable buffer, time in
            pipeline.submit(buffer, at: time)
        }
        tapInstalled = true
        engine.prepare()
        try engine.start()
    }

    private func recordRoute(session: AVAudioSession, hardware: AVAudioFormat, tap: AVAudioFormat) {
        let port = session.currentRoute.inputs.first
        report.sessionChannels = session.inputNumberOfChannels
        report.hardwareChannels = hardware.channelCount
        report.tapFormatChannels = tap.channelCount
        report.actualSampleRate = tap.sampleRate
        report.selectedSource = port?.selectedDataSource?.dataSourceName
        report.selectedPolarPattern = port?.selectedDataSource?.selectedPolarPattern?.rawValue
        report.actualOrientation = session.inputOrientation.rawValue
        report.actualInputPort = port?.portType.rawValue
    }

    private func accept(_ reading: FrameReading) {
        var updated = report
        defer { report = updated } // One observable update per analysis/timer tick.
        lastFrameAt = Date()
        updated.latest = reading
        updated.analyzedFrames += 1
        if reading.analysis.channels[0].active { updated.activeLeftFrames += 1 }
        if reading.analysis.channels[1].active { updated.activeRightFrames += 1 }
        if reading.analysis.duplicateSuspected { updated.duplicateFrames += 1 }
        if reading.analysis.status == .candidate { updated.candidateLagFrames += 1 }
        guard let hostTime = reading.hostTime else {
            updated.motionStatus = "오디오 시각이 없어 회전 대응 보류"
            return
        }
        let midpoint = AVAudioTime.seconds(forHostTime: hostTime)
            + Double(reading.analysis.sampleCount) / (2 * reading.analysis.sampleRate)
        let duration = Double(reading.analysis.sampleCount) / reading.analysis.sampleRate
        if usesFOA {
            #if DEBUG
            if isSynthetic {
                let silent=ProcessInfo.processInfo.arguments.contains("--synthetic-foa-silence") && updated.analyzedFrames>20
                foa.synthetic(at: ProcessInfo.processInfo.systemUptime,silent: silent,
                    isolatedCandidate: ProcessInfo.processInfo.arguments.contains("--synthetic-foa-isolated"))
                lastFOAFrameAt=Date()
            }
            #endif
            updated.foa=foa.report
            updated.tapFormatChannels=foa.report.capture.foaFormat?.channels
        } else if source == "back" {
            var fixture = false
            #if DEBUG
            if isSynthetic && ProcessInfo.processInfo.arguments.contains("--synthetic-bearing") {
                fixture = true
                spatial.acceptSyntheticDisplay(at: ProcessInfo.processInfo.systemUptime,
                    silent: reading.acousticFeatures == nil,spectrum: reading.soundSpectrum)
            }
            #endif
            if !fixture { spatial.enqueue(features: reading.acousticFeatures,spectrum: reading.soundSpectrum,
                midpoint: midpoint,duration: duration) }
        }
        updated.spatial = spatial.report
        updated.positionTrackingEnabled = spatial.report.trackingAvailable
        updated.localizationEnabled = spatial.report.calibration.profile != nil
        if usesFOA { updated.localizationEnabled = !foa.regions.isEmpty; updated.positionTrackingEnabled=foa.report.synchronization?.issue == .matched }
        if timeOrigin == nil { timeOrigin = midpoint }
        let orientation: AlignedOrientation?
        if isSynthetic {
            // Synthetic pose is explicitly labelled; no device sensors are read.
            if let sample = OrientationSample(timestampSeconds: midpoint, quaternion: [0, 0, 0, 1]) {
                syntheticOrientation.append(sample)
            }
            orientation = syntheticOrientation.aligned(at: midpoint)
        } else {
            orientation = motion.aligned(at: midpoint)
            updated.motionStatus = orientation == nil ? "동일 시각의 회전 데이터 대기" : "기기 회전 기록 중 · 이동거리 미측정"
        }
        updated.latestOrientation = orientation
        calibration.append(analysis: reading.analysis, midpoint: midpoint, orientation: orientation)
        guard let origin = timeOrigin else { return }
        let elapsed = midpoint - origin
        tracker.append(TimedLag(timeSeconds: elapsed, analysis: reading.analysis, orientation: orientation))
        updated.trend = tracker.snapshot(at: elapsed)
    }

    private func refreshTrend() {
        guard phase == .running else { return }
        var updated = report
        defer { report = updated } // One observable update per analysis/timer tick.
        updated.waveformDisplay = waveformDisplay.statistics
        if usesFOA { foa.tick(); updated.foa=foa.report } else { spatial.tick() }
        updated.spatial = spatial.report
        updated.positionTrackingEnabled = spatial.report.trackingAvailable
        updated.localizationEnabled = spatial.report.calibration.profile != nil
        if usesFOA { updated.localizationEnabled = !foa.regions.isEmpty; updated.positionTrackingEnabled=foa.report.synchronization?.issue == .matched }
        let now = ProcessInfo.processInfo.systemUptime
        calibration.tick(at: now)
        updated.calibration = calibration.snapshot(at: now)
        guard let origin = timeOrigin else { return }
        updated.trend = tracker.snapshot(at: ProcessInfo.processInfo.systemUptime - origin)
        if updated.trend?.state == .stale { updated.latestOrientation = nil }
    }

    func stop(reason: String = "수음을 중지하고 마이크를 해제했습니다.") {
        notificationGate.set(nil)
        report.waveformDisplay = waveformDisplay.statistics
        waveformDisplay.stop()
        foaCapture?.stop(); foaCapture=nil
        if usesFOA { foa.stop(); report.foa=foa.report }
        spatial.stop()
        report.spatial = spatial.report
        report.positionTrackingEnabled = false
        report.localizationEnabled = false
        calibration.cancel(reason: reason)
        report.calibration = calibration.snapshot(at: ProcessInfo.processInfo.systemUptime)
        generation += 1 // Invalidates permission results and queued old frames.
        watchdog?.invalidate(); watchdog = nil
        syntheticTimer?.invalidate(); syntheticTimer = nil
        trackingTimer?.invalidate(); trackingTimer = nil
        motion.stop()
        if let origin = timeOrigin {
            report.trend = tracker.snapshot(at: ProcessInfo.processInfo.systemUptime - origin, stopped: true)
        }
        if report.motionStatus != "회전 측정 대기" { report.motionStatus = "회전 측정 중지" }
        if let engine {
            engine.stop()
            if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
        }
        tapInstalled = false
        engine = nil
        pipeline = nil
        var finalReason = reason
        if ownsSession {
            do { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
            catch { finalReason += " 오디오 세션 해제 오류: \(error.localizedDescription)" }
        }
        ownsSession = false
        phase = .idle
        report.status = finalReason
        report.stoppedAt = Date()
        archiveReport()
        onStopped?()
    }

    func enteredBackground() {
        if isBusy { stop(reason: "앱이 백그라운드로 이동해 마이크를 해제했습니다.") }
    }

    func beginCalibrationTrial() {
        guard phase == .running, report.requestedSource == "back" else { return }
        spatial.cancelCalibration()
        _ = calibration.begin(at: ProcessInfo.processInfo.systemUptime)
        report.calibration = calibration.snapshot(at: ProcessInfo.processInfo.systemUptime)
    }

    func cancelCalibrationTrial() {
        calibration.cancel(reason: "사용자 구간 취소")
        report.calibration = calibration.snapshot(at: ProcessInfo.processInfo.systemUptime)
    }

    func resetCalibration() {
        calibration = DirectionCalibration()
        report.calibration = calibration.snapshot(at: ProcessInfo.processInfo.systemUptime)
    }

    func mark(side: String) {
        guard phase == .running, let reading = report.latest else { return }
        report.markedReadings.append(MarkedReading(id: UUID(), declaredSoundSide: side, markedAt: Date(), reading: reading))
        if report.markedReadings.count > 12 { report.markedReadings.removeFirst() }
    }

    func export() -> URL? {
        if isBusy { stop(reason: "보고서를 공유하기 위해 수음을 중지하고 마이크를 해제했습니다.") }
        do {
            let url=try writeExport(DiagnosticExport.encoder().encode(report),sessionID: report.sessionID,historical: false)
            exportURL = url
            return url
        } catch { exportError = "보고서를 만들지 못했습니다: \(error.localizedDescription)"; return nil }
    }

    private func archiveReport() {
        guard report.startedAt != nil || report.foa?.capture.lastError != nil || (usesFOA && report.stoppedAt != nil) else { return }
        let encoder=DiagnosticExport.encoder()
        do {
            let data=try encoder.encode(report)
            savedReports.removeAll { $0.id==report.sessionID }
            savedReports.insert(.init(id: report.sessionID,date: report.startedAt ?? Date(),version: report.appVersion,
                status: report.status,json: data),at: 0)
            savedReports=Array(savedReports.prefix(5))
            UserDefaults.standard.set(try JSONEncoder().encode(savedReports),forKey: "soundfield.savedReports")
        } catch { exportError="이전 진단 저장 실패: \(error.localizedDescription)" }
    }
    func exportSaved(_ saved: SavedNativeReport) -> URL? {
        if isBusy { stop(reason: "이전 진단을 공유하기 위해 계측을 중지했습니다.") }
        do {
            return try writeExport(saved.json,sessionID: saved.id,historical: true)
        } catch { exportError=error.localizedDescription; return nil }
    }
    private func writeExport(_ data: Data, sessionID: UUID, historical: Bool) throws -> URL {
        let now=Date(), exportID=UUID()
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(
            DiagnosticExport.fileName(date: now,sessionID: sessionID,exportID: exportID))
        let encoded=try DiagnosticExport.envelope(data,at: now,exportID: exportID,historical: historical)
        try encoded.write(to: url,options: .atomic); return url
    }

    #if DEBUG
    private func scheduleSyntheticNotifications(token: Int) {
        guard isSynthetic else { return }
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--synthetic-startup-override") {
            NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(),
                userInfo: [AVAudioSessionRouteChangeReasonKey: NSNumber(value: AVAudioSession.RouteChangeReason.override.rawValue)])
            return
        }
        guard arguments.contains("--synthetic-route-events") || arguments.contains("--synthetic-interruption") else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard let self, self.generation == token, self.phase == .running else { return }
            if arguments.contains("--synthetic-route-events") {
                NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(),
                    userInfo: [AVAudioSessionRouteChangeReasonKey: NSNumber(value: AVAudioSession.RouteChangeReason.categoryChange.rawValue)])
                NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
                    userInfo: [AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.ended.rawValue)])
            } else {
                NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
                    userInfo: [AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.began.rawValue)])
            }
        }
    }

    private func startSynthetic(_ processor: TapPipeline) throws {
        report.inputOrigin = "synthetic-debug-fixture"
        if ProcessInfo.processInfo.arguments.contains("--synthetic-mono") {
            report.sessionChannels = 1
            report.tapFormatChannels = 1
            throw CaptureFailure.message("실제 입력이 1채널이라 스테레오 분석을 시작하지 않았습니다. (합성 테스트)")
        }
        report.sessionChannels = 2
        report.hardwareChannels = 2
        report.tapFormatChannels = 2
        report.actualSampleRate = 48_000
        report.selectedSource = "합성 테스트"
        syntheticPCMEnabled = !ProcessInfo.processInfo.arguments.contains("--synthetic-startup-override")
        var state: UInt64 = 7
        var left: [Float] = (0..<4800).map { _ in
            state = state &* 6364136223846793005 &+ 1
            return Float(Double(state >> 33) / Double(UInt32.max) - 0.25)
        }
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--synthetic-heat-tone") {
            let gain=arguments.contains("--synthetic-heat-quiet") ? 0.02 : 1.0
            for i in left.indices {
                let angle=2.0*Double.pi*1000.0*Double(i)/48000.0
                let noise=Double(left[i])*0.08
                let sample=gain*(noise+0.1*sin(angle))
                left[i]=Float(sample)
            }
        }
        let right: [Float] = arguments.contains("--synthetic-silent-right")
            ? [Float](repeating: 0, count: left.count)
            : (0..<4800).map { $0 >= 7 ? left[$0 - 7] : 0 }
        let fixtureStartedAt = ProcessInfo.processInfo.systemUptime
        let fixtureLeft=left
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.syntheticPCMEnabled, self.phase == .running else { return }
                if arguments.contains("--synthetic-waveform-stale"),
                   ProcessInfo.processInfo.systemUptime - fixtureStartedAt > 4 { return }
                // Use the fixture's sample clock, not jitter between main-loop
                // timer callbacks. Missed slots remain real timeline gaps.
                let slot = max(0, Int(floor((ProcessInfo.processInfo.systemUptime - fixtureStartedAt) * 10)) - 1)
                processor.submitSynthetic(left: fixtureLeft, right: right, sampleTime: Int64(slot * 4800),
                    bufferStart: fixtureStartedAt + Double(slot) / 10)
            }
        }
        syntheticTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    #endif
}
