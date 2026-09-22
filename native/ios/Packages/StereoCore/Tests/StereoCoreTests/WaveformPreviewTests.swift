import XCTest
@testable import StereoCore

final class WaveformPreviewTests: XCTestCase {
    func testChannelsShareScaleWithoutLosingLevelDifference() throws {
        let left: [Float] = (0..<480).map { $0.isMultiple(of: 2) ? 0.8 : -0.8 }
        let preview = try XCTUnwrap(StereoWaveformPreview.make(left: left, right: left.map { $0 / 4 }, sampleRate: 48_000))
        XCTAssertEqual(preview.amplitudeRange, 0.8)
        XCTAssertEqual(preview.left.first?.maximum, 0.8)
        XCTAssertEqual(preview.right.first?.maximum, 0.2)
        XCTAssertEqual(preview.left.first?.minimum, -0.8)
        XCTAssertEqual(preview.right.first?.minimum, -0.2)
    }

    func testLatestWindowPreservesTransientIncludingLastSample() throws {
        for rate in [44_100.0, 48_000.0, 96_000.0] {
            var left = [Float](repeating: 0, count: 4800)
            let right = [Float](repeating: 0, count: 4800)
            left[0] = 1 // Outside the displayed latest 10 ms.
            left[4799] = -0.25
            let preview = try XCTUnwrap(StereoWaveformPreview.make(left: left, right: right, sampleRate: rate))
            XCTAssertEqual(preview.left.count, 96)
            XCTAssertEqual(preview.right.count, 96)
            XCTAssertEqual(preview.durationSeconds, 0.01, accuracy: 1e-9)
            XCTAssertEqual(preview.amplitudeRange, 0.25)
            XCTAssertEqual(preview.left.last?.minimum, -0.25)
            XCTAssertEqual(preview.left.map(\.maximum).max(), 0)
        }
    }

    func testSilenceAndShortBuffersRemainFiniteAndBounded() throws {
        let silent = [Float](repeating: 0, count: 128)
        let preview = try XCTUnwrap(StereoWaveformPreview.make(left: silent, right: silent, sampleRate: 96_000))
        XCTAssertEqual(preview.amplitudeRange, 0.001)
        XCTAssertEqual(preview.durationSeconds, 128 / 96_000.0, accuracy: 1e-9)
        XCTAssertTrue((preview.left + preview.right).allSatisfy { $0.minimum == 0 && $0.maximum == 0 })
        XCTAssertLessThanOrEqual(preview.left.count, 96)
    }

    func testMalformedInputDoesNotProduceDisplayCoordinates() {
        let valid = [Float](repeating: 0, count: 480)
        XCTAssertNil(StereoWaveformPreview.make(left: [], right: [], sampleRate: 48_000))
        XCTAssertNil(StereoWaveformPreview.make(left: valid, right: [], sampleRate: 48_000))
        XCTAssertNil(StereoWaveformPreview.make(left: valid, right: valid, sampleRate: .nan))
        XCTAssertNil(StereoWaveformPreview.make(left: valid, right: valid, sampleRate: 0))
        var invalid = valid; invalid[12] = .infinity
        XCTAssertNil(StereoWaveformPreview.make(left: invalid, right: valid, sampleRate: 48_000))
    }
}
