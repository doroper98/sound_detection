import AVFoundation
import SwiftUI

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
    private let green = Color(red: 0.48, green: 0.95, blue: 0.68)
    private var busy: Bool { camera.isBusy || model.isBusy }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session)
                .ignoresSafeArea()
            if camera.phase != .running || camera.isSynthetic {
                VStack(spacing: 14) {
                    Image(systemName: "camera").font(.system(size: 44, weight: .light))
                    Text(camera.isSynthetic ? "합성 UI 검사 · 실제 영상 없음" : "실시간 카메라")
                        .font(.title3.bold())
                    Text(camera.status).font(.subheadline).multilineTextAlignment(.center)
                        .accessibilityIdentifier("cameraStatus")
                }.foregroundStyle(.white.opacity(0.75)).padding(32)
            }
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("SOUNDFIELD").font(.headline.monospaced()).foregroundStyle(green)
                        Text("카메라 · 스테레오 계측").font(.caption)
                    }
                    Spacer()
                    Button { showDetails = true } label: {
                        Label("측정 상세", systemImage: "waveform.path")
                            .font(.subheadline.bold()).padding(11)
                    }
                    .background(.black.opacity(0.55), in: Capsule())
                    .accessibilityIdentifier("detailsButton")
                }.padding(20)
                .background(LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom))
                if model.isSynthetic {
                    Text("합성 테스트 · 아이폰 실측 아님").font(.caption.bold()).foregroundStyle(.orange)
                        .accessibilityIdentifier("liveSyntheticBanner")
                }
                Spacer()
                VStack(spacing: 12) {
                    HStack(spacing: 18) {
                        meter("L", index: 0)
                        meter("R", index: 1)
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(model.report.trend?.estimateSeconds.map { String(format: "%+.1f µs", $0 * 1_000_000) } ?? "—")
                                .font(.title3.monospacedDigit().bold()).foregroundStyle(green)
                                .accessibilityIdentifier("liveLagValue")
                            Text("연속 시간차 · 방향 교정 전").font(.caption2)
                        }
                    }
                    Text(model.report.status).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("liveCaptureStatus")
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
                    Text("영상·원음 저장 없음 · 빌드 3").font(.caption2).foregroundStyle(.secondary)
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                camera.stop(reason: "백그라운드로 이동해 카메라를 해제했습니다.")
                model.enteredBackground()
            }
        }
        .onAppear {
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
