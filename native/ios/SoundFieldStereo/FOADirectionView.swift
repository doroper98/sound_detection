import SwiftUI
import StereoCore

struct FOAReport: Codable {
    var capture=FOACaptureDiagnostics()
    var latest: FOAAnalysis?
    var lastMidpoint: Double?
    var received=0
    var matched=0
    var rejectedByReason=[String:Int]()
    var synchronization: PoseAlignmentInspection?
    var state="idle"
    var displayedRegions=0
    let axisMapping="ASSUMED: FOA X forward, Y left, Z up -> portrait view (-Y,Z,X); device mapping unverified"
    let axisMappingVerified=false
    let physicalAccuracyVerified=false
    let distanceEstimated=false
    let meaning="Frequency-band direction candidates only; current W band dBFS, not SPL/source strength. Reflections may bias coherent candidates."
}
struct FOAVisibleRegion: Identifiable {
    var id: Int { acoustic.band }
    let acoustic: FOARegion
    let worldDirection: Vector3
}
@MainActor
final class FOADirectionModel: ObservableObject {
    @Published private(set) var report=FOAReport()
    @Published private(set) var regions=[FOAVisibleRegion]()
    var poseProvider: ((Double,Double,Double) -> PoseAlignmentInspection)?
    private var pending=[(FOAAnalysis,Double,Double,Double)]()
    private var running=false
    private var lastAccepted=0.0
    func start() { report=FOAReport(); report.state="waiting"; regions=[]; pending=[]; running=true; lastAccepted=0 }
    func receive(_ analysis: FOAAnalysis, midpoint: Double, duration: Double, capture: FOACaptureDiagnostics) {
        guard running else { return }
        let events=report.capture.events
        report.capture=capture; report.capture.events=Array((events+capture.events).suffix(20))
        report.latest=analysis; report.lastMidpoint=midpoint; report.received+=1
        let now=ProcessInfo.processInfo.systemUptime
        if pending.count>=4 { pending.removeFirst(); report.rejectedByReason["queueOverflow",default: 0]+=1 }
        pending.append((analysis,midpoint,duration,now)); tick()
    }
    func failure(_ message: String, capture: FOACaptureDiagnostics? = nil) {
        if let capture { report.capture=capture }
        report.capture.lastError=message; report.state="failed"; regions=[]; report.displayedRegions=0
    }
    func noteEvent(_ text: String) {
        report.capture.events.append(text)
        if report.capture.events.count>20 { report.capture.events.removeFirst() }
    }
    func tick() {
        guard running else { return }
        let now=ProcessInfo.processInfo.systemUptime
        while let row=pending.first {
            var inspection=poseProvider?(row.1,row.2,now) ?? .init(issue: .poseProviderUnavailable)
            if !row.1.isFinite || now-row.1>=0.3 || now-row.1 < -0.06 {
                inspection = .init(issue: !row.1.isFinite ? .invalidTiming : (now-row.1>=0.3 ? .audioTooOld : .audioInFuture),
                    audioAgeSeconds: now-row.1,waitingForCameraIssue: inspection.issue == .matched ? nil : inspection.issue)
            }
            report.synchronization=inspection
            if inspection.issue == .poseTimeMismatch || inspection.issue == .missingCameraFrames {
                if now-row.3<0.18 && now-row.1<0.3 { break }
            }
            pending.removeFirst()
            guard inspection.issue == .matched, let pose=inspection.pose, pose.valid,
                  now-row.1>=(-0.06), now-row.1<0.3 else {
                report.rejectedByReason[inspection.issue.rawValue,default: 0]+=1
                report.state="poseUnavailable"; regions=[]; report.displayedRegions=0; continue
            }
            report.matched+=1; report.state=row.0.state; lastAccepted=row.1
            regions=row.0.regions.map { region in
                // Explicit unverified device mapping; never a source/world position.
                let d=region.direction
                return .init(acoustic: region,worldDirection: (pose.forward*d.x-pose.right*d.y+pose.up*d.z).normalized())
            }
            report.displayedRegions=regions.count
        }
        if now-lastAccepted>0.35 { regions=[]; report.displayedRegions=0; if report.state=="candidate" { report.state="stale" } }
    }
    func trackingLost() { regions=[]; pending=[]; report.displayedRegions=0; report.state="poseUnavailable" }
    func stop() {
        running=false; pending=[]; regions=[]; report.displayedRegions=0; report.capture.running=false
        if report.state != "failed" { report.state="stopped" }
    }
    var status: String {
        switch report.state {
        case "idle": return "카메라·수음 시작으로 소리 방향을 확인하세요"
        case "candidate": return "공간 오디오 방향 후보 · 거리 미측정"
        case "quiet": return "측정 대역의 소리가 작습니다 · 공간 오디오 수음 중"
        case "ambiguous": return "여러 방향이 섞여 방향 표시를 보류합니다"
        case "clipped": return "입력이 너무 큽니다 · 소리를 조금 줄여 주세요"
        case "invalidPCM": return "공간 오디오 샘플 형식을 확인해 주세요"
        case "poseUnavailable": return report.synchronization?.instruction ?? "카메라 자세를 기다리고 있습니다"
        case "stale": return "새로운 소리 방향을 기다리고 있습니다"
        case "failed": return report.capture.lastError ?? "공간 오디오 시작 실패"
        case "stopped": return "공간 오디오 계측 중지"
        default: return "4채널 공간 오디오 입력을 확인하고 있습니다"
        }
    }
    #if DEBUG
    func synthetic(at now: Double, silent: Bool) {
        poseProvider = { midpoint,_,_ in
            .init(issue: .matched,pose: .init(time: midpoint,origin: .zero,right: .init(1,0,0),up: .init(0,1,0),forward: .init(0,0,-1)))
        }
        let d=Vector3(1,-0.18,0.12).normalized()
        let channels=[1,d.y,d.z,d.x].map { v in
            (0..<4096).map { Float(silent ? 0 : 0.08*v*sin(2 * .pi*1500*Double($0)/48000)) }
        }
        var capture=FOACaptureDiagnostics(); capture.supported=true; capture.running=true
        capture.foaBuffers=report.received+1
        capture.foaFormat = .init(channels: 4,layoutTag: nil,sampleRate: 48000,commonFormat: 1,interleaved: false)
        receive(FOAAnalyzer.analyze(channels,sampleRate: 48000),midpoint: now-0.05,duration: 4096.0/48000,capture: capture)
    }
    #endif
}

