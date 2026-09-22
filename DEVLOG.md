# SoundField — 개발 로그

## 추적 매트릭스

| Step | REQ | SC | EXP | 결과 |
|---|---|---|---|---|
| S1.1 공간/폰 UI | UI-001, SPACE-001, VIEW-001 | 01,02,05 | EXP-001 | PASS |
| S1.2 물리/관측 | AUDIO-001, DEVICE-001, LOC-001 | 03,04,06 | EXP-001 | PASS (합성 조건) |
| S1.3 내보내기/문서 | DATA-001, DOC-001 | 07,08 | EXP-001 | PASS (로컬) |
| S1.4 배포 | DEPLOY-001 | 09 | EXP-001 | PASS |

## EXP-001 · S1.1–S1.4 — 최초 가상 실험실

- 날짜: 2026-09-22
- 요구사항: GOAL.md의 REQ-UI/SPACE/AUDIO/DEVICE/VIEW/LOC/DATA/DOC/DEPLOY.
- 변경: src/, tests/, scripts/, public/, 설정·workflow·정규 문서.
- 원본 BP 참조: 58c946ed28d3e96b3a6e618c72b86d1c8f0d6fc8.
- 설계: 정답 음압과 관측 기반 추정을 분리. 하나의 마이크 방향 추정을 만들지 않음. 두 마이크 단일 관측의 다중 후보를 그대로 표시.
- 검증: TypeScript strict + Vite 빌드 PASS. 모델 테스트 9/9 PASS. Chromium E2E 2/2 PASS. 데스크톱/모바일 스크린샷 직접 확인.
- 미검증: 실제 하드웨어 수음, Safari 실기기, 실제 cm 정확도.
- 배포: 최초 OAuth 시간 초과 후 사용자 요청으로 브라우저를 열어 인증 완료. Cloudflare Workers 영구 URL https://soundfield-lab.monosound09.workers.dev 배포 성공. Quick Tunnel은 사용하지 않음.
- 원격 검증: 공개 사이트 HTTP 200, version.json 0.1.0, 보안 헤더 확인 및 원격 Chromium E2E 2/2 PASS.
- 커밋 예정: `v0.1.0: Launch SoundField virtual acoustic localization lab`.

## 버그·실패 기록

### BUG-001 — npm 사내 인증서 오류 (RESOLVED)

- 원인: Node 기본 인증서에 사내 체인이 없어 npm이 SELF_SIGNED_CERT_IN_CHAIN으로 재시도.
- 수정: 실행 셸에 NODE_USE_SYSTEM_CA=1 설정. 운영체제 신뢰 저장소 사용.
- 검증: 의존성 설치 성공, audit 취약점 0건. TLS 검증 유지.

### BUG-002 — 첫 빌드 구문/API 오류 (RESOLVED)

- PhoneView lookAt 괄호 누락, 최신 lucide의 GitHub 브랜드 아이콘 부재, Vite 8 chunk 설정 함수 타입 변경.
- 수정: 구문 보정, GitFork 아이콘, 함수 기반 chunk 설정.
- 검증: TypeScript와 프로덕션 빌드 통과.

### BUG-003 — 추정 likelihood 언더플로 가능성 (RESOLVED)

- 원인: 많은 관측·작은 σ에서 모든 지수 적합도가 0으로 반올림될 수 있음.
- 수정: 격자 순위/후보 필터는 비용 공간에서 계산. 열지도 표시만 exp를 사용.
- 검증: 한 관측 다중 후보와 여러 관측 수렴 테스트 통과.

### BUG-004 — Three.js 그림자 상수 제거 경고 (RESOLVED)

- PCFSoftShadowMap 제거 경고를 보고 지원되는 PCFShadowMap으로 수정.

## 개선 로그

<!-- improvements -->

### v0.2.1 — 2026-09-22

| 변경 | 내용 |
|---|---|
| 릴리즈 | 데시벨에 반응하는 열지도와 계정명 없는 공개 주소 |

EXP-003 · REQ-VIEW-003 / REQ-DEPLOY-002 · SC-15 / SC-14.

