import XCTest
@testable import StereoCore

final class FOAStabilityTests: XCTestCase {
    private func plane(_ vector: Vector3 = .init(1,0,0)) -> FOAAnalysis {
        let channels=[1,vector.y,vector.z,vector.x].map { gain in
            (0..<4096).map { Float(0.08*gain*sin(2 * .pi*750*Double($0)/48000)) }
        }
        return FOAAnalyzer.analyze(channels,sampleRate: 48000)
    }
    private func ambiguous() -> FOAAnalysis {
        let w=(0..<4096).map { Float(0.08*sin(2 * .pi*750*Double($0)/48000)) }
        let v=(0..<4096).map { Float(0.08*sin(2 * .pi*750*Double($0)/48000 + .pi/3)) }
        let zero=Array(repeating: Float(0),count: 4096)
        return FOAAnalyzer.analyze([w,zero,zero,v],sampleRate: 48000)
    }
    private func pose(_ time: Double, turned: Bool=false) -> SpatialPose {
        .init(time: time,origin: .zero,right: turned ? .init(0,0,1) : .init(1,0,0),
              up: .init(0,1,0),forward: turned ? .init(1,0,0) : .init(0,0,-1))
    }
    private func feed(_ tracker: inout FOADirectionStabilizer, _ analysis: FOAAnalysis, _ time: Double, turned: Bool=false) {
        tracker.observe(analysis,pose: pose(time,turned: turned),at: time,now: time+0.05)
    }
    func testIsolatedAndAlternatingCandidatesNeverFlash() {
        let valid=plane(), rejected=ambiguous()
        XCTAssertEqual(rejected.state,"ambiguous")
        var tracker=FOADirectionStabilizer()
        for i in 0..<24 {
            feed(&tracker,i%2==0 ? valid : rejected,10+Double(i)*0.085)
            XCTAssertTrue(tracker.regions.isEmpty)
        }
    }
    func testConfirmedDirectionBridgesOneRejectedFrameButExpires() throws {
        let valid=plane(), rejected=ambiguous()
        var tracker=FOADirectionStabilizer()
        for i in 0..<3 { feed(&tracker,valid,10+Double(i)*0.085) }
        XCTAssertEqual(tracker.regions.count,1)
        feed(&tracker,rejected,10.255)
        XCTAssertTrue(try XCTUnwrap(tracker.regions.first).recentOnly)
        XCTAssertEqual(tracker.state,"rechecking")
        XCTAssertEqual(tracker.regions.first?.lastObserved,10.17)
        feed(&tracker,valid,10.34)
        XCTAssertEqual(tracker.state,"candidate")
        XCTAssertFalse(try XCTUnwrap(tracker.regions.first).recentOnly)
        feed(&tracker,rejected,10.425)
        tracker.refresh(at: 10.621)
        XCTAssertTrue(tracker.regions.isEmpty)
    }
    func testOppositeDirectionsDoNotBlendAndCameraRotationKeepsWorldDirection() throws {
        var tracker=FOADirectionStabilizer()
        let valid=plane()
        for i in 0..<3 { feed(&tracker,valid,10+Double(i)*0.085) }
        let old=try XCTUnwrap(tracker.regions.first).worldDirection
        // Device turned; encoded Y maps to the same world direction.
        feed(&tracker,plane(.init(0,1,0)),10.255,turned: true)
        XCTAssertEqual(tracker.regions.count,1)
        XCTAssertLessThan(try XCTUnwrap(tracker.regions.first).worldDirection.angle(to: old),0.001)
        feed(&tracker,plane(.init(-1,0,0)),10.34)
        XCTAssertTrue(tracker.regions.isEmpty)
        XCTAssertEqual(tracker.state,"confirming")
    }
    func testQuietClippedLostPoseAndStaleInputClearImmediately() {
        let valid=plane()
        let quiet=FOAAnalyzer.analyze(Array(repeating: Array(repeating: Float(0),count: 4096),count: 4),sampleRate: 48000)
        var clipped=Array(repeating: Array(repeating: Float(0),count: 4096),count: 4); clipped[0][0]=1
        for invalid in [quiet,FOAAnalyzer.analyze(clipped,sampleRate: 48000)] {
            var tracker=FOADirectionStabilizer()
            for i in 0..<3 { feed(&tracker,valid,10+Double(i)*0.085) }
            feed(&tracker,invalid,10.255)
            XCTAssertTrue(tracker.regions.isEmpty)
        }
        var tracker=FOADirectionStabilizer()
        for i in 0..<3 { feed(&tracker,valid,10+Double(i)*0.085) }
        tracker.clear(state: "poseUnavailable")
        XCTAssertTrue(tracker.regions.isEmpty)
        tracker.observe(valid,pose: pose(10.3),at: 10.3,now: 11)
        XCTAssertTrue(tracker.regions.isEmpty)
    }
    func testTimelineKeepsSubsecondTimesRejectionDetailsAndRetentionCounts() throws {
        let valid=plane(), rejected=ambiguous()
        var history=FOADiagnosticTimeline(uptime: 100,date: Date(timeIntervalSince1970: 0),capacity: 2)
        history.append(valid,midpoint: 100.125,duration: 0.085,poseIssue: "matched",displayState: "confirming")
        history.append(rejected,midpoint: 100.25,duration: 0.085,poseIssue: "movementDuringAudio",displayState: "poseUnavailable")
        history.append(valid,midpoint: 100.375,duration: 0.085,poseIssue: "matched",displayState: "confirming")
        let first=try XCTUnwrap(history.history.first)
        XCTAssertEqual(first.timestampUTC,"1970-01-01T00:00:00.250Z")
        XCTAssertEqual(first.elapsedSeconds,0.125,accuracy: 1e-9)
        XCTAssertEqual(history.history.map(\.sequence),[2,3])
        XCTAssertEqual(history.omittedEarlierEntries,1)
        XCTAssertEqual(history.acousticStateCounts["candidate"],2)
        XCTAssertFalse(history.failedCheckCounts.isEmpty)
        XCTAssertNoThrow(try DiagnosticExport.encoder().encode(history))
    }
    func testRepeatedCurrentAndHistoricalExportsAreUniqueAndKeepMeasurementTimes() throws {
        let date=Date(timeIntervalSince1970: 0.125), sessionID=UUID(), a=UUID(), b=UUID()
        let first=DiagnosticExport.fileName(date: date,sessionID: sessionID,exportID: a)
        let second=DiagnosticExport.fileName(date: date,sessionID: sessionID,exportID: b)
        XCTAssertNotEqual(first,second)
        XCTAssertTrue(first.contains("19700101T000000.125Z"))
        XCTAssertFalse(first.contains(":"))
        let original=Data("{\"startedAt\":\"2026-09-24T00:18:43Z\",\"schemaVersion\":10}".utf8)
        for historical in [false,true] {
            let data=try DiagnosticExport.envelope(original,at: date,exportID: a,historical: historical)
            let object=try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String:Any])
            XCTAssertEqual(object["startedAt"] as? String,"2026-09-24T00:18:43Z")
            XCTAssertEqual(object["exportedAt"] as? String,"1970-01-01T00:00:00.125Z")
            XCTAssertEqual(object["exportID"] as? String,a.uuidString)
            XCTAssertEqual(object["historicalReport"] as? Bool,historical)
        }
    }
    func testSingleToneWithAntiphaseReflectionCanExceedRatioWithoutN3D() throws {
        // Standard SN3D direct + opposite, phase-inverted reflection. Not an Apple normalization defect.
        let a=0.276
        let s=(0..<4096).map { Float(0.08*sin(2 * .pi*750*Double($0)/48000)) }
        let zero=Array(repeating: Float(0),count: 4096)
        let analysis=FOAAnalyzer.analyze([s.map { $0*Float(1-a) },zero,zero,s.map { $0*Float(1+a) }],sampleRate: 48000)
        let band=try XCTUnwrap(analysis.bandDiagnostics.first { $0.band==1 })
        XCTAssertGreaterThan(try XCTUnwrap(band.directionalToOmniEnergy),3)
        XCTAssertTrue(band.failedChecks.contains("energyRatioOutsideModel"))
        XCTAssertGreaterThan(try XCTUnwrap(band.coherence),0.99)
        XCTAssertTrue(analysis.regions.isEmpty)
    }
}
