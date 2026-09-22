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

## 브라우저 테스트 (2개 시나리오)

1. 데스크톱: 화면, 클릭 배치, 주파수↔파장, 폰 드래그, 단일 마이크 제약, 저장 관측 초기화, 기종 간격, 다른 높이/위치의 3관측 누적과 결과 표시, JSON 내용 검증, 릴리즈 노트, 전체 초기화, console pageerror 없음.
2. 390×844 모바일: 가로 넘침 없음, heatmap alpha가 실제 생성됨, OFF 시 비어 있음, native dialog 열기/Escape 닫기.

`test-results/desktop.png`, `mobile.png`를 화면 검토 증거로 생성한다. Git에는 넣지 않으며 CI에서 artifact로 보관한다. 테스트 환경의 SwiftShader는 기능 확인용이며 실제 GPU 성능을 대표하지 않는다.

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
- 실제 수음·장치 정확도는 현 버전 범위 밖이다. 소프트웨어 테스트를 실측 정확도 증거로 사용하지 않는다.
