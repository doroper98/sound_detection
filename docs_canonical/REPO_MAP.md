# 파일 지도

| 경로 | 역할 |
|---|---|
| native/ios/ | SwiftUI iPhone 스테레오 진단 앱·Xcode 프로젝트·설치 안내 |
| native/ios/Packages/StereoCore/ | UI·AVFoundation·좌표와 독립된 좌우 PCM 레벨/정규화 상호상관 진단 및 Swift 테스트 |
| native/ios/Packages/StereoCore/Sources/StereoCore/RotationCalibrationDiagnostics.swift | 회전 보정 6단계 요약·실패 조건·방법별 적합 진단 |
| native/ios/SoundFieldStereo/CaptureModel.swift | 내장 stereo 소스 선택, 실제 포맷 확인, bounded PCM 처리·수명·통계 보고서 |
| native/ios/SoundFieldStereoUITests/ | 명시적으로 표시한 DEBUG 합성 입력의 iOS UI 검증 (실기기 결과 아님) |
| src/App.tsx | 실험 상태, 입력 패널, 관측, 내보내기, 가이드/릴리즈 |
| src/main.tsx | / 시뮬레이터와 /diagnostics 실제 입력 화면의 lazy 분리 |
| src/live/ | 실제 카메라, 권한/캡처 수명 관리, PCM 채널 진단, JSON 내보내기 |
| src/live/LiveSpectrum.tsx | /listen 연속 수음 UI, 주파수·채널 선택, 통계 JSON |
| src/live/monitor.ts | 연속 입력 수집과 취소·장치 종료·무응답 정리 |
| src/live/spectrum.ts | DOM/위치 정보 없는 주파수·대역 RMS 분석 |
| tests/spectrum.test.ts, tests/monitor.test.ts | 주파수·진폭·대역 분리·무음·포화, 캡처 수명 검증 |
| public/audio-diagnostics.worklet.js | 입력 PCM 채널 수를 유지하는 음성 수집, 무음 출력 |
| tests/live.test.ts | 채널/복제/무음 판정, Worklet 전송, 늦은 권한 응답 취소 |
| tests/e2e/diagnostics.spec.ts | 합성 입력의 UI/캡처 해제/채널 불일치 검증, 실기기 검증 아님 |
| src/acoustics.ts | 시뮬레이터의 물리 기준값·장치 프리셋·센서 배치, 독립 엔진의 호출 범위 |
| packages/localization/ | 3D 화면과 독립된 PCM/DSP/위치 추정 패키지, API 문서와 CLI replay |
| src/simulation.ts | 정답 위치를 아는 유일한 PCM 합성 어댑터 |
| src/heatmap.ts | PCM 레벨·포화 측정과 고정 색상 척도, 위치 추정과 분리 |
| src/layout.css | viewport 맞춤, 모바일 탭·설정 패널 |
| tests/engine.test.ts | PCM 분석, 좌표/화면 독립성, 임의 공간과 배열 회귀 |
| src/room.ts | 공유 3D 실내 geometry, 조명, 리소스 정리 |
| src/components/SpatialView.tsx | 왼쪽 orbit/raycast 배치와 파동 |
| src/components/PhoneView.tsx | 카메라 광선 방향과 PCM 레벨 기반 열지도 |
| src/useAudio.ts | 클릭 후 작은 정현파 출력과 음소거 |
| src/styles.css | 반응형 UI, 폰 외형, 한국어/라틴 폰트 |
| tests/acoustics.test.ts | 음향·관측 가능성 단위 테스트 |
| tests/heatmap.test.ts | 볼륨별 PCM 레벨, 지연 불변, 포화와 표시 임계값 |
| tests/e2e/simulator.spec.ts | 사용자 동작과 모바일 검증 |
| scripts/ | 버전 준비 및 릴리즈 무결성 확인 |
| .github/workflows/ | main/PR 검증, 태그 릴리즈, 수동 Cloudflare 배포 |
| public/_headers | Cloudflare 보안 헤더 |
| wrangler.jsonc | soundfield-lab Pages 정적 배포 설정 (pages_build_output_dir) |
| docs/releases/ | 버전별 한국어 노트 (UI와 GitHub가 공유) |
| docs/reports/ | 실기기 진단 보고서 원본 JSON (원음·영상·장치 ID 없음), 해석은 TESTING.md |
| docs_canonical/ | 설계·모델·검증·운영 문서 |
| docs_canonical/LIDAR_SPATIAL_EXPORT_PLAN.md | 기본 기능 검증 뒤 검토할 라이다 공간 지도·음향 결합·내보내기 및 리마인드 조건 |
| docs_canonical/NATIVE_FIELD_VALIDATION.md | 현재 기본 기능의 실기기 반복 측정·기준 위치·오탐 억제·증거 수집 순서 |
| docs_canonical/NATIVE_LOCALIZATION_FEASIBILITY.md | 빌드 1~9 이력 인덱스, 실패 조건/미확정 원인, 시뮬레이션과 실제 입력 차이, 후속 기준 |
| scripts/audit-localization-feasibility.mjs | 기존 엔진과 네이티브 계산의 JS 전사 비교, 강한 반사·고정 지연·동일 자세 반복의 합성 반례 |
| scripts/audit-foa-feasibility.mjs | ACN/SN3D FOA 방향 계산·주파수별 분리 및 강한 반사/벡터 상쇄의 합성 반례 |
| docs/reports/2026-09-23-foa-feasibility-synthetic.json | 공개 FOA 경로 검토의 오프라인 결과, Apple 실제 인코더/실기기 검증 아님 |
| docs/reports/2026-09-23-localization-feasibility-synthetic.json | 오프라인 합성 실험 결과, 실기기 검증 아님 |
| docs/reports/2026-09-23-iphone17pro-build9-audio-only-analysis.json | 사용자 JSON 선택 필드와 해석, 원본 전체/실패한 6단계 기록 아님 |
| docs_canonical/FIELD_ACOUSTICS_FEASIBILITY.md | 사용자 논의, 주파수별 지도, 500m/±50m 기하 계산과 합성개구 검토, 미검증 범위 |
| docs_bp/README.md | 원본 BP 출처와 적용 방식 |

런타임 데이터는 브라우저 메모리에만 있다. 내보내기는 사용자의 기본 다운로드 경로에 JSON을 만든다. dist/는 정적 빌드, version.json은 package 버전을 노출한다. .local/은 로컬 실행/스크린샷/배포 보조 도구용이며 Git에서 제외한다. .wrangler/와 환경 파일도 제외한다.

- `native/ios/Packages/StereoCore/Sources/StereoCore/SpatialAudioSynchronization.swift`: 제한된 특징 요약 큐, AR 대응 사유와 시각 진단.
- `native/ios/Packages/StereoCore/Tests/StereoCoreTests/SpatialSynchronizationTests.swift`: 늦은 프레임 회복·정지·시각·대기 한계 회귀.
- `docs/reports/2026-09-23-iphone17pro-build8-stalled-analysis.json`: 사용자가 제공한 실측의 선택 필드와 해석, 원본 전체의 대체물이 아님.
