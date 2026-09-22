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

`native/ios/scripts/verify.sh`를 Mac에서 실행한다. 순수 Swift 진단 테스트 → Release/iphoneos 서명 없는 빌드 → iPhone 시뮬레이터 UI 검증을 순서대로 수행한다. GitHub Native iOS workflow에서도 동일하게 실행한다. 실기기 채널 수·좌우 교정·전력/수음 지속 성능은 자동 합성 테스트와 별도다. Windows에는 Xcode가 없으므로 Mac CI 결과를 확인한 후에만 iOS 빌드 PASS로 기록한다. 개발용 프로젝트 추가는 웹 릴리즈 번호를 올리지 않으며 App Store/TestFlight 출시는 별도 작업이다.
