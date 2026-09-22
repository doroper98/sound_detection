# iPhone 네이티브 스테레오 진단

웹에서 받은 PCM은 iPhone 17 Pro의 Chrome/Safari 모두 두 칸 중 한 칸만 활성 신호였다. 이 앱은 AVAudioSession의 **내장 stereo polar pattern**을 선택하고 AVAudioEngine에서 실제 PCM을 직접 받는다. WKWebView로 웹사이트를 감싸는 방식이 아니다.

현재는 입력·채널 간 신호 지연을 검증하는 개발용 앱이다. 웹 제품 버전은 0.4.0을 유지한다. App Store/TestFlight 배포나 아이폰 실측 성공을 의미하지 않는다.

## Mac에서 실제 아이폰에 설치

1. 사용하는 아이폰의 iOS를 지원하는 Xcode를 설치한다. 앱 최소 지원은 iOS 17이지만 **iOS 27 아이폰은 해당 기기를 지원하는 Xcode가 필요**하다.
2. 이 폴더의 `SoundFieldStereo.xcodeproj`를 Xcode에서 연다. 로컬 Swift 패키지만 사용하므로 외부 라이브러리 다운로드나 npm 설치는 필요 없다.
3. SoundFieldStereo target → Signing & Capabilities → Team에서 자신의 Apple 계정을 선택한다. Bundle Identifier는 자신이 사용할 수 있는 고유 값으로 바꾼다. 저장소에는 인증서·개인 Team ID를 넣지 않는다.
4. 아이폰을 연결하고 신뢰·개발자 모드를 설정한 뒤, 실행 기기로 아이폰을 선택하여 Run(⌘R)한다. 개인 계정 설치의 유효기간 등 서명 정책은 Xcode 안내를 따른다.
5. 앱에서 **후면 → 스테레오 수음 시작**을 누르고 마이크를 허용한다. 아이폰을 세로로 고정한다. 실제 PCM 2채널이 아니거나 stereo 선택이 적용되지 않으면 분석을 시작하지 않는다.

Mac 없이 Windows 웹페이지만으로 이 네이티브 앱을 아이폰에 설치할 수는 없다. 자동 CI는 서명 없는 기기 빌드와 시뮬레이터 검증을 수행하며, 설치 가능한 서명 IPA/TestFlight에는 Apple 서명·배포 설정이 별도로 필요하다.

## 첫 실기기 검사

- 블루투스/USB 오디오 장치를 분리하고 조용한 실내에서 시작한다. 이 앱은 내장 마이크만 선택하며 카메라는 아직 사용하지 않는다.
- 휴대폰을 고정하고 약 0.5~1m의 왼쪽·정면·오른쪽에서 종이 비비기 등 광대역 소리를 낸다. 각 위치에서 `소리 위치 기록`을 누른다. 표시는 사용자가 선언한 위치이며 자동 교정이나 정답 좌표 입력이 아니다.
- 좌우 레벨·활성 여부·복제 의심·지연 부호가 어떻게 바뀌는지 확인한다. 양수 지연은 오른쪽 신호가 늦음, 음수는 왼쪽이 늦음이다. 전면에서도 반복한다.
- `진단 JSON 공유`로 보고서를 저장/공유한다. 공유 직전에 수음을 중지한다. 보고서는 통계·요청값·실제 포맷·선택 소스·OS 버전만 포함하며 **원음·영상·장치 ID는 포함하지 않는다**.
- 중지/재시작, 권한 거부 후 설정 변경, 잠금·앱 전환, 전화 인터럽트, 헤드셋 연결 시 중지와 마이크 해제를 확인한다. 자동 재개하지 않는다.

2채널 수신 + 양쪽 활성 + 비복제는 다음 교정 단계에 필요한 관찰이다. 물리 센서 독립성·무처리 PCM·하드웨어 동기화의 증명은 아니다. 고정 거리의 여러 방위·주파수·전후면에서 지연 편향과 재현성을 확인한 뒤 위치 엔진 연결 여부를 결정한다.

## 계산과 범위

- 같은 AVAudioPCMBuffer의 실제 2채널 Float32를 사용한다. 강제 2채널 변환·모노 복제·스피커 재생은 없다. 권장 48kHz와 실제 샘플률을 구분한다.
- 평균 제거 후 정규화 상호상관의 절댓값을 ±1ms에서 검색한다. 정수 샘플 분해능은 48kHz에서 약 20.83µs. GCC-PHAT 위치 SDK와 별도의 입력 진단이며 서브샘플 정확도를 주장하지 않는다.
- 한쪽 AC 무음, 포화, 동일/이득 배율/극성 반전 복제, 낮은 상관, 반복 피크, 검색 경계는 지연 값을 숨긴다. 상관 0.35·피크 차 0.08·복제 잔차 1e-5는 초기 휴리스틱이며 실측 신뢰구간이 아니다.
- ±1ms는 진단 검색 범위다. 아이폰 물리 마이크 간격에서 유도한 범위가 아니다. 이 범위 밖 신호와 반사 환경에서 정확한 지연 검출은 보장하지 않는다.
- 처리 중 새 버퍼는 건너뛰고 개수를 남긴다. PCM 대기열은 한 개로 제한한다. `analyzedTimelineGaps`는 분석한 버퍼 사이의 sampleTime 불연속이며 처리 건너뛰기와 실제 입력 중단을 구분하지 않는다.
- `physicalMicrophonesVerified`, `hardwareSynchronizationVerified`, `localizationEnabled`는 항상 false다. 지연을 각도·거리로 환산하거나 임의 마이크 배치로 기존 위치 엔진에 넣지 않는다.

Apple 스테레오는 데이터 소스/빔포밍을 사용해 생성될 수 있다. `.measurement` 모드는 primary microphone을 사용하므로, raw 스테레오를 준다고 가정해 선택하지 않는다. 앱은 `.record` + `.default` + `.stereo` + 세로 입력 방향을 사용한다.

## 검증

Mac에서 `bash scripts/verify.sh`를 실행한다. Swift 패키지 단위 검증, 서명 없는 Release 기기 빌드, DEBUG 합성 입력의 UI 검증을 수행한다. 실제 시작 버튼은 권한 확인 전에는 수음하지 않는다. 합성 모드는 `#if DEBUG` 내부에만 있고 화면과 JSON에 명확히 표시된다.

검증 결과와 실패 수정 기록은 저장소 루트 `DEVLOG.md`, `docs_canonical/TESTING.md`에서 관리한다. GitHub Actions의 **Native iOS**가 동일 절차를 실행하고 로그·xcresult·화면을 보관한다.

## 1차 출처

- [Apple 내장 스테레오 샘플](https://developer.apple.com/documentation/avfaudio/capturing-stereo-audio-from-built-in-microphones)
- [WWDC20: Record stereo audio with AVAudioSession](https://developer.apple.com/videos/play/wwdc2020/10226/)
- [measurement 모드](https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/measurement)
- [마이크 권한](https://developer.apple.com/documentation/avfaudio/avaudioapplication/requestrecordpermission(completionhandler:))
