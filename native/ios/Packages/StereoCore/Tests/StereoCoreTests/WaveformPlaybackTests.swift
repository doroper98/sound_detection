import XCTest
@testable import StereoCore

final class WaveformPlaybackTests: XCTestCase {
    func testHundredMillisecondBufferProducesSixActualStereoWindows() throws {
        let left: [Float] = (0..<4800).map { Float($0 / 800 + 1) / 10 }
        let batch = WaveformBatch.make(left: left, right: left.map { -$0 / 2 }, sampleRate: 48_000, startTimeSeconds: 10)
        XCTAssertEqual(batch.count, 6)
        for (i, frame) in batch.enumerated() {
            XCTAssertEqual(frame.endTimeSeconds, 10 + Double(i + 1) / 60, accuracy: 1e-9)
            XCTAssertEqual(frame.preview.left.last!.maximum, Float(i + 1) / 10, accuracy: 1e-6)
            XCTAssertEqual(frame.preview.right.last!.minimum, -Float(i + 1) / 20, accuracy: 1e-6)
            XCTAssertEqual(frame.preview.durationSeconds, 0.01, accuracy: 1e-9)
        }
    }

    func testBatchedInputProducesMoreThanTenFreshFramesPerSecondWithoutInterpolation() {
        let pcm = [Float](repeating: 0.1, count: 4800)
        var playback = WaveformPlayback(), seen: Set<Double> = []
        for tick in 0...240 {
            let now = Double(tick) / 120
            if tick > 0 && tick.isMultiple(of: 12) {
                playback.append(WaveformBatch.make(left: pcm, right: pcm, sampleRate: 48_000,
                    startTimeSeconds: now - 0.1), bufferDuration: 0.1)
            }
            if tick.isMultiple(of: 2), let frame = playback.frame(at: now) { seen.insert(frame.endTimeSeconds) }
        }
        XCTAssertGreaterThan(seen.count, 90)
        XCTAssertGreaterThan(playback.statistics(at: 2).recentFreshFPS, 45)
        XCTAssertLessThanOrEqual(playback.statistics(at: 2).recentFreshFPS, 60)
    }

    func testQueueBoundLateFramesStopAndStaleness() {
        let pcm = [Float](repeating: 0, count: 4800)
        var playback = WaveformPlayback()
        for i in 0..<10 {
            playback.append(WaveformBatch.make(left: pcm, right: pcm, sampleRate: 48_000,
                startTimeSeconds: Double(i) / 10), bufferDuration: 0.1)
        }
        XCTAssertEqual(playback.statistics(at: 1).pendingFrames, 24)
        XCTAssertGreaterThan(playback.statistics(at: 1).discardedFrames, 0)
        XCTAssertNotNil(playback.frame(at: 1.01))
        XCTAssertNil(playback.frame(at: 1.36))
        XCTAssertEqual(playback.statistics(at: 1.36).pendingFrames, 0)
        playback.clear()
        XCTAssertNil(playback.frame(at: 1.4))
    }

    func testInvalidAndVaryingBuffersStayBoundedAndPreserveSilentChannel() {
        for rate in [8_000.0, 44_100, 48_000, 96_000, 192_000] {
            let pcm = [Float](repeating: 0.2, count: 16_384)
            let batch = WaveformBatch.make(left: pcm, right: pcm.map { _ in 0 }, sampleRate: rate, startTimeSeconds: 1)
            XCTAssertFalse(batch.isEmpty)
            XCTAssertLessThanOrEqual(batch.count, 24)
            XCTAssertTrue(batch.allSatisfy { $0.preview.right.allSatisfy { $0.minimum == 0 && $0.maximum == 0 } })
        }
        XCTAssertTrue(WaveformBatch.make(left: [], right: [], sampleRate: .nan, startTimeSeconds: 0).isEmpty)
    }
}
