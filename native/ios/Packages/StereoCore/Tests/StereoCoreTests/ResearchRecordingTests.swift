import Foundation
import XCTest
@testable import StereoCore

final class ResearchRecordingTests: XCTestCase {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func writer(_ root: URL) throws -> ResearchSessionWriter {
        try .init(root: root, sampleRate: 48000,
            labels: .init(label: "test", azimuthDegrees: 0, elevationDegrees: 0, signal: "tone1kHz", repetition: 1),
            appVersion: "test", buildNumber: "test", deviceModel: "synthetic", operatingSystem: "test", synthetic: true)
    }

    private func pose(_ time: Double) -> ResearchPoseSample {
        .init(timestamp: time, quaternion: [0,0,0,1], position: .zero,
              viewRight: .init(1,0,0), viewUp: .init(0,1,0), viewForward: .init(0,0,-1), trackingState: "normal")
    }

    func testSHA256KnownVectorsAndChunkBoundaries() {
        var hash = ResearchSHA256()
        XCTAssertEqual(hash.hexDigest(), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        hash.update(Data("a".utf8))
        hash.update(Data("bc".utf8))
        XCTAssertEqual(hash.hexDigest(), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        var million = ResearchSHA256()
        for _ in 0..<1000 { million.update(Data(repeating: 97, count: 1000)) }
        XCTAssertEqual(million.hexDigest(), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }

    func testFloat32WAVPreservesEveryChannelBitAndRejectsTruncation() throws {
        let file = try root().appendingPathComponent("audio.wav")
        let writer = try FloatWAVWriter(url: file, channels: 4, sampleRate: 48000)
        let pcm: [[Float]] = [[0,-0.0,0.125],[-0.7,0.2,0.3],[0.5,0.6,0.7],[0.8,-0.9,1]]
        try writer.append(pcm)
        try writer.finish()
        let reader = try FloatWAVReader(url: file)
        let decoded = try reader.read(at: 0, count: 3)
        XCTAssertEqual(decoded.map { $0.map(\.bitPattern) }, pcm.map { $0.map(\.bitPattern) })
        XCTAssertEqual(reader.frames,3)
        var bytes = try Data(contentsOf: file)
        bytes.removeLast()
        try bytes.write(to: file)
        XCTAssertThrowsError(try FloatWAVReader(url: file))
    }

    func testRoundTripUsesOriginalBufferTimingAndLiveAnalysis() throws {
        let session = try writer(root())
        var assembler = PCMWindowAssembler(channels: 4)
        for i in 0...90 { try session.appendPose(pose(100 + Double(i) / 30)) }
        for block in 0..<16 {
            // A real timestamp gap must reset assembly instead of joining unrelated PCM.
            let time = 100 + Double(block * 1024) / 48000 + (block >= 7 ? 0.3 : 0)
            let wave: [Float] = (0..<1024).map { Float(0.08 * sin(Double($0 + block * 1024) * Double.pi / 24)) }
            let zero = [Float](repeating: 0, count: wave.count)
            let pcm = [wave,zero,zero,wave]
            try session.appendAudio(pcm, at: time)
            for window in assembler.append(pcm, at: time, sampleRate: 48000) {
                let duration = 4096.0 / 48000
                try session.appendAnalysis(.init(midpointHostSeconds: window.start + duration / 2,
                    durationSeconds: duration, analysis: FOAAnalyzer.analyze(window.channels, sampleRate: 48000)))
            }
        }
        let manifest = try session.finish(reason: "test stop")
        let replay = try ResearchReplay.run(folder: session.folder)
        XCTAssertEqual(replay.assemblerGaps,1)
        XCTAssertEqual(replay.comparedWindows,manifest.analyzedWindows)
        XCTAssertGreaterThan(replay.comparedWindows,0)
        XCTAssertEqual(replay.mismatchedWindows,0)
        XCTAssertEqual(replay.unmatchedLiveWindows,0)
        XCTAssertTrue(replay.windows.allSatisfy { $0.poseAlignment.issue == .matched })
        let pcm = session.folder.appendingPathComponent("foa.wav")
        var data = try Data(contentsOf: pcm)
        data[data.count - 1] ^= 1
        try data.write(to: pcm)
        XCTAssertThrowsError(try ResearchReplay.run(folder: session.folder))
    }

    func testIncompleteSessionHasNoManifestAndCannotReplay() throws {
        let session = try writer(root())
        try session.appendAudio(Array(repeating: [Float](repeating: 0.1, count: 1024), count: 4), at: 100)
        session.abandon()
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.folder.appendingPathComponent("manifest.json").path))
        XCTAssertThrowsError(try ResearchReplay.run(folder: session.folder))
        let missingPose = try writer(root())
        try missingPose.appendAudio(Array(repeating: [Float](repeating: 0.1, count: 1024), count: 4), at: 100)
        XCTAssertThrowsError(try missingPose.finish(reason: "missing pose"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingPose.folder.appendingPathComponent("manifest.json").path))
    }

    func testGroundTruthLabelsDoNotChangeInferenceAndUnsafeManifestIsRejected() throws {
        let session = try writer(root())
        try session.appendPose(pose(100))
        try session.appendAudio(Array(repeating: [Float](repeating: 0, count: 4096), count: 4), at: 100)
        _ = try session.finish(reason: "test")
        let url = session.folder.appendingPathComponent("manifest.json")
        let original = try ResearchReplay.run(folder: session.folder)
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var labels = try XCTUnwrap(data["labels"] as? [String: Any])
        labels["azimuthDegrees"] = 90
        data["labels"] = labels
        try JSONSerialization.data(withJSONObject: data).write(to: url)
        let changed = try ResearchReplay.run(folder: session.folder)
        XCTAssertEqual(try DiagnosticExport.encoder().encode(original.windows), try DiagnosticExport.encoder().encode(changed.windows))
        var files = try XCTUnwrap(data["files"] as? [[String: Any]])
        files[0]["name"] = "../escape.wav"
        data["files"] = files
        try JSONSerialization.data(withJSONObject: data).write(to: url)
        XCTAssertThrowsError(try ResearchReplay.run(folder: session.folder))
    }
}
