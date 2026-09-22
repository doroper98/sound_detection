import SwiftUI
import StereoCore

private struct SharedReport: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct CaptureDetailsView: View {
    @ObservedObject var model: CaptureModel
    @State private var sharedReport: SharedReport?
    private let green = Color(red: 0.48, green: 0.95, blue: 0.68)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SOUNDFIELD / iPHONE").font(.caption.monospaced()).foregroundStyle(green)
                    Text("스테레오 입력").font(.largeTitle.bold())
                    Text("계속 듣고, 최근 변화를 계산합니다.").foregroundStyle(.secondary)
                }
                if model.isSynthetic {
                    Text("합성 테스트 · 아이폰 실측 아님")
                        .font(.callout.bold()).foregroundStyle(.orange)
                        .accessibilityIdentifier("syntheticBanner")
                }
                VStack(alignment: .leading, spacing: 12) {
                    Picker("수음 방향", selection: $model.source) {
                        Text("후면").tag("back")
                        Text("전면").tag("front")
                    }
                    .pickerStyle(.segmented).disabled(model.isBusy)
                    .accessibilityIdentifier("sourcePicker")
                    Text("아이폰을 세로로 고정하고 소리를 왼쪽·정면·오른쪽에서 번갈아 내세요.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button {
                        if model.isBusy { model.stop() } else { model.start() }
                    } label: {
                        Label(model.isBusy ? (model.phase == .requestingPermission ? "취소" : "수음 중지") : "스테레오 수음 시작",
                              systemImage: model.isBusy ? "stop.fill" : "mic.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent).tint(green).foregroundStyle(.black)
                    .accessibilityIdentifier("captureButton")
                    Text(model.report.status).font(.footnote)
                        .accessibilityIdentifier("captureStatus")
                    Text("오디오 알림 \(model.report.audioEvents.count) · 초기 재설정 \(model.report.startupEngineRestarts)")
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("audioEventCount")
                    HStack {
                        Label("요청 2채널", systemImage: "waveform")
                        Spacer()
                        Text("실제 \(model.report.tapFormatChannels.map(String.init) ?? "—")채널")
                            .accessibilityIdentifier("actualChannels")
                    }.font(.caption).foregroundStyle(.secondary)
                }.card()

                let analysis = model.report.latest?.analysis
                HStack(spacing: 12) {
                    channelCard("L · 왼쪽", level: analysis?.channels[0])
                    channelCard("R · 오른쪽", level: analysis?.channels[1])
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("마지막 구간 시간차").font(.headline)
                    Text(analysis?.rightMinusLeftLagSeconds.map { String(format: "%+.1f µs", $0 * 1_000_000) } ?? "—")
                        .font(.system(size: 34, weight: .semibold, design: .monospaced))
                        .foregroundStyle(green).accessibilityIdentifier("lagValue")
                    Text(analysis.map { statusText($0.status) } ?? "수음을 시작하면 표시됩니다.")
                        .font(.subheadline).accessibilityIdentifier("lagStatus")
                    Text("+는 오른쪽 신호가 늦다는 뜻입니다. 검색 범위 ±1 ms, 정수 샘플 단위.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let reading = model.report.latest {
                        Text("\(Int(reading.analysis.sampleRate)) Hz · \(reading.analysis.sampleCount) samples · 건너뛴 버퍼 \(reading.skippedBuffers)")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }.card()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("연속 관측").font(.headline)
                        Spacer()
                        Text("최근 2초").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(model.report.trend?.estimateSeconds.map { String(format: "%+.1f µs", $0 * 1_000_000) } ?? "—")
                        .font(.title.monospacedDigit().bold()).foregroundStyle(green)
                        .accessibilityIdentifier("trackedLagValue")
                    Text(trendDescription(model.report.trend?.state))
                        .font(.subheadline).accessibilityIdentifier("trendStatus")
                    LagHistoryPlot(history: model.report.trend?.history ?? [], color: green)
                        .frame(height: 96).accessibilityLabel("최근 2초의 채널 시간차 변화 그래프")
                    if let trend = model.report.trend {
                        Text("최근 0.5초 유효 \(trend.recentAccepted)/\(trend.recentTotal) · 산포 \(trend.spreadSeconds.map { String(format: "%.1f µs", $0 * 1_000_000) } ?? "—")")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Text(model.report.latestOrientation.map { String(format: "시작 대비 기기 회전 %.1f°", $0.rotationFromStartDegrees) } ?? model.report.motionStatus)
                        .font(.footnote).accessibilityIdentifier("motionStatus")
                    Text("회전은 기기 자세입니다. 음원 방향·이동거리 추정은 아직 교정 전입니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }.card()

                VStack(alignment: .leading, spacing: 12) {
                    Text("소리 위치 기록").font(.headline)
                    Text("각 위치에서 종이 비비기처럼 주파수가 다양한 소리를 내며 눌러주세요. 현재 통계만 저장합니다.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        ForEach(["왼쪽", "정면", "오른쪽"], id: \.self) { side in
                            Button(side) { model.mark(side: side) }
                                .buttonStyle(.bordered).frame(maxWidth: .infinity)
                                .disabled(model.phase != .running || model.report.latest == nil)
                        }
                    }
                    Text("기록 \(model.report.markedReadings.count)/12 · 최근 기록 유지")
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("markCount")
                }.card()
                Text("내장 스테레오에는 기기 음향 처리가 포함될 수 있습니다. 이 시간차는 아직 물리 마이크의 도달 시간차로 교정되지 않아 방향·거리로 환산하지 않습니다.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button {
                    if let url = model.export() { sharedReport = SharedReport(url: url) }
                } label: {
                    Label("진단 JSON 공유", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).accessibilityIdentifier("exportButton")
                Text("녹음 파일·원음·영상은 저장하지 않습니다. 공유를 누르면 수음을 중지합니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }
        .background(Color(red: 0.055, green: 0.075, blue: 0.07))
        .sheet(item: $sharedReport) { ShareSheet(url: $0.url) }
        .alert("보고서 저장 오류", isPresented: Binding(get: { model.exportError != nil }, set: { if !$0 { model.exportError = nil } })) {
            Button("확인") { model.exportError = nil }
        } message: { Text(model.exportError ?? "") }
    }

    private func channelCard(_ name: String, level: ChannelLevel?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(name).font(.headline)
            Text(level?.rmsDbfs.map { String(format: "%.1f", $0) } ?? "—")
                .font(.title2.monospacedDigit().bold())
            Text("dBFS · \(level.map { $0.active ? "신호 있음" : "무음" } ?? "대기")")
                .font(.caption).foregroundStyle(.secondary)
            ProgressView(value: min(1, max(0, ((level?.rmsDbfs ?? -90) + 90) / 90)))
                .tint(level?.clipped == true ? .orange : green)
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private func statusText(_ status: LagStatus) -> String {
        switch status {
        case .silentChannel: return "한쪽 이상에 분석 가능한 신호가 없습니다."
        case .clipped: return "입력이 포화되어 시간차를 표시하지 않습니다."
        case .duplicate: return "좌우 복제 신호 의심 · 시간차 보류"
        case .ambiguous: return "시간차 후보가 여러 개라 확정할 수 없습니다."
        case .weakCorrelation: return "두 신호의 상관성이 낮아 시간차를 보류합니다."
        case .searchBoundary: return "검색 범위 경계에 있어 시간차를 보류합니다."
        case .candidate: return "신호 시간차 후보 · 방향 교정 전"
        }
    }

    private func trendDescription(_ state: TrendState?) -> String {
        switch state {
        case .collecting: return "연속 관측 수집 중"
        case .tracking: return "최근 중앙값 · 위치 정확도를 뜻하지 않습니다."
        case .changing: return "시간차 변화 또는 흔들림이 큽니다."
        case .noReliableSignal: return "신뢰할 신호가 부족해 누적값을 보류합니다."
        case .stale: return "새 관측을 기다립니다. 이전 추정값은 숨깁니다."
        case .stopped: return "계측 중지 · 마지막 변화 기록"
        case nil: return "수음을 시작하면 자동으로 누적합니다."
        }
    }
}

private struct LagHistoryPlot: View {
    let history: [TimedLag]
    let color: Color

    var body: some View {
        Canvas { context, size in
            var axis = Path()
            axis.move(to: CGPoint(x: 0, y: size.height / 2))
            axis.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(axis, with: .color(.secondary.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            let end = history.last?.timeSeconds ?? 0
            var path = Path(), connected = false
            for item in history {
                guard let lag = item.lagSeconds else { connected = false; continue }
                let x = (item.timeSeconds - (end - 2)) / 2 * size.width
                let y = (1 - min(1, max(-1, lag / 0.001))) / 2 * size.height
                let point = CGPoint(x: x, y: y)
                if connected { path.addLine(to: point) } else { path.move(to: point) }
                connected = true
            }
            context.stroke(path, with: .color(color), lineWidth: 2)
        }
        .overlay(alignment: .topLeading) { Text("+1 ms").font(.caption2).foregroundStyle(.secondary) }
        .overlay(alignment: .bottomLeading) { Text("−1 ms").font(.caption2).foregroundStyle(.secondary) }
    }
}

private extension View {
    func card() -> some View {
        self.padding(16).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
    }
}
