import XCTest
@testable import StereoCore

final class FOAAnalysisTests: XCTestCase {
    private func plane(_ vector: Vector3, hz: Double=750, gain: Double=0.1) -> [[Float]] {
        [1,vector.y,vector.z,vector.x].map { factor in
            (0..<4096).map { Float(gain*factor*sin(2 * .pi*hz*Double($0)/48000)) }
        }
    }
    private func sum(_ a: [[Float]], _ b: [[Float]]) -> [[Float]] {
        zip(a,b).map { zip($0,$1).map(+) }
    }
    func testAxesAndZeroDipolesAreValid() throws {
        for vector in [Vector3(1,0,0),.init(-1,0,0),.init(0,1,0),.init(0,-1,0),.init(0,0,1),.init(0,0,-1),.init(0.3,0.4,0.5).normalized()] {
            let analysis=FOAAnalyzer.analyze(plane(vector),sampleRate: 48000)
            XCTAssertEqual(analysis.state,"candidate")
            let region=try XCTUnwrap(analysis.regions.first)
            XCTAssertLessThan(region.direction.angle(to: vector),0.001)
            XCTAssertEqual(try XCTUnwrap(region.dominantHz),750,accuracy: 48000/4096)
            XCTAssertFalse(analysis.physicalAccuracyVerified)
        }
    }
    func testSeparateFrequenciesDoNotCollapseToFalseMiddle() throws {
        let a=Vector3(0.5,sqrt(0.75),0), b=Vector3(0.5,-sqrt(0.75),0)
        let result=FOAAnalyzer.analyze(sum(plane(a),plane(b,hz: 2250)),sampleRate: 48000)
        XCTAssertEqual(result.regions.count,2)
        XCTAssertLessThan(try XCTUnwrap(result.regions.first { $0.band==1 }).direction.angle(to: a),0.1)
        XCTAssertLessThan(try XCTUnwrap(result.regions.first { $0.band==2 }).direction.angle(to: b),0.1)
    }
    func testQuietInvalidClippedAndCopiedMonoAreNotDirections() {
        let silent=Array(repeating: [Float](repeating: 0,count: 4096),count: 4)
        XCTAssertEqual(FOAAnalyzer.analyze(silent,sampleRate: 48000).state,"quiet")
        XCTAssertEqual(FOAAnalyzer.analyze(Array(silent.prefix(2)),sampleRate: 48000).state,"invalidPCM")
        var invalid=silent; invalid[0][0] = .nan
        XCTAssertEqual(FOAAnalyzer.analyze(invalid,sampleRate: 48000).state,"invalidPCM")
        invalid[0][0]=1
        XCTAssertEqual(FOAAnalyzer.analyze(invalid,sampleRate: 48000).state,"clipped")
        let mono=plane(.init(1,0,0))[0]
        XCTAssertTrue(FOAAnalyzer.analyze(Array(repeating: mono,count: 4),sampleRate: 48000).regions.isEmpty)
    }
    func testOppositeCoherentSourcesCancelAndReflectionCanStillBias() throws {
        XCTAssertTrue(FOAAnalyzer.analyze(sum(plane(.init(1,0,0)),plane(.init(-1,0,0))),sampleRate: 48000).regions.isEmpty)
        let biased=FOAAnalyzer.analyze(sum(plane(.init(1,0,0)),plane(.init(0,1,0),gain: 0.14)),sampleRate: 48000)
        let region=try XCTUnwrap(biased.regions.first)
        XCTAssertGreaterThan(region.direction.angle(to: .init(1,0,0)),50)
        XCTAssertGreaterThan(region.coherence,0.99)
        XCTAssertFalse(biased.physicalAccuracyVerified)
    }
    func testAssemblerKeepsSampleTimeAndRejectsGaps() throws {
        var assembler=PCMWindowAssembler(channels: 4)
        let block=Array(repeating: [Float](repeating: 0.1,count: 1024),count: 4)
        for i in 0..<3 { XCTAssertTrue(assembler.append(block,at: 10+Double(i*1024)/48000,sampleRate: 48000).isEmpty) }
        let window=try XCTUnwrap(assembler.append(block,at: 10+3072.0/48000,sampleRate: 48000).first)
        XCTAssertEqual(window.start,10,accuracy: 1e-9)
        XCTAssertEqual(window.channels[0].count,4096)
        XCTAssertTrue(assembler.append(block,at: 12,sampleRate: 48000).isEmpty)
        XCTAssertEqual(assembler.gaps,1)
        XCTAssertTrue(assembler.append(block,at: .nan,sampleRate: 48000).isEmpty)
        XCTAssertEqual(assembler.gaps,2)
    }
}
