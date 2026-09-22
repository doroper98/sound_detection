import XCTest
@testable import StereoCore

final class SpatialInferenceTests: XCTestCase {
    private func pose(_ time: Double, _ origin: Vector3 = .zero, yaw: Double = 0, roll: Double = 0) -> SpatialPose {
        let y=yaw * .pi/180, r=roll * .pi/180
        let right=Vector3(cos(y),0,sin(y)), up=Vector3(0,1,0), forward=Vector3(sin(y),0,-cos(y))
        return .init(time: time,origin: origin,right: right*cos(r)+up*sin(r),
            up: up*cos(r)-right*sin(r),forward: forward)
    }
    private func feature(_ angle: Double, lag: Bool = true, noise: Double = 0) -> AcousticFeatures {
        .init(sampleRate: 48000,levelDbfs: -24,differenceDb: 0.2*angle+1+noise,
            lagSamples: lag ? 0.4*angle+2 : nil,shape: [0.1,0.2,0.7])
    }
    private func groups(sign: Double = 1, lag: Bool = true) -> [[RotationCalibrationSample]] {
        RotationCalibrator.targets.enumerated().map { step,angle in
            (0..<25).map { i in .init(angle: angle,features: feature(angle*sign,lag: lag,noise: Double(i%3-1)*0.04),time: Double(step*30+i)/10) }
        }
    }
    func testEmpiricalFitUsesMeasuredSignAndRejectsOutOfRangeAndDifferentSpectrum() throws {
        let p=try XCTUnwrap(RotationCalibrator.fit(groups(sign: -1)))
        let result=try XCTUnwrap(p.estimate(feature(-12),at: 1))
        XCTAssertEqual(result.degrees,12,accuracy: 0.3)
        XCTAssertGreaterThanOrEqual(result.uncertaintyDegrees,4)
        XCTAssertNil(p.estimate(feature(-40),at: 1))
        XCTAssertNil(p.estimate(.init(sampleRate: 48000,levelDbfs: -24,differenceDb: -1.4,lagSamples: -2.8,shape: [0.8,0.1,0.1]),at: 1))
        XCTAssertNil(p.estimate(.init(sampleRate: 44100,levelDbfs: -24,differenceDb: -1.4,lagSamples: -2.8,shape: [0.1,0.2,0.7]),at: 1))
    }
    func testAmbiguousLagCanUseRepeatedLevelResponseButConstantResponseCannotCalibrate() throws {
        let p=try XCTUnwrap(RotationCalibrator.fit(groups(lag: false)))
        XCTAssertEqual(p.responses.count,1)
        XCTAssertEqual(p.responses.first?.method,"levelDifference")
        XCTAssertEqual(try XCTUnwrap(p.estimate(feature(8,lag: false),at: 1)).degrees,8,accuracy: 0.3)
        let flat=groups().map { $0.map { RotationCalibrationSample(angle: $0.angle,features: feature(0),time: $0.time) } }
        XCTAssertNil(RotationCalibrator.fit(flat))
    }
    func testUnrepeatableCalibrationAndConflictingFeaturesAreRejected() throws {
        var rows=groups()
        rows[4]=rows[4].map { .init(angle: $0.angle,features: feature(20),time: $0.time) }
        XCTAssertNil(RotationCalibrator.fit(rows))
        let p=try XCTUnwrap(RotationCalibrator.fit(groups()))
        XCTAssertNil(p.estimate(.init(sampleRate: 48000,levelDbfs: -24,differenceDb: 5,lagSamples: -6,shape: [0.1,0.2,0.7]),at: 1))
    }
    func testSixGuidedRotationsReachProfileOnlyWithFixedOriginAndCoverage() {
        var c=RotationCalibrator()
        c.begin(pose: pose(1))
        var time=1.0
        for target in RotationCalibrator.targets {
            for _ in 0..<28 {
                time+=0.1
                c.append(features: feature(target),pose: pose(time,yaw: -target))
            }
        }
        XCTAssertEqual(c.snapshot().phase,"ready")
        XCTAssertNotNil(c.profile)
        c.begin(pose: pose(time+1))
        for i in 0..<30 { c.append(features: feature(0),pose: pose(time+1+Double(i)*0.1,.init(0.1,0,0))) }
        XCTAssertEqual(c.snapshot().step,0)
        XCTAssertEqual(c.snapshot().progress,0)
        c.cancel("test")
        XCTAssertFalse(c.active)
        XCTAssertNil(c.profile)
    }
    func testPoseAlignmentRejectsStaleFastMovementAndIncorrectAxes() {
        var history=SpatialPoseHistory()
        for i in 0..<12 { history.append(pose(Double(i)/30)) }
        XCTAssertNotNil(history.aligned(midpoint: 0.2,duration: 0.1))
        XCTAssertNil(history.aligned(midpoint: 1,duration: 0.1))
        history.append(pose(0.4,.init(1,0,0)))
        XCTAssertNil(history.aligned(midpoint: 0.38,duration: 0.1))
        XCTAssertFalse(SpatialPose(time: 0,origin: .zero,right: .init(1,0,0),up: .init(1,0,0),forward: .init(0,0,-1)).valid)
    }
    func testContinuousBearingHidesStaleOrInvalidInput() {
        let p=RotationCalibrator.fit(groups())!
        var t=BearingTracker()
        for i in 0..<5 { t.append(p.estimate(feature(10),at: Double(i)/10)) }
        XCTAssertNotNil(t.estimate(at: 0.45))
        XCTAssertNil(t.estimate(at: 0.8))
        t.append(nil)
        XCTAssertNil(t.estimate(at: 0.45))
    }
    private func observe(_ pose: SpatialPose, source: Vector3, sigma: Double = 4) -> BearingObservation {
        .init(pose: pose,angleDegrees: pose.bearing(of: source-pose.origin),uncertaintyDegrees: sigma)
    }
    func testSinglePoseRepeatsAndRotationOnlyNeverResolveRange() {
        let source=Vector3(0,0,-2)
        var a=SpatialAccumulator()
        for i in 0..<30 { a.append(observe(pose(Double(i)/10),source: source)) }
        XCTAssertEqual(a.solve(at: 2.91).observationCount,1)
        XCTAssertNil(a.solve(at: 2.91).estimate)
        a.reset()
        for i in 0..<12 { a.append(observe(pose(Double(i)/10,yaw: Double(i%5-2)*10,roll: Double(i)*10),source: source)) }
        XCTAssertNil(a.solve(at: 1.11).estimate)
    }
    func testLevelPhoneTranslationsCannotInventHeight() {
        var a=SpatialAccumulator()
        let source=Vector3(0,0.3,-2)
        for i in 0..<12 { a.append(observe(pose(Double(i)/10,.init(Double(i)*0.1-0.55,0,0)),source: source)) }
        XCTAssertEqual(a.solve(at: 1.11).state,"needTiltOrParallax")
    }
    func testDiverseTranslatedTiltedPlanesRecoverSyntheticPoint() throws {
        var a=SpatialAccumulator()
        let source=Vector3(0.1,0.15,-1.6)
        for i in 0..<24 {
            let origin=Vector3(Double(i%8)*0.13-0.45,Double(i/8)*0.1,Double(i%3)*0.04)
            a.append(observe(pose(Double(i)/10,origin,roll: Double(i/8-1)*35),source: source))
        }
        let solution=a.solve(at: 2.31)
        let estimate=try XCTUnwrap(solution.estimate,solution.state)
        XCTAssertLessThan((estimate.point-source).length,0.001)
        XCTAssertGreaterThan(estimate.uncertaintyRadiusMeters,0)
        XCTAssertGreaterThan(estimate.baselineMeters,0.3)
        XCTAssertNil(a.solve(at: 3).estimate)
        a.reset(); XCTAssertNil(a.solve(at: 3).estimate)
    }
    func testContradictoryMovingSourceCannotProduceConfidentPoint() {
        var a=SpatialAccumulator()
        for i in 0..<24 {
            let source=Vector3(i.isMultiple(of: 2) ? -0.5 : 0.5,0.3,-1.6)
            let p=pose(Double(i)/10,.init(Double(i%8)*0.12-0.4,0,0),roll: Double(i/8-1)*35)
            a.append(observe(p,source: source))
        }
        XCTAssertNil(a.solve(at: 2.31).estimate)
    }
    func testAcousticFeaturesRejectSilenceDuplicatesAndClipping() throws {
        let silence=[Float](repeating: 0,count: 4800)
        let silent=try StereoAnalyzer.analyze(left: silence,right: silence,sampleRate: 48000)
        XCTAssertNil(AcousticFeatures.measure(left: silence,right: silence,analysis: silent))
        let tone=(0..<4800).map { Float(sin(Double($0)*0.4)*0.1) }
        let duplicate=try StereoAnalyzer.analyze(left: tone,right: tone,sampleRate: 48000)
        XCTAssertNil(AcousticFeatures.measure(left: tone,right: tone,analysis: duplicate))
    }
}
