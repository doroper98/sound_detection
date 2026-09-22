# 음향 모델과 해석

## 단위와 좌표

- m, s, Hz, dB SPL을 사용한다. X=좌우, Y=높이, Z=앞뒤.
- 가상 음속 c=343 m/s. 온도는 입력하지 않는다.
- λ=c/f. 주파수와 파장은 독립 변수가 아니므로 한쪽 변경 시 다른 쪽이 연동된다.
- 기준 볼륨은 음원에서 1 m 떨어진 자유 음장 SPL이다. L(r)=L(1m)−20 log10(max(r,0.1)). 음원 바로 옆의 수학적 발산을 막기 위해 0.1 m에서 제한한다.

## 가상 마이크

수신점 P를 중심으로 두 마이크를 P±d·u/2에 둔다. 좌우 배열은 u=(cos(yaw),0,sin(yaw)), 세로 배열은 u=(−sin(yaw)sin(pitch),cos(pitch),cos(yaw)sin(pitch))이다. 카메라의 좌우/상하 축에 대응하는 가상 배열이며 실제 기기 마이크 배치를 재현한다고 주장하지 않는다. 좌우 배열은 방위, 세로 배열은 고도 차이에 민감하지만 어느 쪽도 두 센서만으로 모든 3D 방향을 결정하지 못한다.

기본 간격: iPhone 15 Pro=0.12 m, iPad Pro 11″=0.20 m, Galaxy S24=0.13 m. **실측·제조사 사양이 아니다.** 기기 외형과도 일치한다고 가정하지 않는다. 사용자 정의로 0.02~2 m를 조절한다.

## 도착 시간차와 적합도

물리적 전파 시간차의 이론값은 τ=(|S−M₀|−|S−M₁|)/c다. v0.2.0부터 이 정답 시간차를 추정기에 직접 제공하지 않는다. 시뮬레이터가 각 마이크의 지연·감쇠를 적용한 Float32 PCM을 생성하고, 별도 엔진이 PCM을 분석해 관측 시간차를 얻는다. 엔진에는 S가 전달되지 않는다. 후보 Q에 대한 잔차 r=τ(Q)−τ(observed)를 계산한다.

- 광대역 모델: 고정 seed 잡음을 설정 주파수의 2배를 척도로 하는 저역 필터에 통과시켜 합성 PCM을 만든다. 엔진은 평균 제거/Hann window/zero padding/GCC-PHAT/물리 지연 범위 탐색/peak 보간을 수행한다. 실제 마이크 수음은 아니지만 위치 추정의 입력은 PCM이다.
- 단일 주파수 모델: r←r−round(r·f)/f. 한 주기 차이의 지연을 구별하지 못하는 순음 위상 모호성을 표시한다.
- 광대역 σ는 실제 상관 peak의 반치폭과 돌출도에서 만든 휴리스틱이며 최소 0.5 sample을 사용한다. 정답 좌표나 알려진 음원 SPL을 사용하지 않는다. 순음 σ=max(0.5/fs,0.02/f) 역시 휴리스틱이다. 공분산 또는 정확도 보정식으로 해석하지 않는다.
- 비용 C=Σ(rᵢ/σᵢ)². 표면 적합도 exp(−C/2)를 색으로 표시한다. 확률적으로 보정된 신뢰도가 아니다.
- 20 cm 격자 최고 후보를 찾고, C≤Cmin+3인 후보 개수와 최고점부터 가장 먼 후보의 거리를 표시한다. 절대 신뢰구간이나 오차 보장이 아니다.

음원·볼륨·주파수·신호·배열 간격·마이크 수 변경 시 저장 관측을 비운다. 수신기 위치/자세 변경은 저장 관측을 유지한다. 거의 같은 마이크 위치(두 이동 거리 합 ≤8 cm)는 중복으로 저장하지 않는다. 최대 12개.

## 위치를 유일하게 찾을 수 있는가

1개 무지향성 마이크에는 시간차가 없다. 2개 마이크의 단일 시간차는 일반적으로 3D 공간에서 쌍곡면 위의 후보를 만든다. 이 때문에 높은 적합도 영역이 넓게 남는 것이 정상이다. 마이크 간격이 넓으면 기하학적 지연 변화가 커질 수 있지만, 순음에서는 주기적 모호성이 커진다.

