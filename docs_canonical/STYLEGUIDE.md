# 코드·화면 규칙

- TypeScript strict, 함수 React 컴포넌트. 컴포넌트 PascalCase, 함수 camelCase, 상수 UPPER_SNAKE.
- 음향 계산은 UI와 분리된 순수 함수로 작성한다. 벡터는 명시적인 `[number, number, number]`.
- SI 단위는 계산 경계에서 유지한다. cm/μs 등 UI 단위는 표시 시 변환한다.
- 입력은 유한수와 공간 범위로 제한한다. source 변경에 따라 이전 관측을 재사용하지 않는다.
- 렌더러, 이벤트, observer와 오디오 context의 생명주기를 정리한다.
- `any`, `@ts-ignore`, 하드코딩된 시크릿, 프로덕션 debug logging 금지.
- 앱은 밝은 회색 바탕, 흰 패널, 녹색 인터랙션, 주황 음원, 청록 마이크를 사용한다. 열지도 색과 UI 상태색을 혼동하지 않는다.
- 한국어 기능명과 명시적인 단위를 사용한다. 가상 값은 가상으로 표시한다.
- 키보드 포커스, aria-label, native dialog, 모바일 가로 넘침 방지를 유지한다.
- 아이콘 버튼은 title/aria-label로 설명한다. 새 버튼은 동작을 연결해야 한다.
- 버전은 package.json에서 빌드에 주입한다. 릴리즈 노트는 docs/releases를 UI와 GitHub가 함께 사용한다.
- 커밋: `vX.Y.Z: 변경 요약` 또는 `[SoundField] S1.2 — 설명 · REQ-... · SC-... · EXP-...`.
