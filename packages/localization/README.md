# @soundfield/localization

3D 화면, React, Three.js, 브라우저 API 없이 동작하는 TypeScript/JavaScript 음향 엔진입니다. 유일한 런타임 의존성은 FFT 계산용 fft.js입니다. ES2022 환경에서 사용하며, 실제 마이크 PCM 수집은 앱이 담당합니다.

## 엔진이 받는 것

- 동일 샘플 클록에서 동시 수집된 마이크별 Float32 PCM
- 샘플링 주파수와 마이크 위치(미터)
- 선택적 신호 종류/알려진 순음 주파수, 음속
- 위치 탐색을 호출할 때 앱이 지정하는 탐색 범위

**음원의 위치, 3D mesh, 물체, 방 크기, 카메라 영상, 정답 데이터는 받지 않습니다.** 마이크 배치 좌표는 센서 교정값이고 음원 정답 좌표와 다릅니다.

```ts
import { measureFrame, localize } from '@soundfield/localization';

const measurement = measureFrame({
  channels: [leftPcm, rightPcm], // 동시 수집 Float32Array, 길이가 같아야 함
  sampleRate: 48000,
  microphonePositions: [[-0.06, 0, 0], [0.06, 0, 0]], // 폰 기준 좌표
  synchronized: true,
});

// 기존 관측과 합칠 경우 모든 마이크 위치를 같은 교정 좌표계로 변환해야 함.
const estimate = localize(measurement.observations, {
  min: [-5, -3, -8], max: [5, 3, -0.2], step: 0.2,
});
// estimate.candidates와 spread를 확인. 최고 후보가 유일한 실제 위치라는 뜻은 아님.
```

마이크 3개 이상도 입력할 수 있으며 첫 채널과 나머지 채널의 쌍별 시간차를 반환합니다. 기준 채널을 공유하는 측정 사이의 통계적 상관은 현재 비용 함수에서 모델링하지 않으므로 적합도를 확률 신뢰도로 해석하지 않습니다.

## 빌드·패키징·재생

저장소 루트에서:

```sh
npm ci
npm run build:engine
npm pack ./packages/localization
node packages/localization/examples/replay.mjs experiment.json
```

웹 앱에서 ‘실험 내보내기’로 저장한 JSON을 replay에 전달합니다. replay는 `engineInput`, `engineOptions`, `searchVolume`만 읽습니다. JSON의 source.position을 바꿔도 결과는 바뀌지 않습니다. JSON의 channels는 Float32Array로 복원합니다.

React Native 등 JS 환경은 패키지로 사용합니다. Swift/Kotlin 앱은 독립 함수와 입력/출력 계약을 기준으로 포팅하거나 별도의 JS 런타임을 사용할 수 있습니다. 플랫폼별 수음 모듈이나 네이티브 바인딩은 이 패키지에 포함하지 않습니다.

## 처리와 제약

- 평균 제거, Hann window, 2N zero padding, FFT cross spectrum, PHAT 정규화, 물리적으로 가능한 지연 범위 탐색, 3점 포물선 보간.
- 순음은 알려진 주파수에서 두 채널의 위상차를 측정하고 주기 모호성을 보존합니다.
- delay 부호는 도착시간(M0)−도착시간(M1). 양수이면 M0에 더 늦게 도착합니다.
- sigma는 상관 peak 폭/돌출도로 만든 휴리스틱이고 교정된 측정 공분산이 아닙니다.
- levelDbfs는 PCM 기준 dBFS이며 dB SPL이 아닙니다. SPL은 마이크 감도 교정 없이는 알 수 없습니다.
- 무음·채널 길이 불일치·비동기 채널·잘못된 샘플링값을 거부합니다. 같은 샘플 클록이라는 앱의 선언 자체를 하드웨어 수준에서 검증하지는 못합니다.
- 독립 휴대폰 두 대의 네트워크 도착 시각은 이 입력 계약을 충족하지 않습니다.
- 두 마이크 한 관측은 유일한 3D 위치를 보장하지 않습니다. 다중 pose에는 정지 음원과 알려진 장치 pose가 필요합니다.
- 반사·다중 음원·바람·장치 후처리·클리핑에 대한 실측 검증은 아직 없습니다. 앱 상용 정확도는 별도 데이터로 평가해야 합니다.

설계 근거: [MathWorks GCC-PHAT](https://www.mathworks.com/help/phased/ref/gccphat.html), [FFT.js 원본](https://github.com/indutny/fft.js).
