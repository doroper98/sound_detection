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
    @State private var showSavedReports=false
    private let green = Color(red: 0.48, green: 0.95, blue: 0.68)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SOUNDFIELD / iPHONE").font(.caption.monospaced()).foregroundStyle(green)
                    Text(model.usesFOA ? "공간 오디오 입력" : "스테레오 입력").font(.largeTitle.bold())
                    Text("계속 듣고, 최근 변화를 계산합니다.").foregroundStyle(.secondary)
                    Text("실험 열지도 · 빌드 11 · 영상·원음 저장 없음").font(.caption).foregroundStyle(.secondary)
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
                    Text("방향 열지도는 카메라 화면의 후면 카메라·수음 시작을 사용하세요. 아래 버튼은 별도 스테레오 검사입니다. 이전 진단은 아래 목록에 보관됩니다.")
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
                    if let before=model.report.spatial?.calibrationBeforeStop {
                        Text("중지 전 보정: \(before.instruction)").font(.footnote)
                            .accessibilityIdentifier("lastSpatialCalibration")
                    }
                    if let sync=model.report.spatial?.synchronization, sync.receivedFrames>0 {
                        Text("소리·자세 연결 \(sync.matchedFrames) · 지연 후 연결 \(sync.recoveredAfterWait)")
                            .font(.caption).accessibilityIdentifier("spatialSyncSummary")
                    }
                    Text("오디오 알림 \(model.report.audioEvents.count) · 초기 재설정 \(model.report.startupEngineRestarts)")
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("audioEventCount")
                    if let display = model.report.waveformDisplay {
                        Text("파형 마지막 표시 \(display.recentFreshFPS) fps · 최대 60fps · 10ms 파형 · 공통 자동 배율 · 누적 \(display.presentedFrames) · 표시 지연 \(Int(display.presentationDelaySeconds * 1000))ms")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .accessibilityIdentifier("waveformPerformance")
                    }
                    if let event = model.report.audioEvents.last {
                        Text("마지막 알림 \(event.reasonCode.map(String.init) ?? "—") · 입력 확인 \(event.routeMatches ? "정상" : "불일치") · 당시 분석 \(event.analyzedFramesBeforeEvent)")
                            .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("lastAudioEvent")
                    }
                    HStack {
                        Label("요청 \(model.report.requestedChannels)채널", systemImage: "waveform")
                        Spacer()
                        Text("실제 \(model.report.tapFormatChannels.map(String.init) ?? "—")채널")
                            .accessibilityIdentifier("actualChannels")
                    }.font(.caption).foregroundStyle(.secondary)
                }.card()

                if model.usesFOA { currentShareButton }
                if let foa=model.report.foa {
                    VStack(alignment: .leading,spacing: 8) {
                        Text("4채널 공간 오디오").font(.headline)
                        Text("입력 \(foa.capture.foaBuffers)버퍼 · 분석 \(foa.received) · 카메라 연결 \(foa.matched)")
                            .accessibilityIdentifier("foaSummary")
                        Text("실제 FOA \(foa.capture.foaFormat?.channels ?? 0)채널 · 별도 Stereo \(foa.capture.stereoFormat?.channels ?? 0)채널")
                        Text("상태: \(foa.state) · 시간 누락 \(foa.capture.gaps)")
                        if let timeline=foa.timeline {
                            Text("시각 기록 \(timeline.history.count)구간 · UTC/경과 시간 포함")
                                .accessibilityIdentifier("foaTimelineSummary")
                            Text("최근 최대 \(timeline.capacity)구간 · 이전 \(timeline.omittedEarlierEntries)구간은 누계만 유지")
                                .font(.caption)
                        }
                        Text("카메라 축 대응·물리 정확도 미검증 · 거리 계산 안 함").font(.caption)
                        Text("열지도 파랑 → 빨강: 해당 대역 입력 크기. dBFS는 폰에서 받은 신호 크기이며 음원의 실제 소음도(dB SPL)가 아닙니다.").font(.caption)
                        if let error=foa.capture.lastError { Text(error).font(.footnote) }
                    }.card()
                }
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
                    Text("이 회전 값은 기기 자세입니다. 카메라의 소리 찾기는 별도 AR 이동 추적과 경험적 보정을 사용합니다.")
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
                Text("내장 스테레오에는 기기 음향 처리가 포함될 수 있습니다. 시간차를 물리 마이크 간격으로 바로 환산하지 않습니다. 카메라의 방향·위치 후보는 보정된 경험적 응답을 사용하며 정확도는 미검증입니다.")
                    .font(.footnote).foregroundStyle(.secondary)
                if !model.usesFOA { currentShareButton }
                if !model.savedReports.isEmpty {
                    VStack(alignment: .leading,spacing: 12) {
                        Button { showSavedReports.toggle() } label: {
                            HStack {
                                Text("이전 진단 · 최근 5개")
                                Spacer()
                                Image(systemName: showSavedReports ? "chevron.up" : "chevron.down")
                            }.contentShape(Rectangle())
                        }.accessibilityIdentifier("savedReportsToggle")
                            .accessibilityValue(showSavedReports ? "펼침" : "접힘")
                        if showSavedReports {
                        ForEach(model.savedReports) { saved in
                            Button {
                                if let url=model.exportSaved(saved) { sharedReport=SharedReport(url: url) }
                            } label: {
                                VStack(alignment: .leading,spacing: 3) {
                                    Text(saved.date.formatted(date: .abbreviated,time: .standard))
                                    Text(saved.status).font(.caption).lineLimit(2)
                                    Text(saved.version).font(.caption2)
                                }.frame(maxWidth: .infinity,alignment: .leading)
                            }.accessibilityIdentifier("savedReportShare")
                        }
                        }
                    }.card()
                }


                Text("녹음 파일·원음·영상은 저장하지 않습니다. 공유에는 상대 AR 좌표와 마지막 추정 통계가 포함되며, 수음을 중지합니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }
        .background(Color(red: 0.055, green: 0.075, blue: 0.07))
        .sheet(item: $sharedReport) { ShareSheet(url: $0.url) }
        .alert("보고서 저장 오류", isPresented: Binding(get: { model.exportError != nil }, set: { if !$0 { model.exportError = nil } })) {
            Button("확인") { model.exportError = nil }
        } message: { Text(model.exportError ?? "") }
    }

    private var currentShareButton: some View {
        Button {
            if let url=model.export() { sharedReport=SharedReport(url: url) }
        } label: { Label("진단 JSON 공유",systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
            .buttonStyle(.bordered).accessibilityIdentifier("exportButton")
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

struct DirectionCalibrationView: View {
    @ObservedObject var model: CaptureModel
    @State private var sharedReport: SharedReport?
    private var data: DirectionCalibrationReport? { model.report.calibration }
    private var step: Int { data?.nextStep ?? 0 }
    private var measuring: Bool { data?.state == "preparing" || data?.state == "measuring" }
    private var side: String { ["왼쪽", "정면", "오른쪽"][min(step, 5) % 3] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("입력 비교 · 상세 검사").font(.largeTitle.bold())
                Text("소리 위치를 표시할 보정은 카메라 화면의 ‘소리 찾기 · 방향 보정’에서 진행하세요.")
                    .font(.subheadline)
                Text("소리 위치를 바꾸면 좌우 시간차도 반복해서 달라지는지 확인합니다.")
                    .foregroundStyle(.secondary)
                if model.isSynthetic { Text("합성 테스트 · 실제 방향 교정 아님").foregroundStyle(.orange) }
                VStack(alignment: .leading, spacing: 8) {
                    Text("1  폰을 세로로 고정하고 후면 카메라로 수음을 시작하세요.")
                    Text("2  폰 뒤 카메라가 보는 쪽에 소리 하나만 두세요. 폰을 돌리지 말고, 화면 기준 왼쪽·정면·오른쪽으로 소리를 옮기세요.")
                    Text("3  약 1m의 비슷한 거리에서 종이를 계속 비비세요. 각 위치에서 버튼을 누르면 3초 준비 후 5초를 모읍니다. 같은 순서로 두 번 반복합니다.")
                }.font(.subheadline).card()
                VStack(alignment: .leading, spacing: 12) {
                    Text(step < 6 ? "\(step + 1)/6 · \(step / 3 + 1)회차 · \(side)" : "6/6 · 비교 완료")
                        .font(.title2.bold()).accessibilityIdentifier("calibrationStep")
                    Text(progressText).font(.headline.monospacedDigit())
                        .accessibilityIdentifier("calibrationProgress")
                    if measuring {
                        ProgressView(value: data?.state == "preparing" ? 0 : 5 - min(5, data?.secondsRemaining ?? 5), total: 5)
                        Button("이번 구간 취소") { model.cancelCalibrationTrial() }
                            .buttonStyle(.bordered).accessibilityIdentifier("calibrationCancel")
                    } else if step < 6 {
                        Button("\(side) 5초 측정") { model.beginCalibrationTrial() }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("calibrationStart")
                            .disabled(model.phase != .running || model.report.requestedSource != "back" || data?.state == "attemptLimit")
                    }
                    if model.phase != .running {
                        Text("카메라 화면에서 수음을 시작한 뒤 돌아오세요. 새 수음을 시작하면 이전 비교 기록은 초기화됩니다.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if model.report.requestedSource != "back" {
                        Text("이번 비교는 후면 입력으로 진행합니다. 수음을 중지하고 후면을 선택하세요.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }.card()
                if step == 6 {
                    Text(comparisonText).font(.headline).accessibilityIdentifier("calibrationComparison")
                }
                ForEach(data?.trials ?? []) { trial in
                    VStack(alignment: .leading, spacing: 7) {
                        Text("\(trial.repetition)회차 · \(sideName(trial.declaredSide)) · \(trial.completed ? "수집 완료" : "중단")").font(.headline)
                        Text("시간차 \(trial.medianLagSeconds.map { String(format: "%+.1f µs", $0 * 1e6) } ?? "—") · 후보 \(Int((trial.candidateFraction * 100).rounded()))%")
                        Text("관측 \(trial.observations.count)구간 · \(String(format: "%.1f", trial.coveredSeconds))초 / 5초")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Text("R−L 레벨 \(trial.medianRightMinusLeftDb.map { String(format: "%+.1f dB", $0) } ?? "—") · 폰 회전 \(trial.maxRotationDegrees.map { String(format: "%.1f°", $0) } ?? "—")")
                            .font(.caption.monospacedDigit())
                        Text(trial.usable ? "비교에 사용할 통계 확보" : trial.qualityIssues.map(issueName).joined(separator: " · "))
                            .font(.footnote).foregroundStyle(trial.usable ? .green : .orange)
                        if let reason = trial.interruptionReason { Text(reason).font(.caption).foregroundStyle(.secondary) }
                    }.card()
                }
                Text("중앙값은 채택된 후보만의 요약입니다. 후보 비율이 낮으면 방향 비교를 보류합니다. 같은 차이가 반복돼도 각도·거리 교정 완료를 뜻하지 않습니다.")
                    .font(.footnote).foregroundStyle(.secondary)
                HStack {
                    Button("비교 기록 초기화") { model.resetCalibration() }.disabled(measuring)
                        .accessibilityIdentifier("calibrationReset")
                    Spacer()
                    Button("계측 중지") { model.stop() }.disabled(!model.isBusy)
                }.buttonStyle(.bordered)
                Button {
                    if let url = model.export() { sharedReport = SharedReport(url: url) }
                } label: { Label("비교 JSON 공유", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("calibrationExport")
                Text("공유하면 수음이 중지됩니다. 구간별 통계만 포함하고 원음·파형·영상은 포함하지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }
        .background(Color(red: 0.055, green: 0.075, blue: 0.07))
        .sheet(item: $sharedReport) { ShareSheet(url: $0.url) }
        .alert("보고서 저장 오류", isPresented: Binding(get: { model.exportError != nil }, set: { if !$0 { model.exportError = nil } })) {
            Button("확인") { model.exportError = nil }
        } message: { Text(model.exportError ?? "") }
    }

    private var progressText: String {
        switch data?.state {
        case "preparing": return "준비 \(Int(ceil(data?.secondsRemaining ?? 0)))초 · 손을 떼고 소리를 내세요"
        case "measuring": return "수집 중 · \(String(format: "%.1f", data?.secondsRemaining ?? 0))초 남음"
        case "complete": return "여섯 구간을 JSON으로 공유해 주세요"
        case "attemptLimit": return "시도 상한에 도달했습니다. 공유 후 초기화하세요"
        default: return "소리 위치를 준비한 뒤 눌러주세요"
        }
    }

    private var comparisonText: String {
        switch data?.comparison {
        case "repeatableSeparation": return "위치별 시간차가 두 번 같은 순서로 구분됐습니다. 다음 교정을 위한 자료가 확보됐습니다."
        case "notRepeatable": return "두 번의 시간차가 일치하지 않아 방향 비교를 보류합니다."
        case "noClearSeparation": return "위치별 시간차가 충분히 구분되지 않았습니다."
        default: return "품질이 부족한 구간이 있어 방향 비교를 보류합니다. 아래 원인을 확인하세요."
        }
    }

    private func sideName(_ side: String) -> String { ["left": "왼쪽", "center": "정면", "right": "오른쪽"][side] ?? side }
    private func issueName(_ issue: String) -> String {
        ["interrupted": "구간 중단", "insufficientCoverage": "수집량 부족", "insufficientLagCandidates": "시간차 후보 부족",
         "missingOrientation": "자세 자료 부족", "phoneMoved": "폰이 5° 이상 움직임", "sampleRateChanged": "샘플률 변경",
         "unstableLag": "시간차 흔들림", "observationLimit": "통계 상한 도달"][issue] ?? issue
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
