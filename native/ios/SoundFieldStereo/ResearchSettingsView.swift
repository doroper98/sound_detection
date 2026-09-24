import SwiftUI
import StereoCore

struct ResearchRecordingBadge: View {
    @ObservedObject private var research = ResearchRecordingModel.shared
    var body: some View {
        if research.recording {
            Text(String(format: "● REC %.0f초", research.seconds))
                .font(.caption.monospacedDigit().bold()).foregroundStyle(.red)
                .accessibilityIdentifier("researchREC")
        } else if research.finalizing {
            Text("저장 중").font(.caption).accessibilityIdentifier("researchFinalizing")
        }
    }
}

struct ResearchSettingsView: View {
    let busy: Bool
    @ObservedObject private var research = ResearchRecordingModel.shared
    @State private var shared: SharedReport?
    @State private var showSessions = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("연구 데이터").font(.headline)
                Spacer()
                ResearchRecordingBadge()
            }
            Toggle("원음과 폰 자세 저장", isOn: $research.enabled)
                .disabled(busy || research.finalizing || research.exporting)
                .accessibilityIdentifier("researchToggle")
            Text("기본 꺼짐. 켜면 주변 소리를 아이폰에 저장합니다. 자동 업로드는 없습니다.")
                .font(.caption).foregroundStyle(.secondary)
            if research.enabled {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("세션 이름", text: $research.label)
                        .textFieldStyle(.roundedBorder).accessibilityIdentifier("researchLabel")
                    HStack {
                        Picker("소리 위치", selection: $research.azimuth) {
                            ForEach([-90, -45, 0, 45, 90], id: \.self) { angle in
                                Text(angle == 0 ? "정면 0°" : "\(angle > 0 ? "오른쪽" : "왼쪽") \(abs(angle))°").tag(angle)
                            }
                        }
                        Picker("높이", selection: $research.elevation) {
                            Text("같은 높이 0°").tag(0)
                            Text("위쪽 30°").tag(30)
                        }
                    }.pickerStyle(.menu)
                    Picker("재생 소리", selection: $research.signal) {
                        Text("백색잡음").tag("whiteNoise")
                        Text("1 kHz 순음").tag("tone1kHz")
                        Text("음성").tag("speech")
                        Text("기타").tag("other")
                    }.pickerStyle(.menu)
                    Stepper("반복 \(research.repetition)회차", value: $research.repetition, in: 1...99)
                    Toggle("참고용 스테레오도 저장", isOn: $research.saveStereo)
                    Text("위치는 카메라 화면 기준입니다. 폰을 고정하고 1m 거리의 소리 위치를 골라 주세요. 이 값은 정답 기록에만 쓰며 열지도를 계산할 때는 쓰지 않습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }.disabled(busy || research.finalizing || research.exporting)
                Text("닫기 → 후면 카메라·수음 시작 → 10초 뒤 계측 중지 → 여기서 ZIP 공유. 한 번에 최대 120초.")
                    .font(.caption)
            }
            Text(research.status).font(.footnote).accessibilityIdentifier("researchStatus")
            if let latest = research.sessions.first {
                shareButton(latest, title: "연구 데이터 공유 · 최신 ZIP", identifier: "researchShare")
                DisclosureGroup("이전 연구 녹음 \(research.sessions.count)개", isExpanded: $showSessions) {
                    ForEach(research.sessions, id: \.sessionID) { session in
                        shareButton(session,
                            title: "\(session.labels.label) · \(Int(session.labels.azimuthDegrees))° · \(session.startedAtUTC)",
                            identifier: "savedResearchShare")
                    }
                }.font(.caption)
            }
            Text("ZIP 하나를 이 대화에 첨부하면 됩니다. 실제 녹음이 포함됩니다. 카메라 사진·영상은 저장하지 않습니다.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        .onAppear { research.reload() }
        .sheet(item: $shared) { ShareSheet(url: $0.url) }
    }

    private func shareButton(_ session: ResearchManifest, title: String, identifier: String) -> some View {
        Button {
            Task {
                if let url = await research.share(session) { shared = .init(url: url) }
            }
        } label: {
            Label(title, systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .disabled(busy || research.recording || research.finalizing || research.exporting)
        .accessibilityIdentifier(identifier)
    }
}
