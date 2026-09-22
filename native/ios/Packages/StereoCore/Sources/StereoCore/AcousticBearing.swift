import Foundation

/// Statistics only. Band shape is a coarse source-consistency guard, not source
/// recognition or a calibrated spectrum. It never stores/reconstructs PCM.
public struct AcousticFeatures: Codable, Sendable {
    public let sampleRate: Double
    public let levelDbfs: Double
    public let differenceDb: Double
    public let lagSamples: Double?
    public let shape: [Double]
    public init(sampleRate: Double, levelDbfs: Double, differenceDb: Double, lagSamples: Double?, shape: [Double]) {
        self.sampleRate=sampleRate; self.levelDbfs=levelDbfs; self.differenceDb=differenceDb
        self.lagSamples=lagSamples; self.shape=shape
    }
    public var valid: Bool {
        sampleRate.isFinite && (8000...192000).contains(sampleRate) && levelDbfs.isFinite
            && (-65 ... -3).contains(levelDbfs) && differenceDb.isFinite && abs(differenceDb)<35
            && (lagSamples?.isFinite ?? true) && shape.count==3 && shape.allSatisfy { $0.isFinite && (0...1).contains($0) }
            && abs(shape.reduce(0,+)-1)<0.01
    }
    public static func measure(left: [Float], right: [Float], analysis: StereoAnalysis) -> Self? {
        guard left.count==right.count, left.count>=128, analysis.channels.count==2,
              !analysis.duplicateSuspected, analysis.status != .silentChannel, analysis.status != .clipped,
              let l=analysis.channels[0].rmsDbfs, let r=analysis.channels[1].rmsDbfs else { return nil }
        let rate=analysis.sampleRate
        guard rate.isFinite, rate>0 else { return nil }
        let a=1-exp(-2 * .pi * 400/rate), b=1-exp(-2 * .pi * 2000/rate)
        var energies=[Double](repeating: 0,count: 3)
        for channel in [left,right] {
            var low=0.0, mid=0.0
            let mean=channel.reduce(0.0) { $0+Double($1) }/Double(channel.count)
            for (index,sample) in channel.enumerated() {
                let v=Double(sample)-mean
                low += a*(v-low); mid += b*(v-mid)
                if index>64 {
                    energies[0] += low*low; energies[1] += (mid-low)*(mid-low); energies[2] += (v-mid)*(v-mid)
                }
            }
        }
        let sum=energies.reduce(0,+)
        guard sum>1e-12 else { return nil }
        let f=Self(sampleRate: rate, levelDbfs: max(l,r), differenceDb: r-l,
            lagSamples: analysis.status == .candidate ? analysis.rightMinusLeftLagSamples.map(Double.init) : nil,
            shape: energies.map { $0/sum })
        return f.valid ? f : nil
    }
}

public struct BearingEstimate: Codable, Sendable {
    public let degrees: Double
    public let uncertaintyDegrees: Double
    public let method: String
    public let time: Double
}

public struct BearingResponse: Codable, Sendable {
    public let method: String
    public let slope: Double
    public let intercept: Double
    public let errorDegrees: Double
    func value(_ f: AcousticFeatures) -> Double? { method=="levelDifference" ? f.differenceDb : f.lagSamples }
}

public struct BearingProfile: Codable, Sendable {
    public let responses: [BearingResponse]
    public let sampleRate: Double
    public let shape: [Double]
    public let referenceLevelDbfs: Double
    public let minimumAngle = -25.0
    public let maximumAngle = 25.0
    public let acousticAccuracyVerified = false
    public let assumption = "Same stationary broadband source, front hemisphere, same room and audio route; empirical rotation calibration, not microphone geometry."

