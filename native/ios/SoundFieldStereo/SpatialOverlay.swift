import SwiftUI
import StereoCore

struct SpatialOverlay: View {
    @ObservedObject var spatial: SpatialModel
    @ObservedObject var camera: CameraModel
    let synthetic: Bool
    private let tint=Color(red: 0.48,green: 0.95,blue: 0.68)
    private var data: SpatialReport { spatial.report }

    var body: some View {
        GeometryReader { geometry in
            let size=geometry.size
            ZStack {
                if let bearing=data.bearing {
                    let range=band(bearing,size: size)
                    if let range {
                        Rectangle()
                            .fill(LinearGradient(colors: [.clear,tint.opacity(0.32),.clear],startPoint: .leading,endPoint: .trailing))
                            .frame(width: max(24,range.1-range.0),height: size.height*0.55)
                            .position(x: (range.0+range.1)/2,y: size.height*0.43)
                            .accessibilityLabel("실험적 수평 소리 방향 범위")
                            .accessibilityIdentifier("soundBearingBand")
                    }
                }
                if let estimate=data.solution?.estimate,
                   let p=project(estimate.point,size: size),
                   let pose=data.latestPose {
                    if (20...size.width-20).contains(p.x) && (110...size.height-260).contains(p.y) {
                        let edge=project(estimate.point+pose.right*estimate.uncertaintyRadiusMeters,size: size)
                        let radius=min(90,max(24,abs((edge?.x ?? p.x+35)-p.x)))
                        ZStack {
                            Circle().fill(tint.opacity(0.15))
                            Circle().stroke(tint,style: StrokeStyle(lineWidth: 2,dash: [5,4]))
                            Image(systemName: "waveform").font(.title2.bold()).foregroundStyle(tint)
                        }.frame(width: radius*2,height: radius*2).position(p)
                        Text(String(format: "위치 후보 · 약 %.1fm",(estimate.point-pose.origin).length))
                            .font(.caption.bold()).padding(8).background(.black.opacity(0.8),in: Capsule())
                            .position(x: min(max(p.x,90),size.width-90),y: max(125,p.y-radius-20))
                            .accessibilityIdentifier("soundPositionCandidate")
                    } else {
                        Text("← 화면 밖 위치 후보 →").font(.caption.bold()).foregroundStyle(tint)
                            .position(x: size.width/2,y: 160)
                    }
                }
                if data.calibration.phase=="collecting" {
                    calibrationCard.frame(maxWidth: min(size.width-32,430))
                        .position(x: size.width/2,y: size.height*0.38)
                } else {
                    VStack(spacing: 7) {
                        Image(systemName: data.bearing == nil ? "viewfinder" : "waveform")
                            .font(.system(size: 30,weight: .light))
                        Text(headline).font(.subheadline.bold()).multilineTextAlignment(.center)
                            .accessibilityIdentifier("spatialStatus")
                        Text(detail).font(.caption).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                    }
                    .padding(14).background(.black.opacity(0.58),in: RoundedRectangle(cornerRadius: 14))
                    .frame(maxWidth: size.width-48)
                    .position(x: size.width/2,y: size.height*0.33)
                }
            }.frame(width: size.width,height: size.height)
        }
        .allowsHitTesting(data.calibration.phase=="collecting")
    }
    private var calibrationCard: some View {
        VStack(spacing: 10) {
            Text("방향 보정 \(min(6,data.calibration.step+1))/6").font(.headline)
                .accessibilityIdentifier("rotationCalibrationStep")
            Text(String(format: "소리 각도 %+.0f° → 목표 %+.0f°",data.calibration.currentDegrees ?? 0,data.calibration.targetDegrees))
                .font(.title3.monospacedDigit().bold()).foregroundStyle(tint)
            ProgressView(value: data.calibration.progress).tint(tint)
            Text(data.calibration.instruction).font(.caption).multilineTextAlignment(.center)
            Button("보정 취소") { spatial.cancelCalibration() }.buttonStyle(.bordered)
                .accessibilityIdentifier("rotationCalibrationCancel")
        }.padding(16).background(.black.opacity(0.86),in: RoundedRectangle(cornerRadius: 18))
    }
    private var headline: String {
        if let b=data.bearing { return String(format: "소리 방향 추정 · %@ %.0f°",b.degrees<0 ? "왼쪽" : "오른쪽",abs(b.degrees)) }
        if data.calibration.phase=="rejected" { return "방향 보정 보류" }
        switch data.state {
        case "idle","stopped": return "소리 방향·위치 찾기"
        case "trackingLost": return "카메라 이동 추적 대기"
        case "signalUnreliable": return "소리 방향을 확정하기 어렵습니다"
        default: return "소리 찾기에서 방향 보정을 시작하세요"
        }
    }
    private var detail: String {
        if data.calibration.phase=="rejected" { return data.calibration.instruction }
        guard data.bearing != nil else {
            if data.state=="signalUnreliable" { return "같은 소리 하나를 일정하게 내고 폰을 잠시 멈추세요." }
            return "고정된 한 소리 · 먼저 보정, 이후 이동 관측"
        }
        switch data.solution?.state {
        case "candidate": return "실험적 위치 후보 · 원은 계산상 민감도 범위"
        case "needTranslation": return "거리를 좁히려면 폰을 옆으로 30cm 이상 옮기세요."
        case "needTiltOrParallax": return "높이를 좁히려면 이동 후 폰을 조금 기울여 관측하세요."
        case "inconsistent","uncertain","outOfRange": return "위치가 일치하지 않아 방향 범위만 표시합니다."
        default: return "세로 띠는 수평 방향 범위 · 높이·거리 미정\n옆으로 이동하고 조금 기울린 뒤 잠시 멈추세요."
        }
    }
    private func band(_ b: BearingEstimate, size: CGSize) -> (CGFloat,CGFloat)? {
        if synthetic {
            let half=Double(size.width)/2
            return (CGFloat(half+tan((b.degrees-b.uncertaintyDegrees) * .pi/180)*half/0.6),
                    CGFloat(half+tan((b.degrees+b.uncertaintyDegrees) * .pi/180)*half/0.6))
        }
        guard let pose=camera.spatialCamera.latestPose else { return nil }
        func projection(_ a: Double) -> CGPoint? {
            let r=a * .pi/180
            return camera.spatialCamera.project(pose.origin+(pose.forward*cos(r)+pose.right*sin(r))*2,size: size)
        }
        guard let left=projection(b.degrees-b.uncertaintyDegrees),let right=projection(b.degrees+b.uncertaintyDegrees) else { return nil }
        return (max(-size.width,min(left.x,right.x)),min(size.width*2,max(left.x,right.x)))
    }
    private func project(_ point: Vector3, size: CGSize) -> CGPoint? {
        #if DEBUG
        if synthetic, let pose=data.latestPose {
            let delta=point-pose.origin, depth=delta.dot(pose.forward)
            guard depth>0 else { return nil }
            let scale=Double(size.width)/1.2
            return .init(x: Double(size.width)/2+delta.dot(pose.right)/depth*scale,
                         y: Double(size.height)/2-delta.dot(pose.up)/depth*scale)
        }
        #endif
        return camera.spatialCamera.project(point,size: size)
    }
}

