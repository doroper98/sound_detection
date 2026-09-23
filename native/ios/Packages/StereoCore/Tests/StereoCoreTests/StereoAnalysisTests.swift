import XCTest
@testable import StereoCore

final class StereoAnalysisTests: XCTestCase {
    private func noise(_ count: Int = 2048, seed: UInt64 = 7) -> [Float] {
        var state = seed
        return (0..<count).map { _ in
            state = state &* 6364136223846793005 &+ 1
            return Float(Double(state >> 33) / Double(UInt32.max) - 0.25)
        }
    }

    private func delayed(_ samples: [Float], by delay: Int) -> [Float] {
        samples.indices.map { i in samples.indices.contains(i - delay) ? samples[i - delay] : 0 }
    }

    func testBothLagSignsAndSampleRates() throws {
        let x = noise()
        for rate in [44_100.0, 48_000.0, 96_000.0] {
            for delay in [-11, 7] {
                let result = try StereoAnalyzer.analyze(left: x, right: delayed(x, by: delay), sampleRate: rate)
                XCTAssertEqual(result.status, .candidate)
                XCTAssertEqual(result.rightMinusLeftLagSamples, delay)
                XCTAssertEqual(try XCTUnwrap(result.rightMinusLeftLagSeconds), Double(delay) / rate, accuracy: 1e-10)
            }
        }
    }

    func testZeroLagWithSmallIndependentNoiseIsNotAutomaticallyDuplicate() throws {
        let x = noise(), extra = noise(seed: 19)
        let y = zip(x, extra).map { $0 + 0.02 * $1 }
        let result = try StereoAnalyzer.analyze(left: x, right: y, sampleRate: 48_000)
        XCTAssertFalse(result.duplicateSuspected)
        XCTAssertEqual(result.status, .candidate)
        XCTAssertEqual(result.rightMinusLeftLagSamples, 0)
    }

    func testSilentSecondChannelAndDCOnlySuppressLag() throws {
        for y in [Array(repeating: Float(0), count: 2048), Array(repeating: Float(0.1), count: 2048)] {
            let result = try StereoAnalyzer.analyze(left: noise(), right: y, sampleRate: 48_000)
            XCTAssertEqual(result.status, .silentChannel)
            XCTAssertNil(result.rightMinusLeftLagSamples)
        }
    }

    func testIdenticalScaledAndInvertedCopiesSuppressLag() throws {
        let x = noise()
        for gain: Float in [1, 0.5, -1] {
            let result = try StereoAnalyzer.analyze(left: x, right: x.map { gain * $0 }, sampleRate: 48_000)
            XCTAssertEqual(result.status, .duplicate)
            XCTAssertNil(result.rightMinusLeftLagSeconds)
        }
    }

    func testPeriodicSignalIsAmbiguous() throws {
        let x = (0..<2400).map { Float(0.2 * sin(2 * .pi * 2000 * Double($0) / 48_000)) }
        let result = try StereoAnalyzer.analyze(left: x, right: delayed(x, by: 3), sampleRate: 48_000)
        XCTAssertEqual(result.status, .ambiguous)
        XCTAssertNil(result.rightMinusLeftLagSeconds)
    }

    func testClippingAndUnrelatedNoiseSuppressLag() throws {
        var x = noise()
        let unrelated = try StereoAnalyzer.analyze(left: x, right: noise(seed: 99), sampleRate: 48_000)
        XCTAssertEqual(unrelated.status, .weakCorrelation)
        x[10] = 1
        let clipped = try StereoAnalyzer.analyze(left: x, right: delayed(x, by: 6), sampleRate: 48_000)
        XCTAssertEqual(clipped.status, .clipped)
        XCTAssertNil(clipped.rightMinusLeftLagSeconds)
    }

    func testSearchBoundaryIsRejected() throws {
        let x = noise()
        let result = try StereoAnalyzer.analyze(left: x, right: delayed(x, by: 48), sampleRate: 48_000)
        XCTAssertEqual(result.status, .searchBoundary)
        XCTAssertNil(result.rightMinusLeftLagSamples)
    }

    func testDigitalLevelScalesBy20dB() throws {
        let x = noise(), y = delayed(x, by: 4)
        let a = try StereoAnalyzer.analyze(left: x, right: y, sampleRate: 48_000)
        let b = try StereoAnalyzer.analyze(left: x.map { $0 * 0.1 }, right: y.map { $0 * 0.1 }, sampleRate: 48_000)
        XCTAssertEqual(try XCTUnwrap(b.channels[0].rmsDbfs) - XCTUnwrap(a.channels[0].rmsDbfs), -20, accuracy: 1e-5)
    }

    func testInvalidFramesAreRejected() {
        XCTAssertThrowsError(try StereoAnalyzer.analyze(left: noise(), right: [], sampleRate: 48_000))
        XCTAssertThrowsError(try StereoAnalyzer.analyze(left: noise(), right: noise(), sampleRate: .nan))
        XCTAssertThrowsError(try StereoAnalyzer.analyze(left: [.nan] + noise(2047), right: noise(), sampleRate: 48_000))
        XCTAssertThrowsError(try StereoAnalyzer.analyze(left: noise(16385), right: noise(16385), sampleRate: 48_000))
    }

    func testSilenceJSONUsesNullAndHasNoSamples() throws {
        let zero = Array(repeating: Float(0), count: 2048)
        let result = try StereoAnalyzer.analyze(left: zero, right: zero, sampleRate: 48_000)
        XCTAssertNil(result.channels[0].rmsDbfs)
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(StereoAnalysis.self, from: data)
        XCTAssertEqual(decoded.status, .silentChannel)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("NaN"))
        XCTAssertFalse(json.contains("Infinity"))
        XCTAssertFalse(json.contains("microphonePositions"))
    }
}
