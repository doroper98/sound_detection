import Foundation

public struct ResearchLabels: Codable, Sendable {
    public let label: String
    public let azimuthDegrees: Double
    public let elevationDegrees: Double
    public let signal: String
    public let repetition: Int
    public let distanceMeters: Double

    public init(label: String, azimuthDegrees: Double, elevationDegrees: Double,
                signal: String, repetition: Int, distanceMeters: Double = 1) {
        self.label = label
        self.azimuthDegrees = azimuthDegrees
        self.elevationDegrees = elevationDegrees
        self.signal = signal
        self.repetition = repetition
        self.distanceMeters = distanceMeters
    }

    public var valid: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && label.count <= 120
            && azimuthDegrees.isFinite && (-180...180).contains(azimuthDegrees)
            && elevationDegrees.isFinite && (-90...90).contains(elevationDegrees)
            && ["whiteNoise", "tone1kHz", "speech", "other"].contains(signal)
            && (1...99).contains(repetition) && distanceMeters.isFinite && distanceMeters > 0
    }
}

public struct ResearchPoseSample: Codable, Sendable {
    public let timestamp: Double
    public let quaternion: [Double]
    public let position: Vector3
    public let viewRight: Vector3
    public let viewUp: Vector3
    public let viewForward: Vector3
    public let trackingState: String

    public init(timestamp: Double, quaternion: [Double], position: Vector3,
                viewRight: Vector3, viewUp: Vector3, viewForward: Vector3, trackingState: String) {
        self.timestamp = timestamp
        self.quaternion = quaternion
        self.position = position
        self.viewRight = viewRight
        self.viewUp = viewUp
        self.viewForward = viewForward
        self.trackingState = trackingState
    }

    public var pose: SpatialPose {
        .init(time: timestamp, origin: position, right: viewRight, up: viewUp, forward: viewForward)
    }

    public var valid: Bool {
        pose.valid && quaternion.count == 4 && quaternion.allSatisfy(\.isFinite)
            && abs(quaternion.reduce(0) { $0 + $1 * $1 } - 1) < 0.01
    }
}

public struct ResearchAudioBlock: Codable, Sendable {
    public let stream: String
    public let startHostSeconds: Double
    public let firstFrame: Int
    public let frameCount: Int
}

public struct ResearchAnalysisSample: Codable, Sendable {
    public let midpointHostSeconds: Double
    public let durationSeconds: Double
    public let analysis: FOAAnalysis

    public init(midpointHostSeconds: Double, durationSeconds: Double, analysis: FOAAnalysis) {
        self.midpointHostSeconds = midpointHostSeconds
        self.durationSeconds = durationSeconds
        self.analysis = analysis
    }
}

public struct ResearchFileEntry: Codable, Sendable {
    public let name: String
    public let bytes: Int
    public let sha256: String
}

public struct ResearchManifest: Codable, Sendable {
    public var schemaVersion = 1
    public var complete = true
    public let sessionID: UUID
    public let appVersion: String
    public let buildNumber: String
    public let deviceModel: String
    public let operatingSystem: String
    public let synthetic: Bool
    public let startedAtUTC: String
    public let completedAtUTC: String
    public let stopReason: String
    public let sampleRate: Int
    public let layoutTag: UInt32
    public var channelOrder = ["W", "Y", "Z", "X"]
    public var normalization = "SN3D"
    public var pcmFormat = "Float32LE"
    public let startHostTimeSeconds: Double
    public let foaFrames: Int
    public let poseFrames: Int
    public let analyzedWindows: Int
    public let labels: ResearchLabels
    public let files: [ResearchFileEntry]
    public var coordinateConvention = "User labels: portrait camera right/up/forward, positive azimuth right. Quaternion x,y,z,w rotates portrait view right/up/back into AR session world; position in meters. Host clock seconds for audio and AR. Labels never enter inference."
    public var axisMappingVerified = false
}

/// Single serial owner. Raw buffers precede delivery gates; timeline preserves gaps.
/// manifest.json is written atomically ONLY after close, validation and checksums.
public final class ResearchSessionWriter {
    public let folder: URL
    public let sessionID = UUID()
    public let sampleRate: Int
    private let labels: ResearchLabels
    private let appVersion: String
    private let buildNumber: String
    private let deviceModel: String
    private let operatingSystem: String
    private let synthetic: Bool
    private let startedAt: Date
    private let foa: FloatWAVWriter
    private var stereo: FloatWAVWriter?
    private let saveStereo: Bool
    private var streams = [String: FileHandle]()
    private var firstAudioTime: Double?
    private var lastPoseTime: Double?
    private var poseFrames = 0
    private var analyzedWindows = 0
    private var closed = false