struct SpatialGuide: View {
    @ObservedObject var model: CaptureModel
    @ObservedObject var camera: CameraModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 20) {
                Text("소리 방향·위치 찾기").font(.largeTitle.bold())
                Text("빌드 5 검사는 생략해도 됩니다. 여기서 보정과 위치 표시를 이어서 진행합니다.").foregroundStyle(.secondary)
                Group {
                    Text("1. 고정된 소리 하나 준비").font(.headline)
                    Text("조용하고 밝은 곳에서 한 스피커로 일정한 광대역 소리(잡음 등)를 재생하세요. 여러 스피커·음악·기침처럼 계속 달라지는 소리는 피하세요. 폰에서 1m 이상 떨어진 소리를 후면 카메라 중앙, 같은 높이에 맞추세요.")
                    Text("2. 화면 안내대로 좌우 회전").font(.headline)
                    Text("아래 버튼을 누른 뒤 폰 위치를 최대한 고정하고 좌우로만 돌리세요. 화면의 소리 각도가 목표 0°·−25°·+25°에 맞으면 2.5초 정도 멈춥니다. 두 번 반복하며 자동으로 수집합니다. 원음이나 영상은 저장하지 않습니다.")
                    Text("3. 카메라 위 방향 → 위치 후보").font(.headline)
                    Text("보정이 통과하면 초록 띠로 수평 방향을 표시합니다. 같은 소리는 고정해 두고 폰을 옆으로 30~80cm 옮기며 여러 번 멈추세요. 높이도 좁히려면 폰을 조금 좌우로 기울여 다른 자세에서 관측하세요. 조건이 충분하면 원과 대략적인 거리가 나타납니다.")
                    Text("띠는 높이를 정하지 않습니다. 위치 원과 거리는 실험적 후보이며 정확도는 아직 실기기에서 검증되지 않았습니다. 반사·여러 소리·움직이는 소리에서는 보류될 수 있습니다.").font(.footnote).foregroundStyle(.secondary)
                }
                Text(camera.trackingStatus).font(.caption).accessibilityIdentifier("spatialTrackingStatus")
                Button("중앙 정렬 완료 · 방향 보정 시작") {
                    if let pose=camera.spatialCamera.latestPose { model.spatial.beginCalibration(pose: pose); dismiss() }
                }
                .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                .disabled(model.phase != .running || model.source != "back" || camera.spatialCamera.latestPose == nil)
                .accessibilityIdentifier("rotationCalibrationStart")
                if model.phase != .running { Text("먼저 후면 카메라·수음을 시작하세요.").font(.caption) }
                Button("위치 관측 초기화") { model.spatial.resetMap(); dismiss() }.buttonStyle(.bordered)
                Text("다른 소리·장소로 바꾸면 다시 보정하세요. 수음을 새로 시작하면 이전 보정도 초기화됩니다. 상세 → 진단 JSON 공유에 상대 기기 좌표와 추정 통계를 포함합니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(22)
        }.navigationTitle("소리 찾기")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
    }
}
