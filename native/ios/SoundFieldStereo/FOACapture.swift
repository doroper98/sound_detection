import AVFoundation
import StereoCore

struct FOAFormatReading: Codable {
    let channels: UInt32
    let layoutTag: UInt32?
    let sampleRate: Double
    let commonFormat: UInt
    let interleaved: Bool
}
struct FOACaptureDiagnostics: Codable {
    var supported: Bool?
    var running=false
    var foaFormat: FOAFormatReading?
    var stereoFormat: FOAFormatReading?
    var foaBuffers=0
    var stereoBuffers=0
    var analyzedWindows=0
    var gaps=0
    var skippedDeliveries=0
    var inputPort: String?
    var events=[String]()
    var lastError: String?
    let timestampOrigin="AVCapture synchronizationClock converted to CM host clock"
}

/// One serial owner for all instances prevents a restart overlapping old teardown.
final class FOACapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private static let queue=DispatchQueue(label: "soundfield.foa.capture",qos: .userInitiated)
    private let session=AVCaptureSession()
    private let spatialOutput=AVCaptureAudioDataOutput()
    private let stereoOutput=AVCaptureAudioDataOutput()
    private var active=false
    private let cancellationLock=NSLock()
    private var cancelled=false
    private func isCancelled() -> Bool { cancellationLock.lock(); defer { cancellationLock.unlock() }; return cancelled }
    private var observers=[NSObjectProtocol]()
    private var foaWindows=PCMWindowAssembler(channels: 4)
    private var stereoWindows=PCMWindowAssembler(channels: 2,size: 4800)
    private let deliveryGate=DispatchSemaphore(value: 1)
    private var diagnostics=FOACaptureDiagnostics()
    private let deliver: @MainActor (FOAAnalysis,Double,Double,FOACaptureDiagnostics) -> Void
    private let failure: @MainActor (String,FOACaptureDiagnostics) -> Void
    private let stereo: ([Float],[Float],Double,Double) -> Void

    init(stereo: @escaping ([Float],[Float],Double,Double) -> Void,
         deliver: @escaping @MainActor (FOAAnalysis,Double,Double,FOACaptureDiagnostics) -> Void,
         failure: @escaping @MainActor (String,FOACaptureDiagnostics) -> Void) {
        self.stereo=stereo; self.deliver=deliver; self.failure=failure
    }
    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in
            Self.queue.async { [self] in
                do {
                    guard !isCancelled() else { throw CancellationError() }
                    try configure()
                    guard !isCancelled() else { throw CancellationError() }
                    active=true
                    installObservers()
                    session.startRunning()
                    guard !isCancelled() else { throw CancellationError() }
                    guard session.isRunning else { throw CaptureFailure.message("공간 오디오 세션이 시작되지 않았습니다.") }
                    diagnostics.running=true
                    continuation.resume()
                } catch {
                    diagnostics.lastError=error.localizedDescription
                    tearDown()
                    let snapshot=diagnostics
                    Task { @MainActor [failure] in failure(error.localizedDescription,snapshot) }
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    private func configure() throws {
        guard #available(iOS 26.0, *) else {
            diagnostics.supported=false
            throw CaptureFailure.message("공간 오디오 방향 분석은 iOS 26 이상이 필요합니다. 측정 상세에서 스테레오 검사를 사용할 수 있습니다.")
        }
        guard let device=AVCaptureDevice.default(for: .audio) else { throw CaptureFailure.message("오디오 입력 장치가 없습니다.") }
        let input=try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        // Do not partially configure FOA outputs: commit validates their combination.
        guard session.canAddInput(input) else {
            session.commitConfiguration(); throw CaptureFailure.message("공간 오디오 입력 연결에 실패했습니다.")
        }
        session.addInput(input)
        guard input.isMultichannelAudioModeSupported(.firstOrderAmbisonics) else {
            diagnostics.supported=false; session.removeInput(input); session.commitConfiguration()
            throw CaptureFailure.message("현재 입력은 4채널 공간 오디오를 지원하지 않습니다. 외부 오디오 연결을 해제하고 다시 시작하세요.")
        }
        diagnostics.supported=true
        input.multichannelAudioMode = .firstOrderAmbisonics
        spatialOutput.spatialAudioChannelLayoutTag=kAudioChannelLayoutTag_HOA_ACN_SN3D | 4
        stereoOutput.spatialAudioChannelLayoutTag=kAudioChannelLayoutTag_Stereo
        guard session.canAddOutput(spatialOutput) else {
            session.removeInput(input); session.commitConfiguration()
            throw CaptureFailure.message("4채널 공간 오디오 출력 연결에 실패했습니다.")
        }
        session.addOutput(spatialOutput)
        guard session.canAddOutput(stereoOutput) else {
            session.removeOutput(spatialOutput); session.removeInput(input); session.commitConfiguration()
            throw CaptureFailure.message("공간 오디오와 스테레오 동시 출력 연결에 실패했습니다.")
        }
        session.addOutput(stereoOutput)
        spatialOutput.setSampleBufferDelegate(self,queue: Self.queue)
        stereoOutput.setSampleBufferDelegate(self,queue: Self.queue)
        session.commitConfiguration()
    }
    private func installObservers() {
        for name in [AVCaptureSession.wasInterruptedNotification,AVCaptureSession.runtimeErrorNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name,object: session,queue: nil) { [weak self] note in
                let description=(note.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription ?? note.name.rawValue
                Self.queue.async { [weak self] in self?.fail("공간 오디오가 중단되었습니다: \(description)") }
            })
        }
    }
    func stop() {
        cancellationLock.lock(); cancelled=true; cancellationLock.unlock()
        Self.queue.async { [self] in tearDown() }
    }
    private func tearDown() {
        active=false
        spatialOutput.setSampleBufferDelegate(nil,queue: nil)
        stereoOutput.setSampleBufferDelegate(nil,queue: nil)
        if session.isRunning { session.stopRunning() }
        observers.forEach(NotificationCenter.default.removeObserver); observers=[]
        diagnostics.running=false
    }
    private func fail(_ message: String) {
        guard active, !isCancelled() else { return }
        diagnostics.lastError=message; diagnostics.events.append(message)
        if diagnostics.events.count>20 { diagnostics.events.removeFirst() }
        tearDown()
        let snapshot=diagnostics
        Task { @MainActor [failure] in failure(message,snapshot) }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard active else { return }
        do {
            let isFOA=output === spatialOutput
            diagnostics.inputPort=AVAudioSession.sharedInstance().currentRoute.inputs.first?.portType.rawValue
            if let description=sampleBuffer.formatDescription, CMFormatDescriptionGetMediaType(description)==kCMMediaType_Audio {
                let format=AVAudioFormat(cmAudioFormatDescription: description)
                let observed=FOAFormatReading(channels: format.channelCount,layoutTag: format.channelLayout?.layoutTag,
                    sampleRate: format.sampleRate.isFinite ? format.sampleRate : 0,commonFormat: format.commonFormat.rawValue,interleaved: format.isInterleaved)
                if isFOA { diagnostics.foaFormat=observed } else { diagnostics.stereoFormat=observed }
            }
            let (channels,format)=try Self.readPCM(sampleBuffer,expectedChannels: isFOA ? 4 : 2,foa: isFOA)
            if isFOA { diagnostics.foaBuffers+=1; diagnostics.foaFormat=format }
            else { diagnostics.stereoBuffers+=1; diagnostics.stereoFormat=format }
            let port=AVAudioSession.sharedInstance().currentRoute.inputs.first?.portType
            diagnostics.inputPort=port?.rawValue
            guard port == .builtInMic else { throw CaptureFailure.message("내장 마이크 입력이 바뀌어 공간 오디오를 중지했습니다.") }
            guard let clock=session.synchronizationClock else { throw CaptureFailure.message("공간 오디오 기준 시계를 찾지 못했습니다.") }
            let time=CMSyncConvertTime(sampleBuffer.presentationTimeStamp,from: clock,to: CMClockGetHostTimeClock()).seconds
            let age=ProcessInfo.processInfo.systemUptime-time
            guard time.isFinite, age >= -0.06, age<1 else { throw CaptureFailure.message("공간 오디오 시각이 기기 시각과 맞지 않습니다.") }
            if isFOA {
                for window in foaWindows.append(channels,at: time,sampleRate: format.sampleRate) {
                    diagnostics.gaps=foaWindows.gaps
                    guard deliveryGate.wait(timeout: .now()) == .success else { diagnostics.skippedDeliveries+=1; continue }
                    let analysis=FOAAnalyzer.analyze(window.channels,sampleRate: window.sampleRate)
                    diagnostics.analyzedWindows+=1
                    let snapshot=diagnostics, duration=Double(window.channels[0].count)/window.sampleRate
                    Task { @MainActor [self] in
                        deliver(analysis,window.start+duration/2,duration,snapshot)
                        deliveryGate.signal()
                    }
                }
            } else {
                for window in stereoWindows.append(channels,at: time,sampleRate: format.sampleRate) {
                    stereo(window.channels[0],window.channels[1],window.sampleRate,window.start)
                }
            }
        } catch { fail(error.localizedDescription) }
    }
    /// Copy using Core Media's PCM API; never reinterpret compressed or differently laid-out data.
    static func readPCM(_ sample: CMSampleBuffer, expectedChannels: Int, foa: Bool) throws -> ([[Float]],FOAFormatReading) {
        guard let description=sample.formatDescription,
              CMFormatDescriptionGetMediaType(description)==kCMMediaType_Audio,
              let asbd=CMAudioFormatDescriptionGetStreamBasicDescription(description),
              asbd.pointee.mFormatID==kAudioFormatLinearPCM,
              asbd.pointee.mFormatFlags & kAudioFormatFlagIsBigEndian == 0 else {
            throw CaptureFailure.message("공간 오디오 출력이 지원하는 PCM 형식이 아닙니다.")
        }
        let format=AVAudioFormat(cmAudioFormatDescription: description)
        let count=sample.numSamples, layout=format.channelLayout?.layoutTag
        guard format.channelCount==expectedChannels, (1...16384).contains(count),
              format.sampleRate.isFinite, (32000...96000).contains(format.sampleRate),
              !foa || layout == (kAudioChannelLayoutTag_HOA_ACN_SN3D | 4),
              let buffer=AVAudioPCMBuffer(pcmFormat: format,frameCapacity: AVAudioFrameCount(count)) else {
            throw CaptureFailure.message("실제 채널/레이아웃 불일치: \(format.channelCount)채널, tag \(layout.map(String.init) ?? "없음").")
        }
        buffer.frameLength=AVAudioFrameCount(count)
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample,at: 0,frameCount: Int32(count),into: buffer.mutableAudioBufferList)==noErr else {
            throw CaptureFailure.message("PCM 버퍼 복사에 실패했습니다.")
        }
        let buffers=UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        var channels=[[Float]]()
        for c in 0..<expectedChannels {
            let b=buffers[format.isInterleaved ? 0 : c]
            guard let data=b.mData else { throw CaptureFailure.message("PCM 채널 데이터가 없습니다.") }
            let stride=format.isInterleaved ? expectedChannels : 1, offset=format.isInterleaved ? c : 0
            let values: [Float]
            switch format.commonFormat {
            case .pcmFormatFloat32: values=(0..<count).map { data.assumingMemoryBound(to: Float.self)[$0*stride+offset] }
            case .pcmFormatFloat64: values=(0..<count).map { Float(data.assumingMemoryBound(to: Double.self)[$0*stride+offset]) }
            case .pcmFormatInt16: values=(0..<count).map { Float(data.assumingMemoryBound(to: Int16.self)[$0*stride+offset])/32768 }
            case .pcmFormatInt32: values=(0..<count).map { Float(data.assumingMemoryBound(to: Int32.self)[$0*stride+offset])/2147483648 }
            default: throw CaptureFailure.message("지원하지 않는 PCM 샘플 형식입니다.")
            }
            guard values.allSatisfy(\.isFinite) else { throw CaptureFailure.message("PCM에 유효하지 않은 값이 있습니다.") }
            channels.append(values)
        }
        return (channels,.init(channels: format.channelCount,layoutTag: layout,sampleRate: format.sampleRate,
            commonFormat: format.commonFormat.rawValue,interleaved: format.isInterleaved))
    }
}
