import SwiftUI
import StereoCore

private enum HeatPalette {
    static let colors: [Color] = [.blue,.cyan,.green,.yellow,.orange,.red]
    static func color(_ value: Double, opacity: Double) -> Color {
        Color(hue: (1-min(1,max(0,value)))*0.66,saturation: 0.95,brightness: 1).opacity(opacity)
    }
    static func radial(_ dbfs: Double) -> [Gradient.Stop] {
        let level=SoundHeatLevel.normalized(dbfs)
        return (0...16).map { i in
            let radius=Double(i)/16, weight=i==16 ? 0 : exp(-3.5*radius*radius)
            return .init(color: color(level*weight,opacity: weight*(0.4+0.4*level)),location: radius)
        }
    }
    static func band(_ dbfs: Double) -> [Gradient.Stop] {
        let level=SoundHeatLevel.normalized(dbfs)
        return (0...32).map { i in
            let x=Double(i)/32, radius=abs(x-0.5)*2
            let weight=(i==0 || i==32) ? 0 : exp(-3.5*radius*radius)
            return .init(color: color(level*weight,opacity: weight*(0.4+0.4*level)),location: x)
        }
    }
}

struct SoundHeatLegend: View {
    @ObservedObject var spatial: SpatialModel
    private var visible: Bool { spatial.report.bearing != nil && spatial.report.sound != nil }
    var body: some View {
            VStack(spacing: 3) {
                HStack(spacing: 7) {
                    Text("약함 −65")
                    LinearGradient(colors: HeatPalette.colors,startPoint: .leading,endPoint: .trailing)
                        .frame(width: 90,height: 5).clipShape(Capsule())
                    Text("−15 강함 · dBFS")
                }
                Text("색: 입력 크기 · 영역: 추정 범위")
            }.font(.system(size: 10)).foregroundStyle(.white.opacity(0.9))
                .accessibilityElement(children: .combine).accessibilityIdentifier("soundHeatLegend")
                .frame(height: 28).opacity(visible ? 1 : 0).accessibilityHidden(!visible)
    }
}

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
                if data.bearing == nil {
                    Image(systemName: "plus").font(.system(size: 28,weight: .light))
                        .foregroundStyle(.white).shadow(color: .black,radius: 2)
                        .position(x: size.width/2,y: size.height/2)
                        .accessibilityLabel("소리 정렬용 카메라 중앙 기준점")
                        .accessibilityIdentifier("cameraAlignmentReticle")
                }
                if let bearing=data.bearing, data.solution?.estimate == nil, let sound=data.sound {
                    let range=band(bearing,size: size)
                    if let range {
                        Rectangle()
                            .fill(LinearGradient(stops: HeatPalette.band(sound.levelDbfs),startPoint: .leading,endPoint: .trailing))
                            .frame(width: max(36,range.1-range.0),height: size.height)
                            .position(x: (range.0+range.1)/2,y: size.height/2)
                            .mask(Rectangle().padding(.top,190).padding(.bottom,320))
                            .accessibilityLabel("수평 방향 열지도 · 높이 미정")
                            .accessibilityIdentifier("soundBearingBand")
                        frequencyTag(sound)
                            .position(x: min(max((range.0+range.1)/2,100),size.width-100),y: size.height*0.48)
                    }
                }
                if let estimate=data.solution?.estimate,
                   let p=project(estimate.point,size: size),
                   let pose=data.latestPose, let sound=data.sound {
                    if (20...size.width-20).contains(p.x) && (220...max(220,size.height-350)).contains(p.y) {
                        let edge=project(estimate.point+pose.right*estimate.uncertaintyRadiusMeters,size: size)
                        let radius=min(120,max(64,abs((edge?.x ?? p.x+64)-p.x)))
                        ZStack {
                            Circle().fill(RadialGradient(stops: HeatPalette.radial(sound.levelDbfs),
                                center: .center,startRadius: 0,endRadius: radius))
                                .accessibilityLabel("소리 위치 후보 열섬")
                                .accessibilityIdentifier("soundHeatIsland")
                            frequencyTag(sound)
                                .offset(x: min(max(p.x,100),size.width-100)-p.x)
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
                } else if data.state=="alignSource" {
                    VStack(spacing: 10) {
                        Text("화면 가운데 + 위에 스피커가 보이게 하세요.").font(.subheadline.bold()).multilineTextAlignment(.center)
                        Text("1m 이상 거리 · 같은 높이 · 소리는 고정").font(.caption)
                        Button("정렬 완료 · 보정 시작") {
                            if let pose=camera.spatialCamera.calibrationPose { spatial.beginCalibration(pose: pose) }
                        }.buttonStyle(.borderedProminent).tint(tint).foregroundStyle(.black)
                            .disabled(camera.spatialCamera.calibrationPose == nil)
                            .accessibilityIdentifier("rotationAlignmentDone")
                        Button("취소") { spatial.cancelCalibration() }.font(.caption)
                    }.padding(16).background(.black.opacity(0.8),in: RoundedRectangle(cornerRadius: 16))
                        .frame(maxWidth: size.width-40).position(x: size.width/2,y: size.height*0.34)
                } else if data.solution?.estimate != nil {
                    Text("실험적 위치 열지도 · 한 소리 추정")
                        .font(.caption.bold()).padding(10).background(.black.opacity(0.65),in: Capsule())
                        .position(x: size.width/2,y: size.height*0.25)
                        .accessibilityIdentifier("spatialStatus")
                } else {
                    VStack(spacing: 7) {
                        Image(systemName: data.bearing == nil ? "ear" : "waveform")
                            .font(.system(size: 30,weight: .light))
                        Text(headline).font(.subheadline.bold()).multilineTextAlignment(.center)
                            .accessibilityIdentifier("spatialStatus")
                        Text(detail).font(.caption).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                            .accessibilityIdentifier("spatialDetail")
                    }
                    .padding(14).background(.black.opacity(0.58),in: RoundedRectangle(cornerRadius: 14))
                    .frame(maxWidth: size.width-48)
                    .position(x: size.width/2,y: size.height*0.32)
                }
            }.frame(width: size.width,height: size.height)
        }
        .allowsHitTesting(data.calibration.phase=="collecting" || data.state=="alignSource")
    }
    private func frequencyTag(_ sound: SoundSpectrum) -> some View {
        VStack(spacing: 3) {
            Text(sound.frequencyLabel).font(.system(size: 11,weight: .semibold,design: .rounded))
                .accessibilityIdentifier("soundHeatFrequency")
            Text(String(format: "입력 %.0f dBFS",sound.levelDbfs)).font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85)).accessibilityIdentifier("soundHeatLevel")
        }.foregroundStyle(.white).shadow(color: .black.opacity(0.95),radius: 2,x: 0,y: 1).fixedSize()
    }
    private var calibrationCard: some View {
        VStack(spacing: 10) {
            Text("방향 보정 \(min(6,data.calibration.step+1))/6").font(.headline)
                .accessibilityIdentifier("rotationCalibrationStep")
            Text(data.calibration.movementInstruction)
                .font(.title3.bold()).foregroundStyle(tint).multilineTextAlignment(.center)
                .accessibilityIdentifier("rotationMovementInstruction")
            Text("스피커는 고정 · 폰을 옆으로 옮기지 말고 방향만 바꾸세요")
                .font(.caption2).multilineTextAlignment(.center)
            Text(String(format: "스피커 방향 %+.0f° / 목표 %+.0f°",data.calibration.currentDegrees ?? 0,data.calibration.targetDegrees))
                .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
            ProgressView(value: data.calibration.progress).tint(tint)
            if data.calibration.instruction != data.calibration.movementInstruction {
                Text(data.calibration.instruction).font(.caption).multilineTextAlignment(.center)
            }
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
        case "candidate": return "실험적 위치 열섬 · 강도와 주파수는 현재 입력 기준"
        case "needTranslation": return "거리를 좁히려면 폰을 옆으로 30cm 이상 옮기세요."
        case "needTiltOrParallax": return "높이를 좁히려면 이동 후 폰을 조금 기울여 관측하세요."
        case "inconsistent","uncertain","outOfRange": return "위치가 일치하지 않아 방향 범위만 표시합니다."
        default: return "열지도는 수평 방향 범위 · 높이·거리 미정\n옆으로 이동하고 조금 기울린 뒤 잠시 멈추세요."
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
                Text("카메라 위 열지도에서 방향·위치 후보와 입력 주파수를 확인합니다.").foregroundStyle(.secondary)
                Group {
                    Text("1. 고정된 소리 하나 준비").font(.headline)
                    Text("PC 보정용 페이지에서 소리 시작을 누르세요. 한 스피커에서 “쉬—” 소리가 계속 나게 둡니다. 아이폰은 1m 이상 떨어져 세로로 들고, 스피커와 높이를 비슷하게 맞추세요.")
                    Text("2. 정면 → 오른쪽 → 왼쪽, 두 번").font(.headline)
                    Text("아래 버튼을 누르고 화면 중앙 +에 스피커를 맞춘 뒤 보정을 시작하세요. 이후에는 큰 화살표를 따라 폰이 바라보는 방향만 돌리고, 멈추라는 안내가 나오면 다음 단계까지 기다리세요. 스피커가 계속 +에 있을 필요는 없습니다. 폰은 같은 자리에 두세요.")
                    Text("3. 카메라 위 방향 → 위치 후보").font(.headline)
                    Text("보정이 통과하면 세로 열지도로 수평 방향을 표시합니다. 같은 소리는 고정해 두고 폰을 옆으로 30~80cm 옮기며 여러 번 멈추세요. 높이도 좁히려면 폰을 조금 좌우로 기울여 다른 자세에서 관측하세요. 조건이 충분하면 위치 주변의 열섬과 대략적인 거리가 나타납니다.")
                    Text("4. 색과 작은 주파수 읽기").font(.headline)
                    Text("파랑→청록→노랑→빨강은 폰에서 받은 입력이 약함→강함을 뜻합니다. 열섬 안에 대표 주파수(Hz/kHz)와 입력 크기(dBFS)를 작게 표시합니다. 뚜렷한 주파수가 없는 잡음은 분석 대역 에너지의 가운데 80% 구간을 표시합니다. 색은 고정 −65~−15 dBFS 척도이며 소음계 dB SPL이 아닙니다.")
                    Text("세로 열지도는 높이를 정하지 않습니다. 열섬의 모양은 추정 영역을 부드럽게 강조한 표시이며 물체 크기나 실제 음압 분포가 아닙니다. 주파수는 현재 입력 전체 기준이며 여러 음원을 분리한 값이 아닙니다. 위치·거리 정확도는 실기기 미검증이고 반사·여러 소리·움직이는 소리에서는 보류될 수 있습니다.").font(.footnote).foregroundStyle(.secondary)
                }
                Text(camera.trackingStatus).font(.caption).accessibilityIdentifier("spatialTrackingStatus")
                Button("카메라로 중앙 정렬") {
                    model.cancelCalibrationTrial(); model.spatial.prepareAlignment(); dismiss()
                }
                .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                .disabled(model.phase != .running || model.source != "back" || camera.spatialCamera.calibrationPose == nil)
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
