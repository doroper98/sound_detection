import Foundation

public struct ResearchReplayWindow: Codable, Sendable {
    public let midpointHostSeconds: Double
    public let elapsedSeconds: Double
    public let analysis: FOAAnalysis
    public let poseAlignment: PoseAlignmentInspection
    public let recordedLiveAnalysis: Bool
    public let matchesLiveAnalysis: Bool?
}

public struct ResearchReplayResult: Codable, Sendable {
    public let sessionID: UUID
    public let synthetic: Bool
    public let assemblerGaps: Int
    public let liveWindows: Int
    public let comparedWindows: Int
    public let mismatchedWindows: Int
    public let unmatchedLiveWindows: Int
    public let windows: [ResearchReplayWindow]
}

public enum ResearchReplay {
    public static func run(folder: URL) throws -> ResearchReplayResult {
        let manifestURL = folder.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ResearchError.invalid("manifest.json이 없는 미완료 연구 세션입니다.")
        }
        let manifest = try JSONDecoder().decode(ResearchManifest.self, from: Data(contentsOf: manifestURL))
        try validate(manifest, folder: folder)
        let wav = try FloatWAVReader(url: folder.appendingPathComponent("foa.wav"))
        guard wav.channels == 4, wav.sampleRate == manifest.sampleRate, wav.frames == manifest.foaFrames else {
            throw ResearchError.invalid("WAV와 manifest 형식이 다릅니다.")
        }
        let blocks: [ResearchAudioBlock] = try lines(folder.appendingPathComponent("audio-timeline.jsonl"))
        let poses: [ResearchPoseSample] = try lines(folder.appendingPathComponent("pose.jsonl"))
        let live: [ResearchAnalysisSample] = try lines(folder.appendingPathComponent("analysis.jsonl"))
        guard poses.count == manifest.poseFrames, live.count == manifest.analyzedWindows,
              poses.allSatisfy(\.valid), zip(poses, poses.dropFirst()).allSatisfy({ $0.timestamp < $1.timestamp }),
              live.allSatisfy({ $0.midpointHostSeconds.isFinite && $0.durationSeconds > 0 }),
              zip(live, live.dropFirst()).allSatisfy({ $0.midpointHostSeconds < $1.midpointHostSeconds }) else {
            throw ResearchError.invalid("자세 또는 실시간 분석 시계열이 잘못됐습니다.")
        }
        var assembler = PCMWindowAssembler(channels: 4)
        var poseHistory = SpatialPoseHistory()
        var poseIndex = 0
        var tracking = "unavailable"
        var firstFrame = 0
        var lastTime: Double?
        var liveIndex = 0
        var compared = 0
        var mismatched = 0
        var output = [ResearchReplayWindow]()
        for block in blocks where block.stream == "foa" {
            guard block.firstFrame == firstFrame, block.startHostSeconds.isFinite,
                  block.frameCount > 0, block.frameCount <= 16384,
                  lastTime.map({ block.startHostSeconds > $0 }) ?? true else {
                throw ResearchError.invalid("FOA 오디오 버퍼 순서/시각이 잘못됐습니다.")
            }
            if firstFrame == 0, abs(block.startHostSeconds - manifest.startHostTimeSeconds) > 1e-9 {
                throw ResearchError.invalid("첫 오디오 시각이 manifest와 다릅니다.")
            }
            let pcm = try wav.read(at: firstFrame, count: block.frameCount)
            firstFrame += block.frameCount
            lastTime = block.startHostSeconds
            for window in assembler.append(pcm, at: block.startHostSeconds, sampleRate: Double(wav.sampleRate)) {
                let duration = Double(window.channels[0].count) / window.sampleRate
                let midpoint = window.start + duration / 2
                let now = window.start + duration + 0.06
                while poseIndex < poses.count, poses[poseIndex].timestamp <= now {
                    let pose = poses[poseIndex]
                    tracking = pose.trackingState
                    if tracking == "normal" { poseHistory.append(pose.pose) }
                    else { poseHistory = SpatialPoseHistory() }
                    poseIndex += 1
                }
                let alignment = poseHistory.inspect(midpoint: midpoint, duration: duration, now: now, trackingState: tracking)
                let analysis = FOAAnalyzer.analyze(window.channels, sampleRate: window.sampleRate)
                while liveIndex < live.count, live[liveIndex].midpointHostSeconds < midpoint - 1e-6 { liveIndex += 1 }
                var match: Bool?
                if liveIndex < live.count, abs(live[liveIndex].midpointHostSeconds - midpoint) <= 1e-6 {
                    let sameAnalysis = try equivalent(analysis, live[liveIndex].analysis)
                    match = abs(live[liveIndex].durationSeconds - duration) <= 1e-6 && sameAnalysis
                    compared += 1
                    if match == false { mismatched += 1 }
                    liveIndex += 1
                }
                output.append(.init(midpointHostSeconds: midpoint,
                    elapsedSeconds: midpoint - manifest.startHostTimeSeconds, analysis: analysis,
                    poseAlignment: alignment, recordedLiveAnalysis: match != nil, matchesLiveAnalysis: match))
            }
        }
        guard firstFrame == wav.frames else { throw ResearchError.invalid("오디오 시각 파일이 WAV 전체를 설명하지 않습니다.") }
        return .init(sessionID: manifest.sessionID, synthetic: manifest.synthetic, assemblerGaps: assembler.gaps,
            liveWindows: live.count, comparedWindows: compared, mismatchedWindows: mismatched,
            unmatchedLiveWindows: live.count - compared, windows: output)
    }

    public static func validate(_ manifest: ResearchManifest, folder: URL) throws {
        let required: Set<String> = ["foa.wav", "pose.jsonl", "audio-timeline.jsonl", "analysis.jsonl"]
        let allowed = required.union(["stereo.wav"])
        let names = Set(manifest.files.map(\.name))
        guard manifest.schemaVersion == 1, manifest.complete, manifest.labels.valid,
              manifest.channelOrder == ["W", "Y", "Z", "X"], manifest.normalization == "SN3D",
              manifest.pcmFormat == "Float32LE", manifest.layoutTag == 12451844,
              (32000...96000).contains(manifest.sampleRate), manifest.foaFrames > 0,
              manifest.foaFrames <= manifest.sampleRate * 120,
              manifest.startHostTimeSeconds.isFinite, manifest.startHostTimeSeconds >= 0,
              required.isSubset(of: names), names.isSubset(of: allowed), names.count == manifest.files.count else {
            throw ResearchError.invalid("지원하는 완료 연구 manifest가 아닙니다.")
        }
        let base = folder.resolvingSymlinksInPath().standardizedFileURL
        for file in manifest.files {
            let url = folder.appendingPathComponent(file.name).resolvingSymlinksInPath().standardizedFileURL
            guard url.deletingLastPathComponent() == base, (0...200_000_000).contains(file.bytes),
                  file.sha256.count == 64,
                  try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == file.bytes,
                  try ResearchSHA256.file(url) == file.sha256 else {
                throw ResearchError.invalid("파일 경로·크기·SHA-256 불일치: \(file.name)")
            }
        }
    }

    private static func lines<T: Decodable>(_ url: URL) throws -> [T] {
        let data = try Data(contentsOf: url)
        guard data.count <= 32_000_000 else { throw ResearchError.invalid("연구 JSONL 크기 한도입니다.") }
        return try data.split(separator: 10).map { try JSONDecoder().decode(T.self, from: Data($0)) }
    }

    private static func equivalent(_ a: FOAAnalysis, _ b: FOAAnalysis) throws -> Bool {
        let encoder = JSONEncoder()
        return equalJSON(try JSONSerialization.jsonObject(with: encoder.encode(a)),
                         try JSONSerialization.jsonObject(with: encoder.encode(b)))
    }

    private static func equalJSON(_ a: Any, _ b: Any) -> Bool {
        if let a = a as? NSNumber, let b = b as? NSNumber { return abs(a.doubleValue - b.doubleValue) <= 1e-6 }
        if let a = a as? String, let b = b as? String { return a == b }
        if let a = a as? [Any], let b = b as? [Any] { return a.count == b.count && zip(a,b).allSatisfy { equalJSON($0.0, $0.1) } }
        if let a = a as? [String: Any], let b = b as? [String: Any] {
            return Set(a.keys) == Set(b.keys) && a.allSatisfy { key, value in b[key].map { equalJSON(value, $0) } ?? false }
        }
        return a is NSNull && b is NSNull
    }
}
