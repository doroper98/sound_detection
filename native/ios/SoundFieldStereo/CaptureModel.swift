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
}

struct MarkedReading: Codable, Identifiable {
    let id: UUID
    let declaredSoundSide: String
    let markedAt: Date
    let reading: FrameReading
}

struct NativeReport: Encodable {
    var schemaVersion = 2
    var appVersion = "0.4.0-native-continuous-prototype"
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
    var trend: LagTrend?
    var motionStatus = "회전 측정 대기"
    var latestOrientation: AlignedOrientation?
    let attitudeReferenceFrame = "CoreMotion.xArbitraryZVertical; quaternion x,y,z,w"
    let positionTrackingEnabled = false
    let acousticCalibrationVerified = false
    let physicalMicrophonesVerified = false
    let hardwareSynchronizationVerified = false
    let localizationEnabled = false
    let lagConvention = "right-minus-left; positive means right arrives later"
    let note = "Processed stereo signal lag only. No microphone geometry or physical TDOA calibration. No PCM, audio files, camera frames, device IDs, or source coordinates are exported."
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

/// One analysis job at a time, including its pending UI delivery. The audio tap
/// never queues an unbounded PCM history; busy buffers are counted and dropped.
private final class TapPipeline: @unchecked Sendable {
    private let gate = DispatchSemaphore(value: 1)
    private let queue = DispatchQueue(label: "soundfield.stereo.analysis", qos: .userInitiated)
    private let lock = NSLock()
    private var skipped = 0
    private var sequence = 0
    private var gaps = 0
    private var nextSampleTime: Int64?
    private let deliver: @MainActor (Result<FrameReading, Error>) -> Void

    init(deliver: @escaping @MainActor (Result<FrameReading, Error>) -> Void) {
        self.deliver = deliver
    }

    func submit(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        guard gate.wait(timeout: .now()) == .success else {
            lock.lock(); skipped += 1; lock.unlock()
            return
        }
        guard buffer.format.channelCount == 2,
              buffer.format.commonFormat == .pcmFormatFloat32,
              let pointers = buffer.floatChannelData,
              (128...16_384).contains(Int(buffer.frameLength)) else {
            finish(.failure(CaptureFailure.message("실제 PCM이 분석 가능한 2채널 Float32 형식이 아닙니다. 수음을 중지했습니다.")))
            return
        }
        let count = Int(buffer.frameLength)
        let stride = buffer.stride
        let left = (0..<count).map { pointers[0][$0 * stride] }
        let right: [Float]
        if buffer.format.isInterleaved {
            right = (0..<count).map { pointers[0][$0 * stride + 1] }
        } else {
            right = (0..<count).map { pointers[1][$0 * stride] }
        }
        analyze(left: left, right: right, sampleRate: buffer.format.sampleRate,
                sampleTime: time.isSampleTimeValid ? time.sampleTime : nil,
                hostTime: time.isHostTimeValid ? time.hostTime : nil)
    }

    #if DEBUG
    func submitSynthetic(left: [Float], right: [Float], sampleTime: Int64) {
        guard gate.wait(timeout: .now()) == .success else { return }
        let bufferStart = ProcessInfo.processInfo.systemUptime - Double(left.count) / 48_000
        analyze(left: left, right: right, sampleRate: 48_000, sampleTime: sampleTime,
                hostTime: AVAudioTime.hostTime(forSeconds: bufferStart))
    }
    #endif

    private func analyze(left: [Float], right: [Float], sampleRate: Double, sampleTime: Int64?, hostTime: UInt64?) {
        queue.async { [self] in
            do {
                let analysis = try StereoAnalyzer.analyze(left: left, right: right, sampleRate: sampleRate)
                sequence += 1
                if let expected = nextSampleTime, let actual = sampleTime, expected != actual { gaps += 1 }
                nextSampleTime = sampleTime.map { $0 + Int64(left.count) }
                lock.lock(); let skippedCount = skipped; lock.unlock()
                finish(.success(FrameReading(sequence: sequence, sampleTime: sampleTime, hostTime: hostTime,
                    skippedBuffers: skippedCount, analyzedTimelineGaps: gaps, analysis: analysis)))
            } catch { finish(.failure(error)) }
        }
    }

    private func finish(_ result: Result<FrameReading, Error>) {
        Task { @MainActor [self] in
            deliver(result)
            gate.signal()
        }
    }
}

@MainActor
final class CaptureModel: ObservableObject {
    enum Phase { case idle, requestingPermission, running }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var report = NativeReport()
    @Published var source = "back"
    @Published var exportError: String?
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

    var isBusy: Bool { phase != .idle }
    var isSynthetic: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--synthetic-stereo")
        #else
        return false
        #endif
    }

