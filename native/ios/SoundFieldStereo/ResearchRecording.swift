import Foundation
import UIKit
import StereoCore

struct ResearchConfiguration {
    let root: URL
    let labels: ResearchLabels
    let saveStereo: Bool
    let synthetic: Bool
    let deviceModel: String
    let operatingSystem: String
    let appVersion: String
    let buildNumber: String
}

/// File work never runs on the audio or main queues. A bounded backlog fails
/// explicitly instead of silently dropping PCM from a supposedly complete file.
final class ResearchRecordingSession: @unchecked Sendable {
    let id = UUID()
    private let configuration: ResearchConfiguration
    private let queue = DispatchQueue(label: "soundfield.research.files", qos: .utility)
    private let lock = NSLock()
    private var accepting = true
    private var failed = false
    private var limitReached = false
    private var pendingBytes = 0
    private var abortRequested = false
    private var stopReason = "captureStopped"
    private var writer: ResearchSessionWriter?
    private var earlyPoses = [ResearchPoseSample]()
    private var frames = 0
    private var lastProgress = 0
    private let update: @MainActor (UUID, String, Double, URL?) -> Void

    init(configuration: ResearchConfiguration,
         update: @escaping @MainActor (UUID, String, Double, URL?) -> Void) {
        self.configuration = configuration
        self.update = update
    }

    func setStopReason(_ reason: String) {
        lock.lock()
        stopReason = reason
        lock.unlock()
    }

    func appendAudio(_ channels: [[Float]], time: Double, sampleRate: Double, stereo: Bool) {
        let bytes = channels.reduce(0) { $0 + $1.count * 4 }
        let sampleDate = Date().addingTimeInterval(time - ProcessInfo.processInfo.systemUptime)
        enqueue(bytes: bytes) { [self] in
            guard sampleRate.isFinite, sampleRate.rounded() == sampleRate,
                  (32000...96000).contains(sampleRate) else {
                throw ResearchError.invalid("연구 녹음 샘플률이 잘못됐습니다.")
            }
            if writer == nil {
                if stereo { return }
                writer = try ResearchSessionWriter(root: configuration.root, sampleRate: Int(sampleRate),
                    labels: configuration.labels, appVersion: configuration.appVersion,
                    buildNumber: configuration.buildNumber, deviceModel: configuration.deviceModel,
                    operatingSystem: configuration.operatingSystem, synthetic: configuration.synthetic,
                    saveStereo: configuration.saveStereo, date: sampleDate)
                for pose in earlyPoses { try writer?.appendPose(pose) }
                earlyPoses = []
            }
            guard let writer, writer.sampleRate == Int(sampleRate) else {
                throw ResearchError.invalid("녹음 도중 오디오 형식이 바뀌었습니다.")
            }
            if !stereo, frames + (channels.first?.count ?? 0) > writer.sampleRate * 120 {
                limitReached = true
                setStopReason("120SecondLimit")
                finish()
                return
            }
            try writer.appendAudio(channels, at: time, stereo: stereo)
            if !stereo {
                frames += channels.first?.count ?? 0
                if frames - lastProgress >= writer.sampleRate / 2 {
                    lastProgress = frames
                    notify("recording", seconds: Double(frames) / sampleRate)
                }
            }
        }
    }

    func appendPose(_ pose: ResearchPoseSample) {
        enqueue(bytes: 512) { [self] in
            if let writer { try writer.appendPose(pose) }
            else {
                earlyPoses.append(pose)
                if earlyPoses.count > 120 { earlyPoses.removeFirst() }
            }
        }
    }

    func appendAnalysis(_ analysis: FOAAnalysis, midpoint: Double, duration: Double) {
        enqueue(bytes: 8192) { [self] in
            try writer?.appendAnalysis(.init(midpointHostSeconds: midpoint, durationSeconds: duration, analysis: analysis))
        }
    }

    func finish() {
        lock.lock()
        guard accepting else { lock.unlock(); return }
        accepting = false
        let reason = stopReason
        lock.unlock()
        queue.async { [self] in
            guard !failed else { return }
            do {
                guard let writer else { throw ResearchError.invalid("FOA 입력이 없어 연구 녹음이 생성되지 않았습니다.") }
                notify("closing")
                _ = try writer.finish(reason: reason)
                notify("complete", seconds: Double(frames) / Double(writer.sampleRate), folder: writer.folder)
                self.writer = nil
            } catch { failOnQueue(error.localizedDescription) }
        }
    }

    func abandon(_ reason: String) {
        lock.lock()
        accepting = false
        abortRequested = true
        lock.unlock()
        queue.async { [self] in failOnQueue(reason) }
    }

    private func enqueue(bytes: Int, operation: @escaping () throws -> Void) {
        lock.lock()
        guard accepting else { lock.unlock(); return }
        guard pendingBytes + bytes <= 8 * 1024 * 1024 else {
            accepting = false
            abortRequested = true
            lock.unlock()
            queue.async { [self] in failOnQueue("저장 속도가 수음을 따라가지 못해 미완료로 중지했습니다.") }
            return
        }
        pendingBytes += bytes
        queue.async { [self] in
            defer {
                lock.lock()
                pendingBytes -= bytes
                lock.unlock()
            }
            lock.lock()
            let aborted = abortRequested
            lock.unlock()
            guard !failed, !limitReached, !aborted else { return }
            do { try operation() }
            catch { failOnQueue(error.localizedDescription) }
        }
        lock.unlock()
    }