    public init(root: URL, sampleRate: Int, labels: ResearchLabels, appVersion: String,
                buildNumber: String, deviceModel: String, operatingSystem: String,
                synthetic: Bool, saveStereo: Bool = false, date: Date = Date()) throws {
        guard labels.valid else { throw ResearchError.invalid("연구 세션 라벨/정답 각도를 확인하세요.") }
        self.sampleRate = sampleRate
        self.labels = labels
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.deviceModel = deviceModel
        self.operatingSystem = operatingSystem
        self.synthetic = synthetic
        self.saveStereo = saveStereo
        startedAt = date
        folder = root.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        foa = try FloatWAVWriter(url: folder.appendingPathComponent("foa.wav"), channels: 4, sampleRate: sampleRate)
        for name in ["pose.jsonl", "audio-timeline.jsonl", "analysis.jsonl"] {
            let url = folder.appendingPathComponent(name)
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw ResearchError.invalid("연구 시계열 파일을 만들 수 없습니다.")
            }
            streams[name] = try FileHandle(forWritingTo: url)
        }
    }

    public func appendAudio(_ channels: [[Float]], at hostTime: Double, stereo isStereo: Bool = false) throws {
        guard !closed, hostTime.isFinite, hostTime >= 0 else { throw ResearchError.invalid("연구 녹음이 닫혔거나 시각이 잘못됐습니다.") }
        if isStereo && !saveStereo { return }
        if isStereo && stereo == nil {
            stereo = try FloatWAVWriter(url: folder.appendingPathComponent("stereo.wav"), channels: 2, sampleRate: sampleRate)
        }
        guard let writer = isStereo ? stereo : foa else { throw ResearchError.invalid("WAV 저장 경로가 없습니다.") }
        let first = writer.frames
        try writer.append(channels)
        if !isStereo && firstAudioTime == nil { firstAudioTime = hostTime }
        try line(ResearchAudioBlock(stream: isStereo ? "stereo" : "foa", startHostSeconds: hostTime,
                                    firstFrame: first, frameCount: channels[0].count), to: "audio-timeline.jsonl")
    }

    public func appendPose(_ pose: ResearchPoseSample) throws {
        guard !closed, pose.valid else { throw ResearchError.invalid("잘못된 연구 카메라 자세입니다.") }
        if let last = lastPoseTime, pose.timestamp <= last { return }
        try line(pose, to: "pose.jsonl")
        poseFrames += 1
        lastPoseTime = pose.timestamp
    }

    public func appendAnalysis(_ reading: ResearchAnalysisSample) throws {
        guard !closed, reading.midpointHostSeconds.isFinite, reading.durationSeconds.isFinite,
              reading.durationSeconds > 0 else { throw ResearchError.invalid("잘못된 연구 분석 시각입니다.") }
        try line(reading, to: "analysis.jsonl")
        analyzedWindows += 1
    }

    public func finish(reason: String, date: Date = Date()) throws -> ResearchManifest {
        guard !closed else { throw ResearchError.invalid("이미 닫힌 연구 세션입니다.") }
        closed = true
        try foa.finish()
        try stereo?.finish()
        for file in streams.values {
            try file.synchronize()
            try file.close()
        }
        streams = [:]
        guard let start = firstAudioTime, foa.frames > 0, poseFrames > 0 else {
            throw ResearchError.invalid("FOA 원음 또는 AR 자세가 없어 미완료 세션으로 남깁니다.")
        }
        let names = ["foa.wav", "pose.jsonl", "audio-timeline.jsonl", "analysis.jsonl"] + (stereo == nil ? [] : ["stereo.wav"])
        let files = try names.map { name -> ResearchFileEntry in
            let url = folder.appendingPathComponent(name)
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            return .init(name: name, bytes: size, sha256: try ResearchSHA256.file(url))
        }
        let manifest = ResearchManifest(sessionID: sessionID, appVersion: appVersion, buildNumber: buildNumber,
            deviceModel: deviceModel, operatingSystem: operatingSystem, synthetic: synthetic,
            startedAtUTC: DiagnosticExport.timestamp(startedAt), completedAtUTC: DiagnosticExport.timestamp(date),
            stopReason: reason, sampleRate: sampleRate, layoutTag: 12451844, startHostTimeSeconds: start,
            foaFrames: foa.frames, poseFrames: poseFrames, analyzedWindows: analyzedWindows, labels: labels, files: files)
        try DiagnosticExport.encoder().encode(manifest).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
        return manifest
    }

    public func abandon() {
        closed = true
        try? foa.finish()
        try? stereo?.finish()
        for file in streams.values { try? file.close() }
        streams = [:]
    }

    private func line<T: Encodable>(_ value: T, to name: String) throws {
        guard let file = streams[name] else { throw ResearchError.invalid("연구 시계열 파일이 닫혔습니다.") }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(value)
        data.append(10)
        try file.write(contentsOf: data)
    }

    deinit { for file in streams.values { try? file.close() } }
}