    init() {
        let gate = notificationGate
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVAudioSession.mediaServicesWereLostNotification, AVAudioSession.mediaServicesWereResetNotification,
                     Notification.Name.AVAudioEngineConfigurationChange] {
            // Inspect at posting time so our own setup notifications cannot be
            // delivered later and mistaken for an in-flight route interruption.
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                guard let epoch = gate.read() else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.generation == epoch, self.phase == .running else { return }
                    self.stop(reason: "오디오 경로 변경 또는 인터럽트로 중지했습니다. 연결 상태를 확인하고 다시 시작하세요.")
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

    func start() {
        guard !isBusy else { return }
        generation += 1
        let token = generation
        report = NativeReport()
        tracker = ContinuousLagTracker()
        timeOrigin = nil
        syntheticOrientation = OrientationHistory()
        report.requestedSource = source
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
                let processor = TapPipeline { [weak self] result in
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
                    try startHardware(processor)
                }
                phase = .running
                notificationGate.set(token)
                report.startedAt = Date()
                report.status = isSynthetic ? "합성 테스트 입력 · 실기기 결과 아님" : "스테레오 수음 중 · 세로 방향을 유지하세요."
                lastFrameAt = Date()
                let trendTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.refreshTrend() }
                }
                trackingTimer = trendTimer
                RunLoop.main.add(trendTimer, forMode: .common)
                watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.phase == .running, Date().timeIntervalSince(self.lastFrameAt) > 5 else { return }
                        self.stop(reason: "5초 동안 분석 가능한 PCM이 들어오지 않아 수음을 중지했습니다.")
                    }
                }
            } catch { stop(reason: error.localizedDescription) }
        }
    }

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
        // nil keeps the input node's actual format. No mono-to-stereo converter,
        // channel duplicator, mixer, or speaker output is installed.
        input.installTap(onBus: 0, bufferSize: 2048, format: nil) { @Sendable buffer, time in
            processor.submit(buffer, at: time)
        }
        tapInstalled = true
        audioEngine.prepare()
        try audioEngine.start()
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
        lastFrameAt = Date()
        report.latest = reading
        report.analyzedFrames += 1
        if reading.analysis.channels[0].active { report.activeLeftFrames += 1 }
        if reading.analysis.channels[1].active { report.activeRightFrames += 1 }
        if reading.analysis.duplicateSuspected { report.duplicateFrames += 1 }
        if reading.analysis.status == .candidate { report.candidateLagFrames += 1 }
        guard let hostTime = reading.hostTime else {
            report.motionStatus = "오디오 시각이 없어 회전 대응 보류"
            return
        }
        let midpoint = AVAudioTime.seconds(forHostTime: hostTime)
            + Double(reading.analysis.sampleCount) / (2 * reading.analysis.sampleRate)
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
            report.motionStatus = orientation == nil ? "동일 시각의 회전 데이터 대기" : "기기 회전 기록 중 · 이동거리 미측정"
        }
        report.latestOrientation = orientation
        guard let origin = timeOrigin else { return }
        let elapsed = midpoint - origin
        tracker.append(TimedLag(timeSeconds: elapsed, analysis: reading.analysis, orientation: orientation))
        report.trend = tracker.snapshot(at: elapsed)
    }

    private func refreshTrend() {
        guard phase == .running, let origin = timeOrigin else { return }
        report.trend = tracker.snapshot(at: ProcessInfo.processInfo.systemUptime - origin)
        if report.trend?.state == .stale { report.latestOrientation = nil }
    }

    func stop(reason: String = "수음을 중지하고 마이크를 해제했습니다.") {
        notificationGate.set(nil)
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
    }

    func enteredBackground() {
        if isBusy { stop(reason: "앱이 백그라운드로 이동해 마이크를 해제했습니다.") }
    }

    func mark(side: String) {
        guard phase == .running, let reading = report.latest else { return }
        report.markedReadings.append(MarkedReading(id: UUID(), declaredSoundSide: side, markedAt: Date(), reading: reading))
        if report.markedReadings.count > 12 { report.markedReadings.removeFirst() }
    }

    func export() -> URL? {
        if isBusy { stop(reason: "보고서를 공유하기 위해 수음을 중지하고 마이크를 해제했습니다.") }
        do {
            if let exportURL { try? FileManager.default.removeItem(at: exportURL) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("soundfield-native-stereo.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(report).write(to: url, options: .atomic)
            exportURL = url
            return url
        } catch { exportError = "보고서를 만들지 못했습니다: \(error.localizedDescription)"; return nil }
    }

    #if DEBUG
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
        var state: UInt64 = 7
        let left: [Float] = (0..<2048).map { _ in
            state = state &* 6364136223846793005 &+ 1
            return Float(Double(state >> 33) / Double(UInt32.max) - 0.25)
        }
        let right: [Float] = (0..<2048).map { $0 >= 7 ? left[$0 - 7] : 0 }
        var position: Int64 = 0
        syntheticTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            processor.submitSynthetic(left: left, right: right, sampleTime: position)
            position += 2048
        }
    }
    #endif
}