    private func failOnQueue(_ message: String) {
        guard !failed else { return }
        failed = true
        lock.lock()
        accepting = false
        lock.unlock()
        writer?.abandon()
        writer = nil
        earlyPoses = []
        notify("미완료: " + message)
    }

    private func notify(_ state: String, seconds: Double = 0, folder: URL? = nil) {
        Task { @MainActor [self] in update(id, state, seconds, folder) }
    }
}

/// Only explicitly armed camera sessions can record. Every capture instance keeps
/// its own session, so delayed teardown can never close a subsequent recording.
final class ResearchRecordingHub: @unchecked Sendable {
    static let shared = ResearchRecordingHub()
    private let lock = NSLock()
    private var session: ResearchRecordingSession?

    var current: ResearchRecordingSession? {
        lock.lock()
        defer { lock.unlock() }
        return session
    }

    func set(_ value: ResearchRecordingSession?) {
        lock.lock()
        session = value
        lock.unlock()
    }
}

@MainActor
final class ResearchRecordingModel: ObservableObject {
    static let shared = ResearchRecordingModel()
    @Published var enabled = false
    @Published var label = "측정"
    @Published var azimuth = 0
    @Published var elevation = 0
    @Published var signal = "whiteNoise"
    @Published var repetition = 1
    @Published var saveStereo = false
    @Published private(set) var recording = false
    @Published private(set) var finalizing = false
    @Published private(set) var seconds = 0.0
    @Published private(set) var status = "연구 녹음 꺼짐"
    @Published private(set) var sessions = [ResearchManifest]()
    @Published private(set) var exporting = false
    private var active: ResearchRecordingSession?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ResearchSessions", isDirectory: true)
    }

    func arm(synthetic: Bool, source: String) -> Bool {
        guard !finalizing, !exporting else { return false }
        guard enabled else { return true }
        guard source == "back" else {
            status = "연구 녹음은 후면 카메라·공간 오디오 수음을 사용하세요."
            return false
        }
        let labels = ResearchLabels(label: label, azimuthDegrees: Double(azimuth),
            elevationDegrees: Double(elevation), signal: signal, repetition: repetition)
        guard labels.valid else { status = "세션 이름과 각도를 확인하세요."; return false }
        do {
            var folder = root
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
        } catch {
            status = "연구 저장 폴더를 만들 수 없습니다: " + error.localizedDescription
            return false
        }
        var info = utsname()
        uname(&info)
        let capacity = MemoryLayout.size(ofValue: info.machine)
        let hardware = withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
        let configuration = ResearchConfiguration(root: root, labels: labels, saveStereo: saveStereo,
            synthetic: synthetic, deviceModel: hardware, operatingSystem: UIDevice.current.systemVersion,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown")
        let session = ResearchRecordingSession(configuration: configuration) { [weak self] id, state, seconds, folder in
            self?.received(id: id, state: state, seconds: seconds, folder: folder)
        }
        active = session
        recording = true
        seconds = 0
        status = "REC · 원음 저장 준비"
        ResearchRecordingHub.shared.set(session)
        return true
    }

    func end(reason: String = "userStopped") {
        guard let active, !finalizing else { return }
        active.setStopReason(reason)
        ResearchRecordingHub.shared.set(nil)
        recording = false
        finalizing = true
        status = "연구 데이터 저장 중"
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish research recording") { [weak self] in
                Task { @MainActor in
                    self?.active?.abandon("백그라운드 저장 시간이 만료되었습니다.")
                    self?.releaseBackgroundTask()
                }
            }
        }
        FOACapture.finishResearchWhenIdle(active)
    }

    private func received(id: UUID, state: String, seconds: Double, folder: URL?) {
        guard id == active?.id else { return }
        self.seconds = seconds
        if state == "closing" {
            status = "연구 파일 무결성 확인 중"
            return
        }
        if state == "recording" {
            if recording { status = String(format: "REC · %.1f초 · 아이폰에 저장 중", seconds) }
            return
        }
        recording = false
        finalizing = false
        active = nil
        ResearchRecordingHub.shared.set(nil)
        status = state == "complete" ? "저장 완료 · 연구 데이터 공유로 ZIP을 첨부하세요." : state
        releaseBackgroundTask()
        reload()
    }

    func reload() {
        let root = root
        Task.detached {
            let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            let sessions = folders.compactMap { folder -> ResearchManifest? in
                guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")) else { return nil }
                return try? JSONDecoder().decode(ResearchManifest.self, from: data)
            }.sorted { $0.startedAtUTC > $1.startedAtUTC }
            await MainActor.run { self.sessions = sessions }
        }
    }

    func share(_ manifest: ResearchManifest) async -> URL? {
        guard !recording, !finalizing, !exporting else { return nil }
        exporting = true
        defer { exporting = false }
        let folder = root.appendingPathComponent(manifest.sessionID.uuidString, isDirectory: true)
        let stamp = manifest.startedAtUTC.replacingOccurrences(of: ":", with: "-")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("SoundField-research-\(stamp)-\(UUID().uuidString).zip")
        do {
            try await Task.detached(priority: .utility) {
                try ResearchArchive.create(folder: folder, destination: destination)
            }.value
            status = "실제 녹음이 포함된 ZIP입니다. 이 대화에 첨부해 주세요."
            return destination
        } catch {
            status = "연구 데이터 공유 실패: " + error.localizedDescription
            return nil
        }
    }

    private func releaseBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
}
