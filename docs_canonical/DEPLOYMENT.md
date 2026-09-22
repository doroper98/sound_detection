# Cloudflare 배포

## v0.3.0 공개 배포 (2026-09-22)

- 영구 주소: https://soundfield-lab.pages.dev · 실제 입력 진단: https://soundfield-lab.pages.dev/diagnostics
- 배포: https://8bcdddd5.soundfield-lab.pages.dev. 기존 Pages 인증으로 성공, 재로그인 불필요.
- 공개 /diagnostics HTTP 200, version.json 0.3.0, CSP 및 `camera=(self), microphone=(self)` 확인. 캡처는 사용자 시작/권한 허용 후에만 수행한다.
- 로컬 Gate/단위 테스트 30/30, Chromium E2E 13/13 PASS. Windows WebKit의 기능 미지원 처리 1/1 PASS; 해당 환경에는 캡처 API가 없어 iPhone Safari 검증을 대체하지 못한다.
- 공개 사이트 Chromium E2E 13/13 PASS. 축소 설정·볼륨 회귀와 진단의 합성 수음/카메라 fixture를 포함한다. 실제 iPhone 수음 테스트가 아니다.
- 실제 iPhone 17 Pro 첫 보고서 확보(2026-09-22, iOS 27.0 Chrome for iOS, 공개 /diagnostics). 카메라 후면 1280×720 동작, PCM 2채널 중 1채널만 신호. 자세한 내용은 [TESTING.md](TESTING.md#iphone-17-pro-실기기-진단-첫-보고서-2026-09-22-chrome-for-ios). 공개 웹앱의 가상 결과를 실제 위치 정확도로 제시하지 않는다.

## v0.2.1 공개 배포 (2026-09-22)

- 영구 주소: https://soundfield-lab.pages.dev
- Pages OAuth 추가 인증, 프로젝트 생성 및 배포 완료. 배포 주소: https://7efc0de4.soundfield-lab.pages.dev
- 영구 주소 HTTP 200, version.json 0.2.1 및 CSP/Permissions-Policy/nosniff 확인. 공개 사이트 Chromium E2E 4/4 PASS (데스크톱/모바일 볼륨 회귀 포함).
- 로컬 Gate/25개 단위 테스트 및 4개 E2E PASS. 실제 하드웨어 캡처는 미포함.
- Wrangler 4.136은 신규 Pages 생성 명령을 Workers에 위임할 수 있다. 신규 계정에서 반드시 pages.dev 주소가 필요하면 아래 생성 명령의 `--force`로 Pages를 선택한다. 기존 프로젝트로의 이후 배포에는 필요하지 않다.
- Pages는 Wrangler 설정의 사용자 정의 경로를 지원하지 않는다. `wrangler.jsonc`의 pages_build_output_dir를 사용하고 `--config`를 전달하지 않는다.

## v0.2.0 이력

- 계정명이 없는 Pages 주소를 요청받아 `wrangler.pages.jsonc`와 배포 명령/workflow를 준비했다.
- `pages:write` 권한이 없는 기존 Workers OAuth로 Pages 프로젝트 생성을 시도했으나 Cloudflare API code 10000으로 거부됐다.
- 추가 Pages 로그인 화면이 사용자 응답 없이 만료돼 새 주소는 아직 배포 완료가 아니다. `soundfield-lab.pages.dev`는 예정 이름이며 생성·소유가 확인되지 않은 주소다.
- GitHub v0.1.0 Verify/Release workflow 성공. v0.2.0 로컬 기능 검증 성공.

## v0.1.0 이력

- 로컬 빌드와 Chromium 검증 통과.
- Cloudflare Workers 설정 준비: worker `soundfield-lab`, 정적 폴더 `dist`.
- 사용자 OAuth 로그인 완료 후 영구 Workers 배포 성공.
- Workers 최초 공개 배포 성공. 해당 계정명 포함 주소는 사용자 요청에 따라 후속 버전의 대표 주소로 사용하지 않는다.
- 최초 배포 ID: `fc774b70-3302-42cc-a182-a7c39a9aa516`. 최신 버전은 공개 `/version.json`과 Wrangler deployments에서 확인한다.
- 계정 연결 전 검토한 Quick Tunnel은 사용하지 않았다. 로컬 PC를 꺼도 Cloudflare의 정적 사이트는 유지된다.
- 공개 URL HTTP 200, version.json 0.1.0, CSP/Permissions-Policy/nosniff 및 원격 Chromium E2E 2/2 PASS.

## 계정명 없는 Pages에 배포

```sh
npx wrangler login --scopes account:read user:read workers:write workers_scripts:write pages:write
npx wrangler whoami
npx wrangler pages project create soundfield-lab --production-branch main --force
npm run deploy
```

계정이 여러 개라면 해당 계정 ID를 CLOUDFLARE_ACCOUNT_ID로 지정한다. API token은 Cloudflare Pages Edit 및 계정 조회에 필요한 범위만 지정한다. 토큰을 코드나 Git에 넣지 않는다.

배포 명령에서 반환하는 pages.dev URL을 기록하고 version.json, 보안 헤더, 브라우저 E2E를 확인한다. 새 주소 검증 후 이 작업에서 만든 이전 Worker를 정리할 수 있다. 계정 전체 workers.dev subdomain은 다른 앱에 영향을 주므로 변경하지 않는다. 롤백은 Pages 대시보드의 이전 deployment 또는 이전 Git 태그 빌드로 수행한다.

## GitHub에서 배포

production environment 또는 repository secrets에 CLOUDFLARE_API_TOKEN과 CLOUDFLARE_ACCOUNT_ID를 설정한 뒤 **Deploy Cloudflare** workflow를 실행한다. TypeScript·모델·버전·브라우저 검증을 통과한 자산만 배포한다. 계정 연결 없이 자동 배포가 되는 것으로 표기하지 않는다.

## 임시 미리보기

계정 연결 전 Cloudflare Quick Tunnel로 로컬 프로덕션 빌드를 공개할 수 있다. URL은 임시이며 로컬 서버와 tunnel 프로세스가 실행되는 동안만 유효하다. 영구 배포나 운영 가용성을 제공하지 않는다. 소스 디렉터리가 아닌 `vite preview`의 dist만 노출한다.

## 인증서

이 PC의 Node HTTPS 연결은 사내 인증서 때문에 SELF_SIGNED_CERT_IN_CHAIN이 발생했다. Node 24의 `NODE_USE_SYSTEM_CA=1`로 운영체제 신뢰 저장소를 사용해 해결했다. TLS 검증을 끄지 않았다. 필요할 때 해당 터미널에서만 설정한다.

```powershell
$env:NODE_USE_SYSTEM_CA='1'
npm ci
```

## 근거

- [Cloudflare Static Assets](https://developers.cloudflare.com/workers/static-assets/)
- [Wrangler 설정](https://developers.cloudflare.com/workers/wrangler/configuration/)
- [Quick Tunnels](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/)
