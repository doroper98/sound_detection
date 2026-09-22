# 파일 지도

| 경로 | 역할 |
|---|---|
| src/App.tsx | 실험 상태, 입력 패널, 관측, 내보내기, 가이드/릴리즈 |
| src/acoustics.ts | 시뮬레이터의 물리 기준값·장치 프리셋·센서 배치, 독립 엔진의 호출 범위 |
| packages/localization/ | 3D 화면과 독립된 PCM/DSP/위치 추정 패키지, API 문서와 CLI replay |
| src/simulation.ts | 정답 위치를 아는 유일한 PCM 합성 어댑터 |
| src/heatmap.ts | PCM 레벨·포화 측정과 고정 색상 척도, 위치 추정과 분리 |
| src/layout.css | viewport 맞춤, 모바일 탭·설정 패널 |
| tests/engine.test.ts | PCM 분석, 좌표/화면 독립성, 임의 공간과 배열 회귀 |
| src/room.ts | 공유 3D 실내 geometry, 조명, 리소스 정리 |
| src/components/SpatialView.tsx | 왼쪽 orbit/raycast 배치와 파동 |
| src/components/PhoneView.tsx | 카메라 광선 방향과 PCM 레벨 기반 열지도 |
| src/useAudio.ts | 클릭 후 작은 정현파 출력과 음소거 |
| src/styles.css | 반응형 UI, 폰 외형, 한국어/라틴 폰트 |
| tests/acoustics.test.ts | 음향·관측 가능성 단위 테스트 |
| tests/heatmap.test.ts | 볼륨별 PCM 레벨, 지연 불변, 포화와 표시 임계값 |
| tests/e2e/simulator.spec.ts | 사용자 동작과 모바일 검증 |
| scripts/ | 버전 준비 및 릴리즈 무결성 확인 |
| .github/workflows/ | main/PR 검증, 태그 릴리즈, 수동 Cloudflare 배포 |
| public/_headers | Cloudflare 보안 헤더 |
| wrangler.jsonc | soundfield-lab Pages 정적 배포 설정 (pages_build_output_dir) |
| docs/releases/ | 버전별 한국어 노트 (UI와 GitHub가 공유) |
| docs_canonical/ | 설계·모델·검증·운영 문서 |
| docs_bp/README.md | 원본 BP 출처와 적용 방식 |

런타임 데이터는 브라우저 메모리에만 있다. 내보내기는 사용자의 기본 다운로드 경로에 JSON을 만든다. dist/는 정적 빌드, version.json은 package 버전을 노출한다. .local/은 로컬 실행/스크린샷/배포 보조 도구용이며 Git에서 제외한다. .wrangler/와 환경 파일도 제외한다.
