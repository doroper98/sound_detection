# 검증

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