    public func estimate(_ features: AcousticFeatures, at time: Double) -> BearingEstimate? {
        guard time.isFinite, features.valid, features.sampleRate==sampleRate,
              features.levelDbfs>=referenceLevelDbfs-15,
              zip(features.shape,shape).reduce(0.0, { $0+abs($1.0-$1.1) }) < 0.4 else { return nil }
        let candidates: [(Double,Double,String)] = responses.compactMap { response in
            guard let value=response.value(features), abs(response.slope)>1e-9 else { return nil }
            let angle=(value-response.intercept)/response.slope
            guard angle.isFinite, abs(angle)<=28 else { return nil }
            return (angle,max(4,response.errorDegrees*2),response.method)
        }
        guard let best=candidates.min(by: { $0.1<$1.1 }) else { return nil }
        if candidates.count>1, abs(candidates[0].0-candidates[1].0)>12 { return nil }
        return BearingEstimate(degrees: best.0, uncertaintyDegrees: best.1, method: best.2, time: time)
    }
}

public struct RotationCalibrationSample: Codable, Sendable {
    public let angle: Double
    public let features: AcousticFeatures
    public let time: Double
    public init(angle: Double, features: AcousticFeatures, time: Double) { self.angle=angle; self.features=features; self.time=time }
}

public struct RotationCalibrationState: Codable, Sendable {
    public let phase: String
    public let step: Int
    public let targetDegrees: Double
    public let currentDegrees: Double?
    public let progress: Double
    public let instruction: String
    public let completedSamples: Int
    public let profile: BearingProfile?
}

