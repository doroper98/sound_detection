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
