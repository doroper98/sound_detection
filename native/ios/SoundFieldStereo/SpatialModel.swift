import SwiftUI
import StereoCore

struct SpatialReport: Encodable {
    var state="idle"
    var calibration=RotationCalibrator().snapshot()
    var bearing: BearingEstimate?
    var solution: SpatialSolution?
    var lastCandidate: SpatialEstimate?
    var lastBearing: BearingEstimate?
    var latestPose: SpatialPose?
    var acceptedFrames=0
    var rejectedFrames=0
    var trackingAvailable=false
    let coordinateSystem="ARKit session-local meters; portrait view right/up/forward. No saved world map."
    let assumption="One stationary broadband source in front, same source/room as calibration. Experimental empirical bearing/plane intersection; physical accuracy unverified."
}

@MainActor
final class SpatialModel: ObservableObject {
    @Published private(set) var report=SpatialReport()
    private var calibrator=RotationCalibrator()
    private var tracker=BearingTracker()
    private var accumulator=SpatialAccumulator()
    private var running=false
    private var lastAccepted=0.0
    var active: Bool { running }

    func start() {
        calibrator=RotationCalibrator(); tracker=BearingTracker(); accumulator=SpatialAccumulator()
        report=SpatialReport(); running=true; lastAccepted=0
        report.state="needsCalibration"
    }
    func beginCalibration(pose: SpatialPose) {
        guard running else { return }
        tracker=BearingTracker(); accumulator.reset()
        calibrator.begin(pose: pose)
        report.lastBearing=nil; report.lastCandidate=nil
        report.bearing=nil; report.solution=nil; report.calibration=calibrator.snapshot(); report.state="calibrating"
    }
    func prepareAlignment() {
        guard running else { return }
        cancelCalibration()
        report.state="alignSource"
    }
    func cancelCalibration() {
        calibrator.cancel("보정을 취소했습니다. 소리를 중앙에 맞추고 다시 시작하세요.")
        tracker=BearingTracker(); accumulator.reset()
        report.bearing=nil; report.solution=nil; report.calibration=calibrator.snapshot(); report.state="needsCalibration"
    }
    func resetMap() {
        accumulator.reset(); report.solution=nil; report.lastCandidate=nil
    }
    func trackingLost() {
        guard running else { return }
        tracker=BearingTracker(); accumulator.reset()
        if calibrator.active { calibrator.cancel("AR 추적이 중단되어 보정을 취소했습니다. 중앙 정렬부터 다시 시작하세요.") }
        report.bearing=nil; report.solution=nil; report.latestPose=nil; report.trackingAvailable=false
        report.calibration=calibrator.snapshot(); report.state="trackingLost"
    }
    func accept(features: AcousticFeatures?, pose: SpatialPose?, midpoint: Double) {
        guard running else { return }
        var next=report
        defer { report=next }
        let now=ProcessInfo.processInfo.systemUptime
        guard midpoint.isFinite, now-midpoint >= -0.06, now-midpoint<0.3, let pose else {
            next.rejectedFrames+=1; next.bearing=nil; next.solution=nil; next.latestPose=nil
            tracker=BearingTracker()
            return
        }
        next.latestPose=pose; next.trackingAvailable=true
        if next.state=="alignSource" { return }
        if calibrator.active {
            calibrator.append(features: features,pose: pose)
            next.calibration=calibrator.snapshot(); next.state=calibrator.profile == nil ? "calibrating" : "listening"
            next.bearing=nil; next.solution=nil; return
        }
        guard let profile=calibrator.profile else { next.state="needsCalibration"; return }
        let raw=features.flatMap { profile.estimate($0,at: midpoint) }
        tracker.append(raw)
        guard let raw, let bearing=tracker.estimate(at: now) else {
            next.rejectedFrames+=1; next.bearing=nil; next.solution=nil; next.state="signalUnreliable"; return
        }
        lastAccepted=midpoint; next.acceptedFrames+=1; next.bearing=bearing
        next.lastBearing=bearing
        // Use this buffer's bearing with this buffer's pose. The smoothed display
        // value must never be paired with a different pose for geometry.
        accumulator.append(.init(pose: pose,angleDegrees: raw.degrees,
            uncertaintyDegrees: max(raw.uncertaintyDegrees,bearing.uncertaintyDegrees)))
        let solution=accumulator.solve(at: now)
        next.solution=solution; next.state=solution.estimate == nil ? "bearing" : "positionCandidate"
        if let estimate=solution.estimate { next.lastCandidate=estimate }
    }
    func tick() {
        guard running else { return }
        let now=ProcessInfo.processInfo.systemUptime
        if report.bearing != nil, now-lastAccepted>0.35 {
            tracker=BearingTracker(); report.bearing=nil; report.solution=nil; report.state="signalUnreliable"
        }
        if now-lastAccepted>1 { accumulator.reset() }
    }
    func stop() {
        running=false; tracker=BearingTracker(); accumulator.reset()
        if calibrator.active { calibrator.cancel("수음을 중지해 보정을 취소했습니다.") }
        report.calibration=calibrator.snapshot(); report.bearing=nil; report.solution=nil
        report.latestPose=nil; report.trackingAvailable=false; report.state="stopped"
    }

