# 실제 카메라·수음 진단과 방향 추정 계획

상태: v0.3.0에서 **실제 카메라 + 실제 PCM 음량 + 채널 진단** 구현. iPhone 17 Pro의 실제 Safari 결과는 아직 확보하지 않았다. 실제 방향 열지도와 cm 정확도는 미검증이다.

## iPhone 17 Pro에서 검사하기

1. AirPods·외장 오디오 연결을 해제하고 Safari에서 [진단 페이지](https://soundfield-lab.pages.dev/diagnostics)를 연다.
2. ‘카메라 시작’을 누르고 권한을 허용한다. 후면 카메라를 우선 요청하며 실제 선택된 facingMode/해상도를 결과에 기록한다. 카메라 없이 마이크만 검사할 수도 있다.
3. 기종과 iOS 버전을 입력한다. 기종 입력은 사용자 기록이며 자동 검증이 아니다.
4. ‘4채널 검사 시작’을 누르고 마이크 권한을 허용한다. 검사 중 주변에서 말하거나 손뼉을 친다.
5. 4채널 필수 → 2채널 필수 → 기본 입력을 순서대로 확인한다. 각 성공 요청은 약 1.7초의 PCM을 수집하며, 무응답은 8초에 종료한다. 권한을 기다리는 시간은 별도다.
6. 결과 복사 또는 JSON 저장으로 원본 보고서를 공유한다. 카메라를 켠 경우와 끈 경우 각각 검사하면 입력 경로 차이도 확인할 수 있다.

음성·영상은 서버로 전송하지 않는다. 검사 완료/중지 시 마이크를 해제하고 카메라는 별도 중지한다. 백그라운드/페이지 종료 시 모두 해제한다. 권한 창이 늦게 응답해도 취소된 캡처는 즉시 정리한다. 전후면 전환 버튼은 아직 없으며 후면 선호 요청만 구현했다.

## 결과의 의미

| 결과 | 확인한 것 | 아직 확인하지 않은 것 |
|---|---|---|
| 4채널 exact 요청 성공 | 브라우저가 요청을 수락 | 실제 채널 수, 센서 수 |
| getSettings.channelCount = 4 | 트랙이 보고하는 설정 | 앱까지 4채널이 전달되는지 |
| AudioWorklet에 4채널 PCM 도착 | 현재 Web Audio 경로가 전달한 형식 | 물리 마이크 4개의 독립 원음/시간 동기화 |
| 같은 파형 | 복제된 채널 의심 | 같은 소리를 들은 센서인지, 복제인지 최종 판정 |
| 다른 파형 | 채널 간 차이 존재 | 독립 센서라는 증거, 위치 정확도 |
| 1~2채널 PCM | 해당 경로에서 받은 채널 수 | 다른 앱/API까지 포함한 하드웨어 제한 |

검사 경로는 `getUserMedia → MediaStreamAudioSourceNode → AudioWorklet`이다. Worklet은 실제 입력 배열 길이를 읽고 요청 수로 upmix하지 않는다. 다만 브라우저 내부에서 이미 채널 혼합/복제가 발생할 수 있다. Chromium 자동 테스트에서는 1채널 합성 MediaStream이 2채널 PCM으로, 4채널 스트림이 2채널 PCM으로 도착했다. 이를 Safari 결과로 일반화하지 않는다. `getSupportedConstraints()`는 제약 이름을 인식하는지의 정보이며 4채널 하드웨어 지원 여부가 아니다.

`echoCancellation`, `noiseSuppression`, `autoGainControl` 비활성화는 요청값이다. 실제 적용 설정과 capabilities를 별도로 기록한다. 출력 dBFS는 디지털 레벨이며 음압계처럼 보정된 dB SPL이 아니다.

보고서는 요청별 설정·관측 채널 수·샘플 수·레벨·상관·중복 의심과 브라우저/사용자 입력 기종을 포함한다. 원음, 영상, deviceId/groupId, 음원 좌표는 포함하지 않는다. `physicalMicrophonesVerified`, `hardwareSynchronizationVerified`, `localizationEnabled`는 항상 false다.

## 즉시 보이는 가상 화면이 실제 성능은 아닌 이유

시뮬레이터 ‘정답 비교’는 클릭한 정답 위치를 직접 그린다. ‘마이크 추정’은 클릭한 위치에서 전파된 **합성 PCM**을 생성한 뒤 독립 엔진이 분석한다. 엔진은 음원 좌표를 받지 않지만, 동기화된 채널·알려진 센서 위치·반사 없는 자유 음장이라는 유리한 조건을 사용한다. 즉각적인 갱신은 iPhone의 실제 위치 정확도나 실시간 지연을 입증하지 않는다. 한 마이크는 방향 정보가 없고, 두 마이크의 한 관측에는 3D 모호성이 남는다.

## 실제 방향 열지도로 확장하기

1. 이 진단 결과를 iPhone 17 Pro의 실제 iOS/Safari에서 확보한다.
2. 독립된 동시 채널, 물리 센서 위치, 채널 간 고정 지연과 자동 처리의 영향을 교정한다. 채널별 자극 실험 및 알려진 방향/거리의 음원으로 검증한다.
3. 조건이 확보된 입력만 `packages/localization`에 연결한다. 카메라 축·화각·회전·크롭을 교정해 추정 방향을 영상에 투영한다. 가상 음원 좌표는 사용하지 않는다.
4. 실제 실내 잡음/반사, 주파수·거리·입사각별 오차와 처리 지연을 측정해 지원 범위를 정한다. 움직이며 관측을 누적하려면 별도 자세/위치 추적이 필요하다.
5. 필요한 채널을 제공하지 못하면 음량 진단을 유지하고, 독립 채널 접근이 가능한 외장 동시 다채널 장치 또는 네이티브 API를 검증한다. 네이티브 앱도 원시 4채널을 자동으로 보장하지 않는다.

Fluke처럼 실제 소리의 위치를 표시하려면 위의 하드웨어·교정·실측 검증이 필요하다. 현재 진단 화면에는 임의 위치 열점을 표시하지 않는다.

## 검증 상태와 공식 자료

소프트웨어 자동 검증은 합성 입력을 사용한다. 권한 오류, 취소·중지, 채널 전달/복제, 결과 다운로드와 모바일 화면을 확인하며 실기기의 마이크 검증과 구분한다. 최초 iPhone 17 Pro 보고서를 받으면 iOS/Safari 버전과 JSON 근거를 별도로 기록한다.

- [Apple iPhone 17 Pro 기술 사양](https://support.apple.com/en-my/125090): 마이크 4개 장착과 Safari의 독립 채널 노출은 별개다.
- [MDN getUserMedia](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia): HTTPS·사용자 권한·카메라 요청.
- [MDN channelCount 제약](https://developer.mozilla.org/en-US/docs/Web/API/MediaTrackConstraints/channelCount): 요청 조건과 지원 여부.
- [MDN AudioWorkletProcessor.process](https://developer.mozilla.org/en-US/docs/Web/API/AudioWorkletProcessor/process): 실제 입력 채널 배열과 가변 블록 크기.
- [Chromium의 Web Audio MediaStream 처리](https://raw.githubusercontent.com/chromium/chromium/main/third_party/blink/renderer/modules/mediastream/webaudio_media_stream_audio_sink.cc): 오디오 변환 경로를 이해하는 근거, Safari 사양으로 사용하지 않음.
- [Apple 내장 마이크 스테레오 캡처](https://developer.apple.com/documentation/avfaudio/capturing-stereo-audio-from-built-in-microphones): 네이티브 캡처 경로의 별도 검증 출발점.

확인: 2026-09-22.
