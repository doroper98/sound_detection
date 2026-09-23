import AVFoundation
import SwiftUI
import StereoCore

private struct InputWaveform: View {
    let label: String
    let columns: [WaveformColumn]
    let amplitudeRange: Float
    let tint: Color
    let identifier: String

    private var signalState: String {
        if columns.isEmpty { return "입력 없음" }
        return columns.allSatisfy { $0.minimum == 0 && $0.maximum == 0 } ? "평탄" : "수신 중"
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(label).font(.caption2.monospaced().bold()).foregroundStyle(tint)
            Canvas { context, size in
                let center = size.height / 2
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: center))
                grid.addLine(to: CGPoint(x: size.width, y: center))
                for fraction in [0.25, 0.5, 0.75] {
                    let x = size.width * fraction
                    grid.move(to: CGPoint(x: x, y: 0))
                    grid.addLine(to: CGPoint(x: x, y: size.height))
                }
                context.stroke(grid, with: .color(.white.opacity(0.12)), lineWidth: 0.5)
                guard !columns.isEmpty, amplitudeRange > 0 else { return }
                let scale = size.height * 0.44 / CGFloat(amplitudeRange)
                var extent = Path(), trace = Path()
                for (index, column) in columns.enumerated() {
                    let x = (CGFloat(index) + 0.5) * size.width / CGFloat(columns.count)
                    let high = center - CGFloat(column.maximum) * scale
                    let low = center - CGFloat(column.minimum) * scale
                    extent.move(to: CGPoint(x: x, y: high))
                    extent.addLine(to: CGPoint(x: x, y: low))
                    let midpoint = CGPoint(x: x, y: (high + low) / 2)
                    if index == 0 { trace.move(to: midpoint) } else { trace.addLine(to: midpoint) }
                }
                context.stroke(extent, with: .color(tint.opacity(0.8)), lineWidth: 1)
                context.stroke(trace, with: .color(tint), lineWidth: 1)
            }
            .frame(height: 30)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 4))
            .clipped()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) 입력 파형")
        .accessibilityValue(signalState)
        .accessibilityIdentifier(identifier)
    }
}

/// Only this small subtree observes 60 Hz snapshots; the camera controls,
/// diagnostic report and DSP retain their independent update cadence.
private struct StereoWaveformPanel: View {
    @ObservedObject var display: WaveformDisplayModel
    let green: Color
    let freshFPS: Int
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                InputWaveform(label: "L", columns: display.preview?.left ?? [],
                    amplitudeRange: display.preview?.amplitudeRange ?? 1, tint: green, identifier: "leftWaveform")
                InputWaveform(label: "R", columns: display.preview?.right ?? [],
                    amplitudeRange: display.preview?.amplitudeRange ?? 1, tint: .cyan, identifier: "rightWaveform")
            }
            Text("최근 \(freshFPS) fps · 10ms 파형 · 공통 자동 배율 · 최대 60fps")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .accessibilityIdentifier("liveWaveformPerformance")
        }
    }
}

private final class CameraSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    override func layoutSubviews() {
        super.layoutSubviews()
        if let connection = preview.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90 // App interface is locked to portrait.
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> CameraSurface {
        let view = CameraSurface()
        view.backgroundColor = .black
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "cameraPreview"
        view.accessibilityLabel = "전체 화면 카메라 미리보기"
        view.preview.videoGravity = .resizeAspectFill
        view.preview.session = session
        return view
    }
    func updateUIView(_ view: CameraSurface, context: Context) {
        view.setNeedsLayout()
    }
}