    #if DEBUG
    /// UI fixture goes through the production profile fitter and estimator.
    /// Fake AR pose is never reachable in Release.
    func prepareSyntheticCalibration() {
        let groups=RotationCalibrator.targets.enumerated().map { (step,angle) in
            (0..<25).map { i in RotationCalibrationSample(angle: angle,
                features: AcousticFeatures(sampleRate: 48000,levelDbfs: -20,differenceDb: angle*0.2,
                    lagSamples: angle*0.4,shape: [0.1,0.2,0.7]),time: Double(step*30+i)/10) }
        }
        fixtureProfile=RotationCalibrator.fit(groups)
    }
    private var fixtureProfile: BearingProfile?
    func acceptSyntheticDisplay(at now: Double, silent: Bool) {
        guard running else { return }
        let features=AcousticFeatures(sampleRate: 48000,levelDbfs: -20,differenceDb: 2.4,lagSamples: 4.8,shape: [0.1,0.2,0.7])
        let value=silent ? nil : fixtureProfile?.estimate(features,at: now)
        tracker.append(value)
        report.bearing=tracker.estimate(at: now)
        report.state=report.bearing == nil ? "signalUnreliable" : "bearing"
        report.trackingAvailable=true
        report.latestPose=SpatialPose(time: now,origin: .zero,right: .init(1,0,0),up: .init(0,1,0),forward: .init(0,0,-1))
        lastAccepted=now
        if !silent && ProcessInfo.processInfo.arguments.contains("--synthetic-position") {
            var fixtureAccumulator=SpatialAccumulator()
            let source=Vector3(0.1,0.15,-1.6)
            for i in 0..<24 {
                let roll=Double(i/8-1)*35 * .pi/180
                let origin=Vector3(Double(i%8)*0.13-0.45,Double(i/8)*0.1,Double(i%3)*0.04)
                let pose=SpatialPose(time: now-2.3+Double(i)/10,origin: origin,
                    right: .init(cos(roll),sin(roll),0),up: .init(-sin(roll),cos(roll),0),forward: .init(0,0,-1))
                fixtureAccumulator.append(.init(pose: pose,angleDegrees: pose.bearing(of: source-origin),uncertaintyDegrees: 4))
                report.latestPose=pose
            }
            report.solution=fixtureAccumulator.solve(at: now)
            if let pose=report.latestPose {
                let angle=pose.bearing(of: source-pose.origin)
                report.bearing=fixtureProfile?.estimate(AcousticFeatures(sampleRate: 48000,levelDbfs: -20,
                    differenceDb: angle*0.2,lagSamples: angle*0.4,shape: [0.1,0.2,0.7]),at: now)
            }
            report.state=report.solution?.estimate == nil ? "bearing" : "positionCandidate"
        }
    }
    #endif
}
