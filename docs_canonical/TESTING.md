# 검증

## 2026-09-23 가능성 감사 (EXP-021)

[통합 이력·진단](NATIVE_LOCALIZATION_FEASIBILITY.md), [build9 선택 필드](../docs/reports/2026-09-23-iphone17pro-build9-audio-only-analysis.json), [합성 결과](../docs/reports/2026-09-23-localization-feasibility-synthetic.json)를 보존했다. 실제 실패한 보정의 단계별 통계가 없어 물리 원인은 미확정이다. 현재 방식의 보류/오검출 반례와 GCC 비교를 기기 정확도 증거로 쓰지 않는다.

재현은 `npm run build:engine` → `node scripts/audit-localization-feasibility.mjs`다. 3종 신호×12 seed, 방향 무관 고정 지연 3개, 단일/반복/독립 8자세의 3D 격자 결과를 출력한다. Swift 바이너리 대신 진단 계산의 JS 전사를 비교하므로 실제 앱 실행 검증과 구분한다. 강한 반사에서 두 방식 모두 틀린 결과도 삭제하지 않는다.

직전 `92b8c50`의 [Native iOS](https://github.com/doroper98/sound_detection/actions/runs/35857827251)와 [Verify](https://github.com/doroper98/sound_detection/actions/runs/35857827175)는 완료 SUCCESS다. 아래 이전 기록에서 대기 상태였던 UI 검사 대기 시간 보완의 후속 결과이며 실제 음향 검증은 아니다.

2026-09-23: 다음 실기기 검증은 [기본 기능 실기기 검증 순서](NATIVE_FIELD_VALIDATION.md)를 따른다. 빌드 7의 자동 검증과 실제 음향 정확도 판정을 분리한다. 기본 검증 후 [라이다 공간 지도·내보내기 계획](LIDAR_SPATIAL_EXPORT_PLAN.md)을 재검토한다.

## 빌드 8 보정 진단 (EXP-019)

사용자의 빌드 7 실기기 결과는 [선택 필드와 해석](../docs/reports/2026-09-23-iphone17pro-build7-rejected-analysis.json)에 기록한다. 6단계·150개 수집은 성공했지만 보정 적합은 거부됐다. 종료 직전 한 프레임을 보정 전체의 음향 조건으로 확대 해석하지 않는다.

빌드 8 회귀는 평탄한 각도 응답, 반복 불일치, 구간 안 산포, 스펙트럼 변화, 시간차 없이 유효한 레벨 응답, 잘못된 입력, 실패 상태 JSON 왕복/새 측정 초기화, 회전 부호와 경과 시간 진행률을 검사한다. 합성 UI는 실패 안내 뒤 위치/주파수 미표시·정지 후 공유 버튼·회전 안내/취소를 검사한다. 코드 `53f884b`에서 [Native iOS](https://github.com/doroper98/sound_detection/actions/runs/35842079170) Swift 67/67·합성 iOS UI 25/25·Release 기기 빌드·IPA 포장 PASS. [웹 CI](https://github.com/doroper98/sound_detection/actions/runs/35842079382) 단위 40/40·E2E 16/16 PASS. 로컬 gate PASS. 로컬 웹 E2E는 15/16 통과하고 기존 시뮬레이터 시나리오 한 건이 120초 제한을 넘었다. 그 한 건만 재실행해도 시간 초과했으며 trace에는 선행 assertion 완료 후 full-page screenshot 호출이 남아 있다. 원인은 확정하지 않았고 로컬 전체 PASS로 기록하지 않는다. 웹 실행 코드는 이번 변경에서 수정하지 않았다. [검증 JSON](../docs/reports/2026-09-23-native-build8-verification.json). 실패 안내 화면은 전체 캡처로 확인했다. 회전 안내 화면 캡처는 주 안내/취소가 보이지만 주변 영역의 렌더가 일부 빠져 완전한 화면 증거로 사용하지 않는다.

## 빌드 7 열지도와 영역 주파수 (EXP-017)

코드 `13864bd`에서 [Native iOS](https://github.com/doroper98/sound_detection/actions/runs/35804076363) Swift 59/59·합성 UI 23/23·Release 기기 빌드·IPA 포장 PASS. [웹 CI](https://github.com/doroper98/sound_detection/actions/runs/35804076241) 단위 40/40·E2E 16/16 PASS. 로컬 gate·웹 E2E 및 실제 시뮬레이터 캡처 검토를 완료했다. 실기기 음향 위치·SPL 정확도는 미검증이다.

순음(44.1/48kHz)의 주파수 한 bin 이내, 진폭 10배의 20dB 변화, 역상 채널 스펙트럼 보존, 광대역 대역 표시, 다중 성분의 대표 peak, Nyquist 경계, 무음/DC/포화/잘못된 입력 거부를 검증했다. UI는 실제 합성 PCM의 1kHz 입력을 FFT bin에 해당하는 약 996Hz로 표시하고, −23/−57dBFS의 입력 레벨, 현재 열섬/방향 열지도, stale/중지/배경 제거와 기존 파형을 검사했다. DEBUG 공간 자세는 합성이며 실제 AR 동작/음향 정확도 검증이 아니다.

빌드 7 IPA 505,134바이트, SHA-256 `18d76f5758c3f4c0a29c5d53f4d1321dea1c82f04090e9eb74968f72bb19a649`. ZIP CRC·arm64 iPhoneOS·빌드 번호·신규 DEBUG 입력 인자 제외를 확인했다. [검증 JSON](../docs/reports/2026-09-23-native-build7-verification.json), [열섬과 주파수](../docs/assets/native-build7-heat-tone.png), [작은 입력](../docs/assets/native-build7-heat-quiet.png), [방향 열지도](../docs/assets/native-build7-bearing-synthetic.png).

열섬은 추정 영역의 강조이고 색은 수신 dBFS다. 원거리 음압장, 여러 음원의 주파수별 위치 분리, 물체 크기 또는 검증된 신뢰구간이 아니다. 시인성을 위한 64~120pt의 크기 제한을 사용한다.

## 빌드 6 카메라 위 방향·공간 후보 (EXP-016)

코드 `5facebb`에서 [Native iOS](https://github.com/doroper98/sound_detection/actions/runs/35795916043) Swift 53/53·합성 UI 21/21·Release 기기 빌드·IPA 포장 PASS. [웹 CI](https://github.com/doroper98/sound_detection/actions/runs/35795915981) 단위 40/40·E2E 16/16 PASS. 로컬 gate·웹 E2E와 최종 화면 검토도 완료했다.

빌드 6 IPA 486,175바이트, SHA-256 `edaa60bc934e83dbd519a95aa29e50348d2f430ca7807616815e27b07ef0205d`. ZIP CRC·실제 iPhoneOS arm64·빌드 번호·새 DEBUG 위치/방향 인자 제외를 확인했다. [검증 기록](../docs/reports/2026-09-23-native-build6-verification.json) · [방향 띠](../docs/assets/native-build6-bearing-synthetic.png) · [위치 후보](../docs/assets/native-build6-position-synthetic.png). 합성 화면이며 실제 아이폰의 카메라/음향 측정이 아니다.

추가 검증: 실제 AR 축과 대응하는 좌표에서 경험적 응답 부호·반복성·다른 샘플률/스펙트럼/범위/상반된 특성 거부, 6단계 회전 보정의 고정 위치/수집 시간, 시각 대응·빠른 이동 거부, stale/무음 제거. 단일 자세 반복·제자리 회전·수평 이동만으로 고도 생성 금지, 다양한 이동/기울기의 합성 평면 교점 복원, 모순된 이동 음원 거부. UI에서는 합성 보정 응답의 방향 띠·조건부 후보 원/거리·중지/백그라운드 제거·실제 전체 화면 중심의 정렬 기준점·AR 없는 상태에서 보정 거부를 검사했다. 기존 스테레오/알림/파형/비교 회귀도 유지했다.

물리 마이크 배열/카메라와 유효 음향 중심의 외부 보정/반사·잡음/실기기 AR+오디오 동시 사용/실제 정확도는 검증하지 않았다. 후보 반경은 모델 민감도이며 검증된 물리 신뢰구간이 아니다. 1m 이상 고정된 단일 광대역 음원의 해당 세션을 대상으로 한다.


## 빌드 5 방향 비교·파형 표시 주기 (EXP-015)

**최종 자동 검증 PASS:** 코드 `37bce7f`에서 [Native iOS](https://github.com/doroper98/sound_detection/actions/runs/35744865905) Swift 42/42·합성 UI 18/18·Release 기기 빌드·IPA 포장 PASS. [웹 CI](https://github.com/doroper98/sound_detection/actions/runs/35744865907) 단위 40/40·E2E 16/16 PASS. 로컬 gate와 E2E 16/16도 통과했다.

[검증·해시](../docs/reports/2026-09-23-native-build5-verification.json) · [파형 화면](../docs/assets/native-build5-waveform-synthetic.png) · [방향 비교](../docs/assets/native-build5-comparison-synthetic.png). 빌드 5 IPA 348,143바이트, SHA-256 `8d5d650b558f85f2dab7b74b17abc4ca8d60a0bb737ff227bd7de501592d048d`. Windows에서 ZIP CRC·iPhoneOS arm64·빌드 번호·DEBUG 인자 제외·해시를 확인하고 최종 파형/비교 화면을 직접 검토했다. 실기기 빌드 5 fps·방향 교정은 사용자 확인 대상이다.

추가 검사는 100ms PCM의 서로 다른 여섯 10ms 창, 10Hz 입력의 60Hz 표시 스케줄, 상한·지연/중지 제거·채널 차이, 6구간 반복 분리/동일값 거부/모호성 보존/기기 움직임·자세 누락/취소/수집 경계·희소 입력/샘플률 변경이다. UI는 6개 구간과 비교·공유, 취소/백그라운드, 초당 20개 이상의 새 파형 표시와 상세 화면 뒤 복귀를 검사했다. CI 부하로 관측량이 부족하면 비교 보류를 허용하되 방향 성공으로 표시하지 못하게 검사한다. 시뮬레이터 속도는 실제 iPhone 성능을 대신하지 않는다.

[빌드 4 실측](../docs/reports/2026-09-22-iphone17pro-native-build4-stereo.json)에서 259/259 양쪽 활성과 초기 경로 유지, 누락/복제 0을 확인했다. [해석](../docs/reports/2026-09-22-iphone17pro-native-build4-analysis.json). 후보 15/259, 마지막 이력 19개 ambiguous, 기기 자세 91.64°는 방향 정확도를 뜻하지 않는다. 파형 끊김은 사용자 보고이며 빌드 4 JSON에는 fps가 없다.

## 빌드 4 L/R 미니 파형 (EXP-014)

**자동 검증 PASS:** 코드 `d9b5c31`, [Native iOS CI](https://github.com/doroper98/sound_detection/actions/runs/35733399591)에서 Swift 31/31·iPhone 16 Pro/iOS 18.5 UI 15/15·Xcode 16.4 Release 기기 빌드·IPA 포장 통과. 최신 최대 10ms 좌우 크기 차이, 여러 샘플률의 피크/마지막 샘플 보존, 무음/짧은 버퍼·비정상 입력 거부, 양쪽 표시/화면 내 배치/한쪽 무음/350ms 지연 후 제거/중지·백그라운드를 검증했다. [웹 CI](https://github.com/doroper98/sound_detection/actions/runs/35733399620) 단위 40/40·Chromium E2E 16/16도 PASS.

[검증 결과·IPA 해시](../docs/reports/2026-09-22-native-waveform-verification.json) · [양쪽 파형](../docs/assets/native-waveform-stereo-synthetic.png) · [오른쪽 무음](../docs/assets/native-waveform-silent-right-synthetic.png). 두 합성 화면을 직접 검토하고 Windows에서 IPA의 해시·CRC·실제 iOS 실행 파일·빌드 번호·DEBUG 인자 제외를 확인했다. 기존 빌드 3의 실제 수음 성공과 새 빌드 4 파형의 기기 검증은 구분한다.

## 빌드 3 첫 실제 스테레오 수음 (EXP-013)

**사용자 실기기 결과 확보:** [제공 JSON](../docs/reports/2026-09-22-iphone17pro-native-build3-stereo.json) · [파생 해석](../docs/reports/2026-09-22-iphone17pro-native-build3-analysis.json). 사용자는 기침과 컴퓨터 영상 소리를 수음했다고 설명했다. iOS 27.0, 후면 Stereo·48kHz, 세션/하드웨어/tap 2채널, 카메라 세션 실행 상태에서 통합 시작. 약 25초간 245개 구간 모두 좌우 active, 복제 의심 0·분석 건너뛰기 0·분석 타임라인 불연속 0이다. 코드 3 한 번·코드 4 세 번 모두 입력 검사 후 수음을 유지했고 엔진 재시작은 없었다. 빌드 2 시작 중지 오류는 이번 기록에서 재현되지 않았다.

시간차 후보는 14/245(5.7%)이며, 마지막 약 2초 20개 중 19개는 ambiguous, 1개는 −83.33µs 후보이다. 마지막 구간 좌우 약 −61.9/−60.9dBFS, peakCorrelation 0.872지만 최고점과 경쟁 후보 차이가 0.001465로 코드 기준 0.08 미만이다. 마지막 0.5초 후보 0/5와 종료 상태 stopped를 확인한다. 후보 개수를 정답률로 해석하지 않으며, 전체 기록을 보존한 것이 아니므로 이전 231개 비후보의 상세 상태나 소리별 대응을 추정하지 않는다.

카메라는 오디오 시작 때 실행 중이었다는 증거이며 전체 영상 프레임 연속성을 검증한 기록은 아니다. 자세/오디오 시각 대응도 소프트웨어 관찰이다. 독립 물리 마이크·하드웨어 동기화·음향 교정·방향/거리/위치는 미검증이다. 다음 비교는 폰을 고정하고 한 소리를 왼쪽/정면/오른쪽에서 분리하여 위치 표시와 JSON을 수집한다. 원본에 맞추기 위한 임계값/런타임 변경은 하지 않았다.

## 빌드 2 실기기 알림·빌드 3 회귀 (EXP-012)

[사용자 원본](../docs/reports/2026-09-22-iphone17pro-native-build2-override.json)은 reasonCode 4에서 분석 전 중지를 기록한다. 선택된 후면 Stereo·3종 채널 수 2·48kHz·엔진 실행까지 확인했으며 실제 PCM 분석은 0이다. 코드 4는 override인데 빌드 2가 unknown으로 처리했다. routeMatches=false는 해당 이벤트에서 실제 검사하지 않은 결과이므로 입력 경로 불일치의 증거로 해석하지 않는다. 사용자는 카메라가 시작되자마자 중지했다고 설명했으며 cameraSessionRunningAtAudioStart=false와의 차이는 미확정으로 보존한다.

**빌드 3 자동 검증 PASS:** 코드 `ac5562d`, [Native iOS CI](https://github.com/doroper98/sound_detection/actions/runs/35730115675)에서 Swift 27/27·시뮬레이터 UI 13/13·Xcode 16.4 Release 기기 빌드·IPA 포장 통과. 첫 PCM 전 override에서 동일한 스테레오 입력을 유지하고 실제 불일치는 거부하는 두 회귀를 포함한다. [웹 CI](https://github.com/doroper98/sound_detection/actions/runs/35730115684)의 단위 40/40·Chromium E2E 16/16도 PASS. [영구 결과·해시](../docs/reports/2026-09-22-native-override-verification.json) · [검토한 합성 UI 화면](../docs/assets/native-camera-build3-synthetic.png). Windows에서 전달 IPA의 해시·CRC·실제 iOS 실행 파일·빌드 번호·권한·DEBUG 인자 제외를 재검사했다. 실제 카메라/수음 동시 사용과 빌드 3 기기 오류 해결 여부는 후속 확인 대상이다.

## 카메라 화면·실기기 시작 알림 수정 (EXP-011)

- 사용자 확인: Sideloadly 설치 완료와 실제 앱 실행. 외부 오디오 장치 없이 수음 시작 직후 일반적인 경로/인터럽트 중지 문구 표시. 알림 원본 JSON이 없어 실제 발생 종류는 미확정.
- 회귀 기준: 정상 설정/엔진 알림은 실제 동일한 내장 스테레오 경로일 때 수음 유지, 초기 엔진 재시도는 첫 PCM 전 2초·최대 2회. 장치 교체/입력 조건 변경/인터럽트 시작/미디어 서비스 실패는 중지. 종료된 인터럽트만으로 재개하지 않음.
- 카메라: 전체 화면 미리보기와 같은 화면의 조작 버튼, 명시적 시작, 카메라 거절 시 수음 미시작, 취소 뒤 늦은 권한 결과 차단, 중지/백그라운드 해제. 합성 UI 검사는 카메라 프레임을 생성하지 않는다. 물리 카메라 영상·오디오 동시 수신은 사용자 기기에서 확인한다.
- **자동 검증 PASS:** 코드 `95cda61`, [Native iOS CI](https://github.com/doroper98/sound_detection/actions/runs/35725200763)에서 Swift 25/25·iPhone 16 Pro/iOS 18.5 시뮬레이터 UI 11/11·Xcode 16.4 Release 기기 빌드·IPA 포장 통과. 카메라 성공 직후 수음 시작 실패 시 영상도 해제하는 회귀를 포함한다. [웹 CI](https://github.com/doroper98/sound_detection/actions/runs/35725200712)의 Gate/단위 40/40·Chromium E2E 16/16도 PASS.
- [결과·파일 해시](../docs/reports/2026-09-22-native-camera-routefix-verification.json) · [합성 카메라 UI 화면](../docs/assets/native-camera-overlay-synthetic.png). Windows에서 내려받은 빌드 2 IPA(253,153바이트)의 해시·ZIP CRC·실제 iOS arm64 실행 파일·카메라 권한·빌드 번호·DEBUG 인자 제외를 확인했다. 화면은 직접 검토했으며 실제 카메라 영상을 포함하지 않는다. 새 빌드의 실제 iPhone 설치/수음·카메라 동시 사용과 시작 오류 해결 여부는 아직 미검증이다.

## 연속 네이티브 관측 추가 (EXP-010)

**자동 검증 PASS (2026-09-22):** 코드 `9397574`, [Native iOS CI](https://github.com/doroper98/sound_detection/actions/runs/35721177466). Xcode 16.4/iphoneos Release 빌드, Swift 20/20, iPhone 16 Pro/iOS 18.5 시뮬레이터 UI 5/5, unsigned IPA 생성. [결과·파일 해시](../docs/reports/2026-09-22-native-continuous-verification.json) · [합성 연속 관측 화면](../docs/assets/native-continuous-synthetic.png). [웹 CI](https://github.com/doroper98/sound_detection/actions/runs/35721177518)도 Gate/단위 40/40·Chromium E2E 16/16 PASS.

- Swift: 단발 이상치의 중앙값 안정성, 0.5초 내 계단 변화 반영, 최신 무음 즉시 보류, stale/stop/restart, 큰 산포 표시, 유효 비율, 버퍼 상한/역행 시각, 자세의 근접 시각·90° 회전·오래된 값 거부·quaternion 부호/배율 동치·잘못된 quaternion 검증을 추가한다.
- UI: 연속 중앙값과 기기 회전 표시·변화 그래프, 중지 후 누적값 보류를 기존 시작/공유/백그라운드 흐름에 추가한다. 합성 PCM과 합성 quaternion은 표시·보고서에 명시한다.
- 포장: 검증한 Release/iphoneos 실행 파일을 Payload 구조의 unsigned IPA로 만든다. Info.plist 플랫폼·CRC·SHA-256을 확인하며 개인 프로비저닝 프로필이 있으면 포장을 거부한다.
- 내려받은 IPA를 Windows에서 다시 검사해 SHA-256·CRC 일치, Mach-O arm64 실행 파일과 iOS 플랫폼(시뮬레이터 아님), 실제 Info.plist와 메타데이터 일치, DEBUG 합성 입력 실행 인자 제외를 확인했다. 파일 크기는 191,303바이트다. CI의 `sourceCommit`은 PR merge ref이고 결과 JSON에 별도로 PR head를 남겼다.
- 첫 실행 `35720277567`은 UI 4/5: 공유창 뒤의 버튼을 앱 스크롤로 드러내려는 자동 조작이 실패했다. 공유창이 열린 시점의 수음 중지·누적값 보류를 직접 검증하도록 수정 후 전체 UI 5/5 PASS. 공유창 닫기 제스처 성공으로 기록하지 않는다.
- 실제 Core Motion과 오디오 시각 대응, Windows 개인 서명 설치, 실제 iPhone 17 Pro 수음·추정 정확도는 자동 합성 테스트에 포함되지 않는다.

## iPhone 네이티브 스테레오 진단 (EXP-009)

**자동 검증 PASS (2026-09-22):** 코드 `b447dc1`, [Native iOS CI](https://github.com/doroper98/sound_detection/actions/runs/35718003457). Xcode 16.4/iphoneos Release 빌드, 순수 Swift 10/10, iPhone 16 Pro/iOS 18.5 시뮬레이터 UI 5/5. [영구 결과 요약](../docs/reports/2026-09-22-native-stereo-verification.json) · [합성 입력 화면](../docs/assets/native-stereo-synthetic.png). 실제 아이폰 17 Pro 결과는 아직 없다.

실행: Mac에서 `bash native/ios/scripts/verify.sh`. GitHub의 Native iOS workflow도 같은 스크립트를 실행한다. Windows의 Swift/Xcode 미설치를 통과로 처리하지 않는다.

| 검증 계층 | 검사 | 실기기 성공 여부 |
|---|---|---|
| StereoCore Swift 테스트 10개 | 양·음 지연과 44.1/48/96kHz, 0지연+독립 잡음, 무음/DC, 복제/배율/극성, 순음 다중 피크, 포화·독립 잡음, 검색 경계, 20dB 변화, 비정상 PCM, JSON | 합성 신호 검증 |
| iphoneos Release 빌드 | AVAudioSession/AVAudioEngine/SwiftUI·로컬 패키지, 마이크 권한 plist, 서명 없이 컴파일/링크 | 설치·수음 검증 아님 |
| iPhone 시뮬레이터 UI 5개 | 시작/위치 표시/중지, 지연된 권한 결과 취소, 모노 거부, 백그라운드 해제, 공유 시 중지 | DEBUG 합성 입력, 화면·JSON에 명시 |
| iPhone 17 Pro 실제 입력 | 실제 PCM2, 양쪽 활성, 복제 여부, 전면/후면·좌/정면/우, 인터럽트·잠금·재시작 | 아직 미검증 |

기기 빌드는 iOS SDK에서 타입과 링크를 검증하고, 시뮬레이터는 앱 동작을 검증한다. 내장 마이크 stereo polar pattern 적용과 실제 PCM은 물리 아이폰에서 별도로 검사해야 한다. 초기 CI의 아키텍처 불일치와 후속 결과는 DEVLOG.md의 EXP-009/BUG-015에 기록한다.

보고서의 지연은 right-minus-left, 기존 TS SDK는 microphone0-minus1이다. 두 경로를 바로 연결하지 않는다. 내장 스테레오 처리의 편향·좌우 축과 유효 센서 모델을 검증하기 전에는 물리 TDOA/각도/거리로 표시하지 않는다. JSON의 세 가지 검증·활성 플래그는 false로 유지한다. 실제 검사 순서: [네이티브 앱 안내](../native/ios/README.md).

## v0.4.0 연속 주파수 분석

로컬 Gate PASS, Chromium E2E 16/16 PASS. 화면 조정 후 연속 분석 1/1 추가 PASS. 390×844/1366×768에서 페이지 양축 넘침 없음, 카메라·그래프·전체/대역/peak 수치가 함께 보이는지 확인했다. 합성 입력 스크린샷은 `docs/assets/live-spectrum-mobile.png`, `live-spectrum-desktop.png`다.

- 40개 단위 테스트: 기존 30개 + 스펙트럼 7개 + 연속 캡처 수명 3개. 44.1/48 kHz의 1 kHz tone peak 오차 한 bin 이내, 0.1 진폭 RMS 약 −23.01 dBFS, 10배 진폭 20 dB, 저역/고역 분리, 무음·DC·포화·Nyquist를 검증한다.
- 모의 타이머와 미디어 객체로 무응답 timeout, 트랙 ended, 사용자 Stop 뒤 트랙/포트/타이머 정리를 검증한다.
- 브라우저 시나리오: 카메라 병행 300 Hz 합성 입력/무음 CH 2, 대역/채널 선택, 통계 JSON, 정지·재시작·pagehide, 권한 거절/미지원, 늦은 권한 허용 취소. 실제 AudioWorklet/FFT를 실행하며 물리 마이크 성능 검증으로 간주하지 않는다.
- iPhone의 연속 분석, 실제 OS 잠금·회전·수음 처리·성능은 사용자의 후속 실기기 검증 대상이다.

## Safari 실기기 보고서 추가 (2026-09-22)

[원본 JSON](../docs/reports/2026-09-22-iphone17pro-safari-diagnostics.json)은 사용자가 제공한 값이며 새 자동 테스트 결과가 아니다. v0.3.0, startedAt `09:05:59.558Z`, exportedAt `09:06:32.419Z`, 사용자 입력 기종 iPhone 17 Pro, OS 입력 공란. UA의 `iPhone OS 18_7`와 `Version/27.0`을 그대로 기록하고 실제 iOS 버전을 단정하지 않는다.

후면 카메라 1280×720/30 fps를 켠 상태에서 4채널 exact·2채널 exact·기본 모두 captured. 각 20프레임/81,920 samples/48 kHz, 관측 2채널, 활성 채널은 CH 1뿐이다. CH 1 최종 레벨은 각각 −58.15/−53.71/−51.66 dBFS, CH 2 peak는 모두 0이다. 상관은 null, 물리 독립성·동기화·localization은 false다. channelCount 제약·설정·capability는 미보고다.

Chrome과 정성적으로 같으며 두 경로에서 위치 추정에 필요한 독립 다채널은 확보되지 않았다. 카메라 끈 상태와 네이티브 API의 가능성을 이 결과로 판정하지 않는다. 아래의 최초 Chrome 기록은 당시 확인 범위로 보존한다.

## 자동 Gate

```sh
npm ci
npm run gate
npx playwright install chromium
npm run test:e2e
```

Gate는 TypeScript strict, Vite 프로덕션 빌드, 물리 테스트, 버전·lock·DEVLOG·CHANGELOG·릴리즈 노트의 일치를 검사한다. Vitest는 `tests/**/*.test.ts`만 수집하며 Playwright 테스트를 섞어 실행하지 않는다.

## 물리 테스트 (9개)

λ=c/f, 거리 두 배 음압 감소, 회전 후 마이크 간격 유지, 시간차 부호/상한/대칭, 무관측 추정 없음, 단일 관측의 넓은 후보, 독립 4관측의 공간 제약, 중복 관측 거부, 순음의 주기 모호성을 검증한다. 추정기는 정답 좌표를 입력으로 받지 않는다.

## 브라우저 테스트 (4개 시나리오)

v0.2.0에서 PCM 엔진 테스트 12개를 추가해 총 21개다. ±지연, 무음/비동기 입력 거부, 고정 PCM에 대한 정답 좌표 독립성, demo 외부 좌표계, 수평/수직 센서 배열, production code의 UI import 부재를 검증한다. `npm run build:engine`은 DOM lib 없이 별도로 빌드한다.

1. 데스크톱: 화면, 클릭 배치, 주파수↔파장, 폰 드래그, 단일 마이크 제약, 저장 관측 초기화, 기종 간격, 다른 높이/위치의 3관측 누적과 결과 표시, JSON 내용 검증, 릴리즈 노트, 전체 초기화, console pageerror 없음.
2. 390×844 모바일: 페이지 가로/세로 넘침 없음, heatmap ON/OFF, native dialog, 하단 패널에서 설정하면서 스캔 화면 유지, 설정 세부 탭, 공간/스캔 전환 후 유효한 열지도와 console pageerror 없음.
3. 데스크톱 볼륨: 마이크 추정/정답 비교 각각 50→90 dB에서 열지도 alpha·표시 픽셀·따뜻한 색 픽셀 증가, PCM 40 dB 증가, 50 dB 복귀 시 동일 면적.
4. 모바일 볼륨: 동일 회귀 검증, 설정 중 수신 레벨과 미리보기 유지 및 양축 페이지 넘침 없음.

v0.2.1은 heatmap.test.ts 4개를 더해 총 25개 단위 테스트다. 두 신호의 40~100 dB 단계별 레벨 증가와 지연 불변, 근접 고음량 PCM 포화/범위 제한, 단일 채널 레벨, 무음과 고정 표시 임계값을 검증한다. 볼륨 비교 화면은 test-results/volume-50.png와 volume-90.png다.

`test-results/desktop.png`, `mobile.png`를 화면 검토 증거로 생성한다. Git에는 넣지 않으며 CI에서 artifact로 보관한다. 테스트 환경의 SwiftShader는 기능 확인용이며 실제 GPU 성능을 대표하지 않는다.

공유용 화면은 별도로 docs/assets에 복사한다. 모바일 설정 중 미리보기는 mobile-settings.png로 검토한다. v0.2.0 패키지를 npm pack 후 별도 consumer에 설치/import했고, CLI replay에서 source.position만 변경해도 출력 전체가 동일하며 6 sample 지연을 복원하는 것을 확인했다.

## 배포 후

```powershell
$env:PLAYWRIGHT_BASE_URL='https://배포주소'
npm run test:e2e
Remove-Item Env:PLAYWRIGHT_BASE_URL
```

공개 URL의 200, version.json의 버전, JS/CSS asset 정상 응답, CSP/보안 헤더, 원격 브라우저 기능을 확인한다. 배포 전 dry-run만 성공하면 공개 사이트 검증으로 기록하지 않는다.

## 수동·하드웨어 후속

- 실제 iPhone/iPad Safari 및 Android의 touch 회전·높이 입력·내보내기.
- 낮은 GPU 성능, WebGL 비활성 환경의 안내.
- 같은 평면 관측에 남는 고도 모호성, 단일 주파수에서 간격 확대 시 후보 증가.
- 실제 수음 접근성은 /diagnostics에서 기기별로 확인한다. 장치의 위치 정확도는 미검증이며 소프트웨어 테스트를 실측 정확도 증거로 사용하지 않는다.

## v0.3.0 추가 검증

- 단위 테스트 30개: 무음/복제/상이한 채널, 요청과 PCM 불일치 판정, 실제 Worklet 코드의 가변 블록·채널 변경 처리, 취소 후 늦게 응답한 입력 해제.
- Chromium E2E 총 13개: 기존 4개 + 설정 축소/미리보기/패널 넘침 1개 + 실제 입력 UI 8개. 캡처는 합성 fixture다. 카메라 프레임, 스트림 해제, 채널 요청/전달, 권한 오류/미지원, JSON의 민감 데이터 제외를 검증한다.
- Chromium의 MediaStreamAudioSource 변환이 1/4채널 fixture를 2채널로 만들므로 그 경로는 실제 2채널을 기대한다. 4채널·복제·설정 무시 UI 테스트는 해당 경계에서 native Web Audio 소스를 주입하고 실제 Worklet/분석을 실행한다. 센서 입력이나 Safari 결과로 간주하지 않는다.
- Windows Playwright WebKit 26.6은 캡처 API가 없어 5개 수음 시나리오를 수행하지 못했다. 미지원 오류/보고서 다운로드/모바일 넘침 시나리오 1개는 PASS. 실제 iPhone의 Safari와 다른 환경이다.

WebKit의 미지원 처리 재현: `npx playwright install webkit` 후 PowerShell에서 `$env:PLAYWRIGHT_BROWSER='webkit'`를 설정하고 `npx playwright test tests/e2e/diagnostics.spec.ts --grep 'unsupported capture' --output test-results-webkit`를 실행한다. 기본 CI 브라우저는 Chromium이다.

실기기에서는 [검사 순서](LIVE_CAMERA_PLAN.md)대로 iOS 버전과 진단 보고서를 확보한다. 카메라 동시 사용 유무, 권한 최초/거절, 화면 회전, 탭 숨김 후 캡처 해제도 확인한다.

## 공개 사이트 native 캡처 경로 추가 점검 (2026-09-22)

이전 대화에서 수행한 추가 검증 결과를 보존한다. 이번 문서화에서 iPhone 검증을 새로 수행한 것은 아니다.

- 근거: 로컬 `.local/camera-native-audit.json`, `checkedAt=2026-09-22T06:01:21.796Z`. 브라우저 Chromium 153.0.8010.12, 대상 공개 `/diagnostics`.
- `--use-fake-device-for-media-stream` 및 `--use-fake-ui-for-media-stream`으로 브라우저 가상 장치/권한 승인을 사용했다. JavaScript getUserMedia API는 대체하지 않았다.
- HTTPS/동일 origin 권한 정책, 1280×720 video의 프레임·미디어 시간 증가, 3회 재시작, 세로/가로 viewport, 마이크 검사 중/후 영상, pagehide 이벤트 후 재시작·새로고침을 확인했다.
- 해당 Windows headless 환경에서 가상 UI 승인 플래그 없이 native 캡처가 NotSupportedError를 반환했다. 가상 UI 승인은 권한 거절을 덮어쓰므로 실제 사용자의 거절 경로 검증으로 계산하지 않는다.
- 실제 iPhone 카메라·Safari 채널 수·OS 잠금/회전 센서 동작의 증거가 아니다. 임시 스크립트/원본 로그의 `.local/`은 Git 제외 경로다. 영구 기록은 이 요약이며, 기존 합성 E2E와 실기기 확인을 구분한다.

## iPhone 17 Pro 실기기 진단 첫 보고서 (2026-09-22, Chrome for iOS)

사용자가 실제 iPhone 17 Pro에서 공개 `/diagnostics`를 실행해 전달한 첫 보고서다. 원본 JSON은 [docs/reports/2026-09-22-iphone17pro-crios-diagnostics.json](../docs/reports/2026-09-22-iphone17pro-crios-diagnostics.json)에 그대로 보존한다. 원음·영상·deviceId는 포함되지 않는다.

### 조건

- 앱 0.3.0, `startedAt=2026-09-22T08:59:28.051Z`, 검사 완료(`completed=true`), 총 소요 약 6.3초.
- userAgent: `iPhone OS 27_0_0`, `CriOS/153.0.8010.24`. **Chrome for iOS이며 Safari 앱이 아니다.** iOS의 타사 브라우저는 WebKit 엔진을 사용하므로 엔진 수준의 참고 자료다. Safari 앱 자체의 결과로 기록하지 않는다.
- 기종은 사용자 입력 "iPhone 17 Pro". iOS 버전 입력란은 비어 있어 userAgent의 27.0.0을 참고값으로 쓴다.
- secureContext, getUserMedia, AudioContext, AudioWorkletNode 모두 사용 가능.
- 카메라를 켠 상태에서 검사(`cameraActiveAtProbeStart=true`). 후면(`environment`) 1280×720, 30 fps가 실제 선택됐다. 카메라를 끈 상태의 검사는 아직 없다.

### 요청별 결과

| 요청 | status | PCM 채널 수 | 신호 있는 채널 | 채널 1 레벨(최종 프레임) | 채널 2 |
|---|---|---|---|---|---|
| 4채널 exact | captured | 2 | 1 | −58.8 dBFS, peak 0.0042 | 무음(peak 0) |
| 2채널 exact | captured | 2 | 1 | −59.9 dBFS, peak 0.0032 | 무음(peak 0) |
| 기본 입력 | captured | 2 | 1 | −54.4 dBFS, peak 0.0065 | 무음(peak 0) |

- 각 요청 20 프레임 × 4096 샘플 = 81,920 샘플, 48 kHz. `settings.echoCancellation=false`가 적용값으로 보고됐다.
- `getSupportedConstraints()`에 `channelCount`, `noiseSuppression`, `autoGainControl`이 없다. 사양상 인식하지 못하는 제약은 무시되므로 4채널·2채널 exact 요청이 OverconstrainedError 없이 성공한 것은 **수락이 아니라 무시**로 해석한다. `settings.channelCount`와 `capabilities.channelCount`도 보고되지 않았다.
- 채널 2가 세 요청 모두 정확히 0이므로 상관·복제 판정은 계산되지 않았다(`correlation=null`). 두 물리 마이크의 증거가 아니며, 브라우저 내부 변환의 결과인지 캡처 형식 자체인지 이 보고서만으로는 판정할 수 없다.
- 앱 판정: "4채널 안정 수신 미확인". `physicalMicrophonesVerified`, `hardwareSynchronizationVerified`, `localizationEnabled`는 모두 false.

### 해석과 한계

- 이 브라우저·경로에서는 실효 1채널(모노) PCM만 얻는다. 방향 추정에 필요한 다채널 입력은 확보되지 않았다.
- 레벨은 디지털 dBFS이며 조용한 환경의 값이다. 낮은 레벨은 마이크 고장의 증거가 아니다. 손뼉 등 큰 소리를 냈는지는 보고서에 남지 않는다.
- Safari 앱, 카메라 끈 상태, 권한 거절, 화면 회전, 잠금 후 복귀는 이 보고서에 포함되지 않았다. 한 기기·한 브라우저·한 회의 결과다.

## 빌드 9 첫 단계 정지 회귀

`SpatialSynchronizationTests`는 늦은 실제 시각의 합성 카메라 프레임이 첫 보정 단계를 통과하는지, 영구 누락/오래된 시각/빠른 이동 거부, 대기 큐 한계·세션 폐기, 잘못된 큰 안내를 검사한다. iOS UI는 `--synthetic-pose-delay` 및 `--synthetic-pose-stalled`로 실제 SpatialModel 큐·calibrator 경로를 구동한다. 열지도용 완성 프로필 fixture를 쓰지 않는다. DEBUG 밖에서는 해당 입력 경로가 없다. Mac CI 결과 대기이며 실제 기기 해결을 뜻하지 않는다.

빌드 9 전달 검증: 코드 `7a0b468`의 [Native iOS](https://github.com/doroper98/sound_detection/actions/runs/35856433903)에서 Swift 73/73, 합성 UI 27/27, Release 기기 빌드·IPA 포장 PASS. [웹 CI](https://github.com/doroper98/sound_detection/actions/runs/35856433756)의 단위 40/40·E2E 16/16 PASS. 로컬 gate 및 직전 앱 코드의 로컬 웹 E2E 16/16 PASS(웹 코드는 동일). 캡처 2개를 직접 확인하고 IPA CRC/arm64 iPhoneOS/빌드 9/SHA-256/Release의 합성 플래그 제외를 확인했다. 별도 focused 실행 35856434110은 보정 회귀 2개를 포함해 5/6 통과했고 기존 파형 UI 5초 대기에서 시간 초과했다. 전체 실행은 같은 앱 코드에서 통과했다. 이후 UI 검사만 양쪽 순차 30초 대기로 보완했으며 앱의 350ms 만료/수음/위치 코드는 변경하지 않았다. 보완한 검사 대기 설정의 CI는 별도다. 실기기 정지 해결과 음향 위치 정확도는 미검증. [검증 보고서](../docs/reports/2026-09-23-native-build9-verification.json).