public struct RotationCalibrator {
    public static let targets = [0.0,-25,25,0,-25,25]
    private var reference: SpatialPose?
    private var startedAt=0.0
    private var step=0
    private var currentAngle: Double?
    private var group: [RotationCalibrationSample]=[]
    private var groups: [[RotationCalibrationSample]]=[]
    private var phase="idle"
    private var message="고정된 소리 하나를 화면 중앙에 맞춘 뒤 보정을 시작하세요."
    public private(set) var profile: BearingProfile?
    public var active: Bool { phase=="collecting" }
    public init() {}
    public mutating func begin(pose: SpatialPose) {
        guard pose.valid else { return }
        self=Self(); reference=pose; startedAt=pose.time; phase="collecting"
        message="폰 위치를 유지하고 안내 각도에서 잠시 멈추세요."
    }
    public mutating func cancel(_ reason: String) { phase="idle"; group=[]; message=reason; profile=nil }
    public mutating func append(features: AcousticFeatures?, pose: SpatialPose) {
        guard active, let reference, pose.valid else { return }
        currentAngle=pose.bearing(of: reference.forward)
        guard pose.time-startedAt<180 else { cancel("보정 시간이 초과됐습니다. 다시 시작하세요."); return }
        guard (pose.origin-reference.origin).length<=0.04 else {
            group=[]; message="폰 위치가 움직였습니다. 처음 위치로 돌아오거나 보정을 다시 시작하세요."; return
        }
        guard abs(pose.elevation(of: reference.forward))<6, pose.up.angle(to: reference.up)<8 else {
            group=[]; message="보정 중에는 폰을 세로로 유지하고 좌우로만 돌리세요."; return
        }
        guard let f=features, f.valid, f.levelDbfs > -60 else {
            group=[]; message="광대역 소리를 일정하게 내주세요. 소리가 약하거나 분석 조건이 부족합니다."; return
        }
        let angle=currentAngle!
        guard abs(angle-Self.targets[step])<=3 else {
            group=[]; message="표시된 소리 각도에 맞춰 폰을 좌우로 돌린 뒤 멈추세요."; return
        }
        if let last=group.last {
            guard pose.time>last.time else { return }
            if pose.time-last.time>0.3 { group=[] }
        }
        group.append(.init(angle: angle, features: f, time: pose.time))
        if group.count>60 { group.removeFirst() }
        message="좋습니다. 같은 자세로 소리를 계속 내주세요."
        guard group.count>=20, pose.time-(group.first?.time ?? pose.time)>=2.4 else { return }
        groups.append(group); group=[]; step+=1
        if step==6 {
            profile=Self.fit(groups)
            phase=profile == nil ? "rejected" : "ready"
            message=profile == nil ? "좌우 응답이 충분히 구분되거나 반복되지 않았습니다. 더 일정한 한 소리로 다시 보정하세요."
                : "보정 완료 · 같은 소리의 방향 범위를 표시합니다."
        }
    }
    public func snapshot() -> RotationCalibrationState {
        .init(phase: phase, step: step, targetDegrees: Self.targets[min(step,5)], currentDegrees: currentAngle,
            progress: min(1,Double(group.count)/25), instruction: message,
            completedSamples: groups.reduce(0) { $0+$1.count }, profile: profile)
    }
    /// Repeated labeled rotations cross-check sign, response slope and residual.
    /// Labels are measured relative poses after user's central alignment, not
    /// target positions passed into live localization.
    public static func fit(_ groups: [[RotationCalibrationSample]]) -> BearingProfile? {
        guard groups.count==6, groups.allSatisfy({ $0.count>=20 }), let first=groups.first?.first else { return nil }
        let all=groups.flatMap { $0 }
        guard all.allSatisfy({ $0.features.valid && $0.features.sampleRate==first.features.sampleRate
            && $0.angle.isFinite && $0.time.isFinite }),
            zip(groups,targets).allSatisfy({ abs(medianValue($0.0.map(\.angle))-$0.1)<3.1 }) else { return nil }
        let shape=(0..<3).map { band in medianValue(all.map { $0.features.shape[band] }) }
        guard all.allSatisfy({ row in zip(row.features.shape,shape).reduce(0.0) { $0+abs($1.0-$1.1) } < 0.4 }) else { return nil }
        var responses: [BearingResponse]=[]
        for method in ["levelDifference","signalLag"] {
            func value(_ s: RotationCalibrationSample) -> Double? { method=="levelDifference" ? s.features.differenceDb : s.features.lagSamples }
            guard groups.allSatisfy({ Double($0.compactMap(value).count)>=Double($0.count)*0.75 }) else { continue }
            let x=groups.map { medianValue($0.map(\.angle)) }
            let y=groups.map { medianValue($0.compactMap(value)) }
            let mx=x.reduce(0,+)/6, my=y.reduce(0,+)/6
            let denominator=x.reduce(0) { $0+pow($1-mx,2) }
            guard denominator>100 else { continue }
            let slope=zip(x,y).reduce(0) { $0+($1.0-mx)*($1.1-my) }/denominator
            guard abs(slope) >= (method=="levelDifference" ? 0.04 : 0.12) else { continue }
            let intercept=my-slope*mx
            guard (0..<3).allSatisfy({ abs(y[$0]-y[$0+3])/abs(slope)<6 }) else { continue }
            let errors=all.compactMap { row -> Double? in value(row).map { (($0-intercept)/slope)-row.angle } }
            let rms=sqrt(errors.reduce(0) { $0+$1*$1 }/Double(errors.count))
            guard rms<=5 else { continue }
            responses.append(.init(method: method,slope: slope,intercept: intercept,errorDegrees: max(2,rms)))
        }
        guard !responses.isEmpty else { return nil }
        let shapeSum=shape.reduce(0,+)
        return BearingProfile(responses: responses, sampleRate: first.features.sampleRate,
            shape: shape.map { $0/shapeSum }, referenceLevelDbfs: medianValue(all.map { $0.features.levelDbfs }))
    }
}

public struct BearingTracker {
    private var rows: [BearingEstimate]=[]
    public init() {}
    public mutating func append(_ value: BearingEstimate?) {
        guard let value else { rows=[]; return }
        if let last=rows.last, value.time<=last.time { return }
        rows.removeAll { value.time-$0.time>0.45 }
        rows.append(value)
        if rows.count>12 { rows.removeFirst() }
    }
    public func estimate(at now: Double) -> BearingEstimate? {
        guard let last=rows.last, now-last.time >= -0.06, now-last.time<0.35,
              rows.count>=3, last.time-rows[0].time>=0.15 else { return nil }
        let angle=medianValue(rows.map(\.degrees))
        let spread=1.4826*medianValue(rows.map { abs($0.degrees-angle) })
        guard spread<=5 else { return nil }
        return BearingEstimate(degrees: angle,uncertaintyDegrees: max(last.uncertaintyDegrees,spread*2),method: last.method,time: last.time)
    }
}

private func medianValue(_ a: [Double]) -> Double {
    guard !a.isEmpty else { return .nan }
    let s=a.sorted(), n=s.count
    return n.isMultiple(of: 2) ? (s[n/2-1]+s[n/2])/2 : s[n/2]
}