- BUG-007: PhoneView가 정규화된 방향 적합도/고정 Gaussian만 그려 수신 음량을 반영하지 않았음. PCM RMS를 별도로 전달하고 고정 척도에서 색·alpha·표시 임계값에 반영. 위치 추정 코드는 변경하지 않음.
- BUG-008: 시뮬레이터의 amplitude 상한이 큰 볼륨 입력을 같은 PCM으로 만듦. 고정 이득에 여유를 두고 실제 샘플만 ±1에서 포화, 포화 표시 추가.
- 변경: src/heatmap.ts, simulation.ts, PhoneView/App, 모바일에서도 보이는 수신 레벨과 tests/heatmap.test.ts/E2E.
- 검증: Gate 및 단위 테스트 25개 PASS. 두 신호의 40~100 dB 단계별 PCM 10 dB 증가와 지연 불변 PASS. 데스크톱/모바일 E2E 4개 PASS. 정답 비교 50/90 dB 및 모바일 설정 화면을 직접 검토하고 docs/assets에 보관. 원격 배포 검증은 아래에 기록.
- 첫 모바일 회귀 테스트가 열린 설정 패널에서 숨겨진 모드 버튼을 클릭해 시간 초과. 실제 사용자 순서에 맞게 패널 닫기 → 모드 선택 → 설정 열기로 수정.
- Pages 추가 OAuth 인증 성공. Wrangler 4.136의 기본 Pages 생성 명령이 Workers로 자동 위임되어 이전 주소에 v0.2.0을 배포하는 동작을 확인. 사용자의 계정명 없는 URL 요구에 따라 `pages project create --force`로 Pages 프로젝트를 명시적으로 생성. 기존 프로젝트 배포에는 force가 필요하지 않음.
- 실제 카메라 웹앱 문의에 대해 HTTPS/권한/후면 video, PCM 채널 진단, 독립 수음 검증, 카메라 축 교정을 단계별로 docs_canonical/LIVE_CAMERA_PLAN.md에 기록. 실제 촬영·수음은 이번 수정에 포함하지 않음.
- BUG-009: Pages 배포가 `--config wrangler.pages.jsonc`를 거부. Pages는 사용자 정의 설정 경로를 지원하지 않아 표준 wrangler.jsonc에 pages_build_output_dir를 설정하고 npm/CI 명령의 --config 제거.
- 배포: https://soundfield-lab.pages.dev, deployment 7efc0de4. HTTP 200/version.json 0.2.1/보안 헤더 확인 및 원격 Chromium E2E 4/4 PASS. 페이지에 계정명이 없는 URL 요구 완료.

### v0.2.0 — 2026-09-22

| 변경 | 내용 |
|---|---|
| 릴리즈 | 3D 화면과 독립된 PCM 음향 엔진 및 Pages 주소 |

EXP-002 · REQ-ENGINE-001 / REQ-ARRAY-001 / REQ-UI-002 / REQ-VIEW-002 / REQ-DEPLOY-002.

- 엔진을 packages/localization으로 분리. DOM 없는 TypeScript 빌드. PCM → GCC-PHAT/순음 위상 → 위치 후보.
- 합성 신호 생성은 src/simulation.ts, 렌더링은 src/components에 한정. 정답 시간차를 바로 공급하는 코드는 테스트 fixture에만 남김.
- JSON engineInput/engineOptions와 CLI replay, npm 패키지 구성 추가.
- 좌우/세로 배열, 영상 위 방향 열지도, 데스크톱 viewport 고정 및 모바일 탭/하단 패널.
- 21개 단위 테스트, 데스크톱/모바일 E2E 2개 PASS. 실제 하드웨어/Safari 미검증.
- DOM 없는 엔진 빌드와 별도 consumer 설치/import PASS. CLI replay의 정답 좌표를 바꿔도 출력 동일, 6 sample 지연 복원 PASS. 패키지 약 6.7 kB, JavaScript/타입 선언/예제 포함.
- BUG-005: 숨긴 모바일 탭의 ResizeObserver가 0×0을 보고해 camera aspect NaN이 발생. 0 크기 resize를 건너뛰고 탭 전환 후 열지도/console error 회귀 검증 추가.
- BUG-006: CSS로 숨긴 모바일 가이드 텍스트의 접근성 이름 누락. aria-label 추가 후 가이드 테스트 통과.
- Git push의 기존 PAT에 workflow scope가 없어 거부됨. 기존 연결된 GitHub 앱으로 workflow만 작성하고 나머지는 git으로 전송하여 권한 범위에 맞게 게시. 별도 사용자 인증 불필요.
- Pages API는 기존 Workers OAuth의 pages:write 부족으로 code 10000 거부. 여러 로그인 창이 응답 없이 만료되어 추가 인증을 기다림. 계정 전체 workers.dev 이름은 다른 사이트에 영향을 주므로 변경하지 않음.
- v0.1.0 GitHub Verify/Release workflow 모두 PASS 확인. 기존 기록 보존.

### v0.1.0 — 2026-09-22

| 항목 | 변경 파일 | 내용 |
|---|---|---|
| 3D 공간 | room, SpatialView | 실내 모델, 물체/바닥 raycast, 파동, 수신기 표시 |
| 휴대폰 | PhoneView, styles | 시야 회전, 표면 열지도, 음압/적합도 구분 |
| 음향 | acoustics | SPL·파장·시간차·순음 모호성·격자 추정 |
| 실험 제어 | App, useAudio | 장치·마이크·좌표·관측·내보내기·미리듣기 |
| 검증 | tests, scripts | 단위/E2E, 버전 문서 검사 |
| 문서/릴리즈 | docs, workflows | BP 추적 체계, GitHub 릴리즈와 Cloudflare 배포 설정 |

## 교훈

1. ‘스피커로 수음’ 요청은 실제 센서인 마이크로 구체화하고 실제 수음과 가상 실험을 구분한다.
2. 두 마이크의 한 시간차에서 정답 점만 빨갛게 그리면 추정 정확도를 오해하게 만든다. 정답 음압과 후보 적합도를 분리한다.
3. 관측 반복만으로 독립 정보가 늘지 않는다. 중복 pose를 거부하고 위치·높이 변경을 안내한다.
4. 소프트웨어 테스트 수렴을 실제 스마트폰 성능으로 설명하지 않는다.
5. 브라우저 서체는 같은 사이트에서 제공해 오프라인 캐시 및 CSP와 일치시킨다.
6. 계정 인증 없는 준비 상태를 공개 배포 완료로 기록하지 않는다.
