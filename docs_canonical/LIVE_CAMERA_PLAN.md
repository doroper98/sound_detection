# 실제 카메라·수음 웹앱 확장 계획

상태: 설계 제안. v0.2.1에는 실제 카메라·마이크 캡처가 없다.

## 카메라를 웹에서 표시

Cloudflare Pages의 HTTPS 주소를 그대로 사용할 수 있다. 사용자가 ‘카메라 시작’을 누르면 `navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: 'environment' } }, audio: false })`로 후면 카메라를 요청한다. `video.srcObject`에 스트림을 연결하고 `playsInline`, `muted`를 설정한다. 권한 거절, 장치 없음, 카메라 사용 중, 전후면 전환, 중지 및 페이지 종료 시 track.stop()을 처리한다. 서버 영상 업로드는 필요하지 않다.

현 public/_headers는 카메라와 마이크를 차단한다. 기능 추가 시 해당 origin에 대해 `camera=(self), microphone=(self)`를 허용하고 영상 렌더링에 맞는 CSP를 함께 검증해야 한다. 브라우저의 사용자 권한 승인은 여전히 필요하다. 모바일 레이아웃의 스캔 영역을 video와 canvas 오버레이로 대체하면 설정 패널과 미리보기 구조를 유지할 수 있다.

## 음량과 위치를 분리해 검증

1. 기기 진단: 마이크 권한을 별도로 요청하고 getSettings/getCapabilities, sampleRate, channelCount와 실제 AudioWorklet의 PCM 채널 수를 표시한다. echoCancellation, noiseSuppression, autoGainControl 비활성화를 요청하되 실제 적용 결과를 기록한다.
2. 음량 모드: 한 채널이어도 PCM 레벨/스펙트럼은 표시할 수 있다. 음량만으로 화면의 특정 위치에 열점을 만들지 않는다.
3. 방향 모드: 독립된 동시 마이크 채널과 실제 센서 위치를 확인한 경우만 packages/localization에 전달한다. channelCount=2 보고만으로 물리적으로 독립된 두 마이크라고 판단하지 않는다. 복제·혼합 채널과 시간 지연을 별도 실험으로 검증한다.
4. 영상 정렬: 센서 좌표계와 카메라 축, 화각, 회전·크롭·화면비를 교정한 뒤 추정 방향을 영상 픽셀로 투영한다. 휴대폰을 움직여 관측을 누적하려면 별도 자세/위치 추적이 필요하다. 클릭한 가상 음원 좌표를 실제 추정에 사용하지 않는다.
5. 지원 불가 기기: 방향 탐지를 비활성화하고 음량 모드를 유지한다. 외장 동시 다채널 인터페이스나 물리 채널 접근이 가능한 네이티브 API를 검토한다. 서로 다른 휴대폰 두 대의 네트워크 도착 시각은 음향 TDOA 동기화가 아니다.

초기 목표는 **실제 영상 + 실제 음량 + 수음 기능 진단**이다. Fluke처럼 정확한 방향 열지도를 제공하는 단계는 하드웨어 채널 접근성, 센서/영상 교정과 실측 오차 검증을 통과해야 한다. 단일 배열의 두 센서에는 3D 모호성이 남는다.

## 실기기 검증 기준

- 대상 iPhone/iPad 모델, iOS/Safari 버전 또는 Android 모델/Chrome 버전을 기록한다.
- 첫 권한 요청, 거절 후 재시도, 탭 전환/백그라운드, 화면 회전, 카메라 전환/중지와 모바일 스크롤을 검증한다.
- 채널별 독립 신호와 동기화, 자동 처리, known source를 이용한 방향 오차를 확인한다. 방향을 검증하기 전에는 실제 위치 탐지 성공으로 표시하지 않는다.

## 공식 자료

- [MDN getUserMedia](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia): HTTPS, 권한, 전후면 선택.
- [MDN 제약·기능·설정](https://developer.mozilla.org/en-US/docs/Web/API/Media_Capture_and_Streams_API/Constraints): 요청과 실제 설정 구분.
- [MDN channelCount](https://developer.mozilla.org/en-US/docs/Web/API/MediaTrackSettings/channelCount): 실제 적용된 채널 수.

확인: 2026-09-22.
