# 참고한 BP와 이 프로젝트의 적용

원본: https://github.com/doroper98/YK_BP/tree/main/docs_bp

참조 커밋: `58c946ed28d3e96b3a6e618c72b86d1c8f0d6fc8` (2026-09-22 확인).

BP_INDEX, BP_REQUIREMENTS, BP_PROJECT_STRUCTURE, BP_TESTING, BP_VERSIONING, BP_DEVLOG, BP_WORKFLOW, BP_CLAUDE_MD를 읽고 다음 체계를 적용했다.

| BP 원칙 | 적용 위치 |
|---|---|
| 요구사항·성공 기준 추적 | GOAL.md, DEVLOG.md |
| 정규 문서 4종 | docs_canonical/ARCHITECTURE.md, STYLEGUIDE.md, TESTING.md, REPO_MAP.md |
| CLI Gate | npm run gate, GitHub Verify workflow |
| 원자적 버전 관리 | package/lock + CHANGELOG + DEVLOG + docs/releases |
| 실험·버그·교훈 축적 | DEVLOG.md |
| 세션 간 지식 유지 | AGENTS.md, CLAUDE.md, WORKFLOWS.md |

웹 프로젝트에 맞게 Electron 패키징 대신 Cloudflare 정적 자산과 사이트 ZIP을 사용한다. 단일 기본 브랜치는 main이다. ‘빌드=버전’은 배포 가능한 릴리즈 단위에 적용하며 실패 재시도나 검증용 빌드마다 버전을 올리지는 않는다. 모델의 수학적 정확성과 추정 제약을 확인하기 위해 단위 테스트와 브라우저 테스트를 포함한다. 사용자 요청에 이미 포함된 배포·저장소 게시를 BP 예시 때문에 재승인받지 않는다.