struct FOADirectionOverlay: View {
    @ObservedObject var model: FOADirectionModel
    @ObservedObject var camera: CameraModel
    let synthetic: Bool
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Show distinct spectral regions; close directions share a tag to avoid overlap.
                ForEach(visibleRegions) { region in
                    if let point=project(region.worldDirection,size: geometry.size),
                       (0...geometry.size.width).contains(point.x), (0...geometry.size.height).contains(point.y) {
                        let strength=SoundHeatLevel.normalized(region.acoustic.levelDbfs)
                        let radius=CGFloat(max(75,min(130,75+region.acoustic.spreadDegrees*2)))
                        ZStack {
                            Circle().fill(RadialGradient(stops: heatStops(strength),center: .center,startRadius: 0,endRadius: radius))
                                .accessibilityIdentifier("foaHeatIsland")
                            VStack(spacing: 2) {
                                Text(region.acoustic.frequencyLabel).font(.system(size: 12,weight: .bold))
                                    .accessibilityIdentifier("foaFrequency")
                                Text(String(format: "%.0f dBFS",region.acoustic.levelDbfs)).font(.system(size: 10))
                            }.padding(6).background(.black.opacity(0.65),in: RoundedRectangle(cornerRadius: 7))
                        }.frame(width: radius*2,height: radius*2).position(point)
                    }
                }
                VStack(spacing: 5) {
                    Text(model.status).font(.subheadline.bold()).accessibilityIdentifier("foaStatus")
                    Text("실험 방향 열지도 · 카메라 축 대응·정확도 확인 전")
                        .font(.caption2).foregroundStyle(.white.opacity(0.8))
                    if !model.regions.isEmpty && visibleRegions.allSatisfy({ region in
                        guard let p=project(region.worldDirection,size: geometry.size) else { return true }
                        return !CGRect(origin: .zero,size: geometry.size).contains(p)
                    }) { Text("방향 후보가 화면 밖에 있습니다").font(.caption) }
                }.multilineTextAlignment(.center).padding(12).background(.black.opacity(0.6),in: RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: geometry.size.width-40).position(x: geometry.size.width/2,y: geometry.size.height*0.27)
            }.frame(width: geometry.size.width,height: geometry.size.height)
        }.foregroundStyle(.white).allowsHitTesting(false)
    }
    private var visibleRegions: [FOAVisibleRegion] {
        var chosen=[FOAVisibleRegion]()
        for region in model.regions.sorted(by: { $0.acoustic.levelDbfs>$1.acoustic.levelDbfs }) {
            if !chosen.contains(where: { $0.worldDirection.angle(to: region.worldDirection)<18 }) { chosen.append(region) }
        }
        return chosen
    }
    private func heatStops(_ strength: Double) -> [Gradient.Stop] {
        (0...10).map { index in
            let radius=Double(index)/10
            let value=strength*(1-0.45*radius*radius)
            return .init(color: Color(hue: (1-value)*0.66,saturation: 0.95,brightness: 1)
                .opacity(index==10 ? 0 : 0.85*(1-radius*radius)),location: radius)
        }
    }
    private func project(_ direction: Vector3,size: CGSize) -> CGPoint? {
        #if DEBUG
        if synthetic {
            guard direction.z<0 else { return nil }
            let scale=Double(size.width)/1.2
            return .init(x: Double(size.width)/2+direction.x/(-direction.z)*scale,
                         y: Double(size.height)/2-direction.y/(-direction.z)*scale)
        }
        #endif
        guard let pose=camera.spatialCamera.calibrationPose else { return nil }
        // Distance 2 is a projection helper only; no source range or world point is inferred.
        return camera.spatialCamera.project(pose.origin+direction*2,size: size)
    }
}