struct CaptureView: View {
    @ObservedObject var model: CaptureModel
    @StateObject private var camera = CameraModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showDetails = false
    @State private var showCalibration = false
    @State private var showSpatialGuide = false
    private let green = Color(red: 0.48, green: 0.95, blue: 0.68)
    private var busy: Bool { camera.isBusy || model.isBusy }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if camera.usesSpatialCamera {
                SpatialCameraPreview(session: camera.spatialCamera.session).ignoresSafeArea()
            } else {
                CameraPreview(session: camera.session).ignoresSafeArea()
            }
            if camera.phase != .running || camera.isSynthetic {
                VStack(spacing: 14) {
                    Image(systemName: "camera").font(.system(size: 44, weight: .light))
                    Text(camera.isSynthetic ? "합성 UI 검사 · 실제 영상 없음" : "실시간 카메라")
                        .font(.title3.bold())
                    Text(camera.status).font(.subheadline).multilineTextAlignment(.center)
                        .accessibilityIdentifier("cameraStatus")
                }.foregroundStyle(.white.opacity(0.75)).padding(32)
                    .opacity(camera.isSynthetic && model.spatial.report.bearing != nil ? 0 : 1)
            }
            SpatialOverlay(spatial: model.spatial,camera: camera,synthetic: model.isSynthetic)
                .ignoresSafeArea() // Projection viewport must match the edge-to-edge ARSCNView.
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("SOUNDFIELD").font(.headline.monospaced()).foregroundStyle(green)
                        Text("소리 방향 · 위치").font(.caption)
                    }
                    Spacer()
                    Button { showCalibration = true } label: {
                        Label("방향 비교", systemImage: "arrow.left.and.right")
                            .font(.caption.bold()).padding(10)
                    }
                    .background(.black.opacity(0.55), in: Capsule())
                    .accessibilityIdentifier("calibrationButton")
                    Button { showDetails = true } label: {
                        Label("측정 상세", systemImage: "waveform.path")
                            .font(.caption.bold()).padding(10)
                    }
                    .background(.black.opacity(0.55), in: Capsule())
                    .accessibilityIdentifier("detailsButton")
                }.padding(20)
                .background(LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom))
                Button { showSpatialGuide = true } label: {
                    Label("소리 찾기 · 방향 보정",systemImage: "scope").font(.subheadline.bold()).padding(.horizontal,16).padding(.vertical,9)
                }.background(.black.opacity(0.7),in: Capsule()).foregroundStyle(green)
                    .accessibilityIdentifier("spatialGuideButton")
                if model.isSynthetic {
                    Text("합성 테스트 · 아이폰 실측 아님").font(.caption.bold()).foregroundStyle(.orange)
                        .accessibilityIdentifier("liveSyntheticBanner")
                }
                Spacer()
                VStack(spacing: 12) {
                    SoundHeatLegend(spatial: model.spatial)
                    HStack(spacing: 18) {
                        meter("L", index: 0)
                        meter("R", index: 1)
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(model.report.trend?.estimateSeconds.map { String(format: "%+.1f µs", $0 * 1_000_000) } ?? "—")
                                .font(.title3.monospacedDigit().bold()).foregroundStyle(green)
                                .accessibilityIdentifier("liveLagValue")
                            Text("연속 신호 시간차").font(.caption2)
                        }
                    }
                    StereoWaveformPanel(display: model.waveformDisplay, green: green,
                        freshFPS: model.report.waveformDisplay?.recentFreshFPS ?? 0)
                    Text(model.report.status).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("liveCaptureStatus")
                        .accessibilityValue("분석 \(model.report.analyzedFrames)구간")
                    Picker("카메라와 마이크 방향", selection: $model.source) {
                        Text("후면").tag("back")
                        Text("전면").tag("front")
                    }.pickerStyle(.segmented).disabled(busy)
                    Button {
                        if busy {
                            camera.stop(); model.stop()
                        } else {
                            Task {
                                if await camera.start(front: model.source == "front") {
                                    model.start(cameraPreviewActive: camera.phase == .running && !camera.isSynthetic,
                                                startControl: "cameraAndAudio")
                                }
                            }
                        }
                    } label: {
                        Label(busy ? "계측 중지" : "카메라·수음 시작", systemImage: busy ? "stop.fill" : "camera.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }.buttonStyle(.borderedProminent).tint(green).foregroundStyle(.black)
                        .accessibilityIdentifier("liveCaptureButton")
                    Text("영상·원음 저장 없음 · 실험 열지도 · 빌드 7").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(18)
                .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 22))
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
        .foregroundStyle(.white)
        .sheet(isPresented: $showDetails) {
            NavigationStack {
                CaptureDetailsView(model: model)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { showDetails = false } } }
            }.presentationDetents([.large])
        }
        .sheet(isPresented: $showCalibration) {
            NavigationStack {
                DirectionCalibrationView(model: model)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { showCalibration = false } } }
            }.presentationDetents([.large])
        }
        .sheet(isPresented: $showSpatialGuide) {
            NavigationStack { SpatialGuide(model: model,camera: camera) }.presentationDetents([.large])
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                camera.stop(reason: "백그라운드로 이동해 카메라를 해제했습니다.")
                model.enteredBackground()
            }
        }
        .onChange(of: showDetails) { _, _ in model.waveformDisplay.setVisible(!showDetails && !showCalibration && !showSpatialGuide) }
        .onChange(of: showCalibration) { _, _ in model.waveformDisplay.setVisible(!showDetails && !showCalibration && !showSpatialGuide) }
        .onChange(of: showSpatialGuide) { _, _ in model.waveformDisplay.setVisible(!showDetails && !showCalibration && !showSpatialGuide) }
        .onAppear {
            model.spatialPoseProvider = { [weak camera] midpoint,duration in
                camera?.spatialCamera.aligned(midpoint: midpoint,duration: duration)
            }
            camera.onTrackingLost = { [weak model] in model?.spatial.trackingLost() }
            // Cleanup must not depend on SwiftUI rendering an intermediate
            // phase; permission or route failure can return to idle immediately.
            model.onStopped = { [weak camera] in
                if let camera, camera.isBusy { camera.stop() }
            }
            camera.onInterrupted = { [weak model] in
                if let model, model.isBusy { model.stop(reason: "카메라가 중지되어 수음도 해제했습니다.") }
            }
        }
    }

    private func meter(_ title: String, index: Int) -> some View {
        let value = model.report.latest?.analysis.channels[index].rmsDbfs
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold())
            Text(value.map { String(format: "%.0f", $0) } ?? "—").font(.title3.monospacedDigit())
            Text("dBFS").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