여러 독립 위치·방향·높이에서 관측하면 후보를 좁힐 수 있다. 실제 환경에서는 음원이 고정되어야 하고 장치 위치·자세 및 시간차의 교정이 필요하다. 본 시뮬레이터는 이 정보를 정확히 안다고 가정한다. 단위 테스트의 21 cm 미만 기준은 특정 잡음 없는 4관측/20 cm 격자 사례에만 해당한다.

## 열지도

기본 ‘마이크 추정’은 카메라의 광선 방향별로 0.3~10 m의 고정 탐색 거리들에서 관측 적합도를 평가하고 최대값을 투명한 색으로 겹친다. 여러 관측으로 좁혀진 후보가 있으면 그 추정 거리도 평가한다. 배경 mesh와 raycast 교차를 사용하지 않아 공중 후보도 표시할 수 있다. 시야 변환은 표시용 카메라 정보일 뿐 음향 엔진 입력이 아니다. 두 마이크만으로 남는 띠를 작은 점으로 숨기지 않는다.

‘정답 비교’는 설정된 위치에 시각적 색 표식과 별도 라벨을 그린다. 표식의 그라데이션은 비교용이며 측정된 공간 음압 분포가 아니다. 수신 SPL 숫자도 이 모드에서만 알려진 설정으로 계산한다. 추정 화면의 dBFS는 실제 엔진 입력 PCM 기준 레벨이고 SPL로 교정되지 않았다.

Fluke와 같은 영상 위 겹침 표현을 참고했지만 동일 장비·알고리즘·정확도를 재현하지 않는다. [Fluke ii900 공식 사양](https://www.fluke.com/en-us/product/industrial-imaging/sonic-industrial-imager-ii900)은 64개 MEMS 마이크와 시각 영상 위 SoundMap을 설명한다. 두 마이크 시뮬레이션의 관측 가능성은 다르다.

## 독립 엔진의 경계

`packages/localization`은 fft.js와 자체 파일만 import한다. DOM 타입 없이 빌드된다. 입력은 PCM, sampleRate, 센서 배치, 동기화 선언, 선택적 측정 옵션과 탐색 범위다. src/room.ts, Source, INITIAL_SOURCE, 렌더링 및 정답 좌표를 읽지 않는다. JSON replay 역시 source/receiver/기존 result를 읽지 않는다. 마이크 배치 좌표는 센서 교정값이며 탐색기의 정답 정보가 아니다.

실제 앱에 필요한 캡처 및 시간 동기화는 별도다. 앱이 동기화됐다고 선언한 채널의 실제 하드웨어 동기화를 라이브러리가 보증하지 않는다. 상세 API: [SDK README](../packages/localization/README.md).

## 실제 휴대폰 수음으로 확장할 때

브라우저 `getUserMedia`는 사용자 동의와 HTTPS가 필요하다. `channelCount: 2`를 요청하더라도 두 개의 물리 마이크가 원시 독립 채널로 제공된다는 보장은 없다. getSettings/getCapabilities와 실제 PCM을 확인하고, 자동 이득·잡음 억제·반향 제거·채널 혼합도 검증해야 한다. 별도 휴대폰 두 대는 공통 시간축이 없으므로 단순 네트워크 수신 시간으로 μs급 도착 시간차를 계산할 수 없다.

실제 구현의 다음 순서: 기기별 채널 조사 → 동시 다채널 하드웨어/네이티브 API 검증 → 지연 교정 → 광대역 상관/GCC-PHAT → 자세·위치 추정 → 반사/잡음 환경 실측 평가. 현재 앱은 이 작업의 완료를 주장하지 않는다.

## 근거 자료

- [MathWorks: TDOA 위치 추정](https://www.mathworks.com/help/fusion/ug/object-tracking-using-time-difference-of-arrival.html): 시간차와 쌍곡면/다중 수신기 관측의 기하.
- [MDN: getUserMedia](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia): HTTPS와 권한, 입력 제약.
- [MDN: channelCount 설정](https://developer.mozilla.org/en-US/docs/Web/API/MediaTrackSettings/channelCount): 실제 설정된 채널 수의 확인과 지원 제한.
- [MDN: MediaTrackConstraints](https://developer.mozilla.org/en-US/docs/Web/API/MediaTrackConstraints): 채널·샘플링·음성 처리 제약.

자료 확인: 2026-09-22. [GCC-PHAT 설명](https://www.mathworks.com/help/phased/ref/gccphat.html), [FFT.js](https://github.com/indutny/fft.js)도 참조했다. 본 프로젝트의 σ 및 후보 임계값은 자체 휴리스틱이다.
