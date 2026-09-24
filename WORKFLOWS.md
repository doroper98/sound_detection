# 개발·검증·릴리즈 절차

1. GOAL.md에 REQ와 성공 기준을 먼저 추가/갱신한다.
2. 해당 코드를 구현하고 필요한 물리 모델/동작 테스트를 추가한다.
3. `npm run gate`로 타입 검사, 빌드, 음향 테스트, 버전 문서 일치를 확인한다.
4. 화면/인터랙션 변경은 `npm run test:e2e`와 스크린샷 검토를 수행한다.
5. DEVLOG.md에 EXP, REQ, SC, 실패 원인, 수정과 검증 결과를 기록한다.
6. 신규 릴리즈는 `npm run release:prepare -- minor "변경 요약"`로 버전을 준비한다. PATCH=수정, MINOR=기능 추가, MAJOR=호환성 변경/정식 릴리즈.
7. 생성된 릴리즈 노트와 DEVLOG의 TODO를 실제 내용으로 채우고 Gate를 통과한다. 검증을 위한 재빌드는 버전을 소비하지 않는다.
8. `git commit -m "vX.Y.Z: 변경 요약"`, `git tag -a vX.Y.Z -m "SoundField vX.Y.Z"`, `git push origin main --follow-tags`.
9. Release workflow가 태그/버전 일치 및 브라우저 검증 후 GitHub 릴리즈와 사이트 ZIP을 생성한다.
10. Cloudflare 인증이 있으면 `npm run deploy`, 배포 후 공개 URL에서 브라우저 검증한다. GitHub의 Deploy Cloudflare workflow는 production secrets 설정 후 수동 실행 가능하다.

첫 공개 전 사용자 피드백이 없으면 자동 검증과 수동 화면 검토 결과를 명확히 구분한다. 테스트 PASS를 사용자 승인이나 실제 하드웨어 검증으로 기록하지 않는다.

## 네이티브 iOS 작업

연구 녹음 변경은 먼저 `gh workflow run native-ios.yml --ref <브랜치> -f researchOnly=true`로 동일 Swift 녹음/재생 계약을 확인한다. 이 경로는 IPA를 만들지 않는다. 일반 검증은 core 계약 → Release 기기 컴파일 → UI 중지/백그라운드/공유 → **실제 시뮬레이터 앱이 쓴 파일을 CLI 재생하고 ZIP 검사** → IPA 포장 순서다. Windows 작업은 동일 패키지를 빌드하고 Swift가 PATH에 없는 상태에서도 동봉 런타임으로 재생하는지 검사한다. CI에는 명시적 합성 세션만 업로드한다. 사용자가 제공한 실제 원음은 공개 CI나 Git에 넣지 않는다.

빌드 12 focused 목록은 연구 녹음 2개를 포함한 UI 10개다. 원음은 기본 OFF이며 연구 녹음 UI/생명주기만 이번에 추가한다. 실제 10세션의 축 검증·90세션의 오차 기준선 전에는 추정 기준 변경 및 기존 보정 삭제를 하지 않는다. 측정/공유 절차는 [GROUND_TRUTH_PROTOCOL](docs_canonical/GROUND_TRUTH_PROTOCOL.md), 원문 판정의 적용 범위는 [외부 검토 반영표](docs/reviews/2026-09-24-review-disposition.md)에 있다.

### 사용자 실측 수정의 빠른 전달 (2026-09-23)

사용자가 반복 수정의 속도 개선을 요청했다. 개발 빌드는 `gh workflow run native-ios.yml --ref <현재 브랜치>`로 수동 실행하면 순수 Swift 전체 + Release 기기 빌드 + 현재 수정 및 핵심 수음 생명주기 UI 8개(빌드 11)를 먼저 검증한다. PR/main 자동 실행은 전체 UI 회귀를 그대로 수행한다. 다음 수정 때 focused 목록은 바뀐 기능에 맞게 갱신한다. 웹 코드를 바꾸지 않은 네이티브 수정에서 로컬 웹 E2E 반복을 사용자 IPA 전달의 선행 조건으로 두지 않는다. 웹 변경에는 기존 gate/E2E 규칙을 적용한다.

`NATIVE_UI_SCOPE=full` 또는 `focused`로 스크립트 실행 범위를 명시할 수 있다. 증거에 `ui-test-scope.txt`를 남기며 focused 통과를 전체 회귀 통과라고 표현하지 않는다. 첫 focused 실행은 새 보정 검사 2개를 포함해 5/6 통과했고 기존 파형 조회의 5초 대기가 시간 초과했다. 같은 앱의 전체 실행은 27/27 통과했으며, 이후 해당 UI 검사만 채널별 순차 30초 대기로 보완했다. 단축 시간을 수치로 보장하지 않는다. 자동 전체 회귀에서 문제가 나오면 수정 대상이다. 실기기 입력/정확도 검증은 어느 실행 범위에서도 별개다.

`native/ios/scripts/verify.sh`를 Mac에서 실행한다. 순수 Swift 진단 테스트 → Release/iphoneos 서명 없는 빌드 → iPhone 시뮬레이터 UI 검증을 순서대로 수행한다. GitHub Native iOS workflow에서도 동일하게 실행한다. 실기기 채널 수·좌우 교정·전력/수음 지속 성능은 자동 합성 테스트와 별도다. Windows에는 Xcode가 없으므로 Mac CI 결과를 확인한 후에만 iOS 빌드 PASS로 기록한다. 개발용 프로젝트 추가는 웹 릴리즈 번호를 올리지 않으며 App Store/TestFlight 출시는 별도 작업이다.
