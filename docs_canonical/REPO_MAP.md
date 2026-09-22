# 파일 지도

| 경로 | 역할 |
|---|---|
| src/App.tsx | 실험 상태, 입력 패널, 관측, 내보내기, 가이드/릴리즈 |
| src/acoustics.ts | 물리, 가상 장치, 합성 관측, 위치 후보 탐색 |
| src/room.ts | 공유 3D 실내 geometry, 조명, 리소스 정리 |
| src/components/SpatialView.tsx | 왼쪽 orbit/raycast 배치와 파동 |
| src/components/PhoneView.tsx | 카메라 방향, 표면 raycast, 열지도 |
| src/useAudio.ts | 클릭 후 작은 정현파 출력과 음소거 |
| src/styles.css | 반응형 UI, 폰 외형, 한국어/라틴 폰트 |
| tests/acoustics.test.ts | 음향·관측 가능성 단위 테스트 |
| tests/e2e/simulator.spec.ts | 사용자 동작과 모바일 검증 |
| scripts/ | 버전 준비 및 릴리즈 무결성 확인 |
| .github/workflows/ | main/PR 검증, 태그 릴리즈, 수동 Cloudflare 배포 |
| public/_headers | Cloudflare 보안 헤더 |
| wrangler.jsonc | soundfield-lab 정적 자산 배포 |
| docs/releases/ | 버전별 한국어 노트 (UI와 GitHub가 공유) |
| docs_canonical/ | 설계·모델·검증·운영 문서 |
| docs_bp/README.md | 원본 BP 출처와 적용 방식 |

런타임 데이터는 브라우저 메모리에만 있다. 내보내기는 사용자의 기본 다운로드 경로에 JSON을 만든다. dist/는 정적 빌드, version.json은 package 버전을 노출한다. .local/은 로컬 실행/스크린샷/배포 보조 도구용이며 Git에서 제외한다. .wrangler/와 환경 파일도 제외한다.
