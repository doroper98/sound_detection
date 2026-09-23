import XCTest
@testable import StereoCore

final class SoundSpectrumTests: XCTestCase {
    private func tone(_ hz: Double,rate: Double=48000,amplitude: Double=0.1) -> [Float] {
        (0..<4800).map { Float(amplitude*sin(2 * .pi*hz*Double($0)/rate)) }
    }
    func testToneFrequencyAcrossRatesAndAmplitude() throws {
        for rate in [44100.0,48000] {
            for hz in [120.0,997,3150,12000] {
                let samples=tone(hz,rate: rate)
                let result=try XCTUnwrap(SoundSpectrumAnalyzer.measure(left: samples,right: samples,sampleRate: rate))
                XCTAssertEqual(try XCTUnwrap(result.dominantHz),hz,accuracy: result.binWidthHz)
                XCTAssertEqual(result.fftSize,4096)
                XCTAssertEqual(result.levelDbfs,20*log10(0.1/sqrt(2)),accuracy: 0.12)
            }
        }
    }
    func testOppositePhaseChannelsRetainFrequencyAndLevel() throws {
        let left=tone(1000), right=left.map { -$0 }
        let result=try XCTUnwrap(SoundSpectrumAnalyzer.measure(left: left,right: right,sampleRate: 48000))
        XCTAssertEqual(try XCTUnwrap(result.dominantHz),1000,accuracy: result.binWidthHz)
        XCTAssertEqual(result.levelDbfs,-23.01,accuracy: 0.05)
    }
    func testTenfoldAmplitudeChangesLevelByTwentyDecibels() throws {
        let loud=tone(1000), quiet=tone(1000,amplitude: 0.01)
        let a=try XCTUnwrap(SoundSpectrumAnalyzer.measure(left: loud,right: loud,sampleRate: 48000))
        let b=try XCTUnwrap(SoundSpectrumAnalyzer.measure(left: quiet,right: quiet,sampleRate: 48000))
        XCTAssertEqual(a.levelDbfs-b.levelDbfs,20,accuracy: 0.01)
        XCTAssertEqual(a.dominantHz,b.dominantHz)
        XCTAssertGreaterThan(SoundHeatLevel.normalized(a.levelDbfs),SoundHeatLevel.normalized(b.levelDbfs))
        XCTAssertEqual(SoundHeatLevel.normalized(-80),0)
        XCTAssertEqual(SoundHeatLevel.normalized(0),1)
    }
    func testBroadbandNoiseGetsBandInsteadOfArbitraryFrequency() throws {
        var state: UInt64=91
        let samples: [Float]=(0..<4800).map { _ in
            state=state &* 6364136223846793005 &+ 1
            return Float(Double(state>>33)/Double(UInt32.max)-0.25)
        }
        let result=try XCTUnwrap(SoundSpectrumAnalyzer.measure(left: samples,right: samples,sampleRate: 48000))
        XCTAssertNil(result.dominantHz)
        XCTAssertGreaterThan(result.upperHz-result.lowerHz,8000)
        XCTAssertTrue(result.frequencyLabel.hasPrefix("대역"))
    }
    func testSilenceDCClippingAndInvalidInputDoNotMakeHeat() {
        let zero=[Float](repeating: 0,count: 4800), dc=[Float](repeating: 0.2,count: 4800)
        XCTAssertNil(SoundSpectrumAnalyzer.measure(left: zero,right: zero,sampleRate: 48000))
        XCTAssertNil(SoundSpectrumAnalyzer.measure(left: dc,right: dc,sampleRate: 48000))
        XCTAssertNil(SoundSpectrumAnalyzer.measure(left: tone(1000,amplitude: 1),right: zero,sampleRate: 48000))
        XCTAssertNil(SoundSpectrumAnalyzer.measure(left: tone(1000),right: zero,sampleRate: .nan))
        XCTAssertNil(SoundSpectrumAnalyzer.measure(left: [Float.nan],right: [.nan],sampleRate: 48000))
        XCTAssertNil(SoundSpectrumAnalyzer.measure(left: Array(zero.prefix(32)),right: zero,sampleRate: 48000))
    }
    func testStrongestSpectralComponentAndNyquistBoundary() throws {
        let a=tone(1000), b=tone(4000,amplitude: 0.025)
        let mix=zip(a,b).map { $0+$1 }
        let result=try XCTUnwrap(SoundSpectrumAnalyzer.measure(left: mix,right: mix,sampleRate: 48000))
        XCTAssertEqual(try XCTUnwrap(result.dominantHz),1000,accuracy: result.binWidthHz)
        let lowRate=tone(3500,rate: 8000)
        let low=try XCTUnwrap(SoundSpectrumAnalyzer.measure(left: lowRate,right: lowRate,sampleRate: 8000))
        XCTAssertLessThanOrEqual(low.upperHz,4000)
        XCTAssertEqual(try XCTUnwrap(low.dominantHz),3500,accuracy: low.binWidthHz)
    }
}
