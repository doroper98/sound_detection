# Cloudflare 배포

## 현재 상태 (2026-09-22)

- 로컬 빌드와 Chromium 검증 통과.
- Cloudflare Workers 설정 준비: worker `soundfield-lab`, 정적 폴더 `dist`.
- 사용자 OAuth 로그인 완료 후 영구 Workers 배포 성공.
- 공개 주소: **https://soundfield-lab.monosound09.workers.dev**
- 최초 배포 ID: `fc774b70-3302-42cc-a182-a7c39a9aa516`. 최신 버전은 공개 `/version.json`과 Wrangler deployments에서 확인한다.
- 계정 연결 전 검토한 Quick Tunnel은 사용하지 않았다. 로컬 PC를 꺼도 Cloudflare의 정적 사이트는 유지된다.
- 공개 URL HTTP 200, version.json 0.1.0, CSP/Permissions-Policy/nosniff 및 원격 Chromium E2E 2/2 PASS.

## 계정에 영구 배포

```sh
npx wrangler login
npx wrangler whoami
npm run deploy
```

계정이 여러 개라면 해당 계정 ID를 CLOUDFLARE_ACCOUNT_ID로 지정한다. API token을 사용할 경우 Worker Scripts Edit와 계정 조회 등 배포에 필요한 범위만 지정한다. 토큰을 코드나 Git에 넣지 않는다.

배포 명령에서 반환하는 workers.dev URL을 기록하고 version.json, 보안 헤더, 브라우저 E2E를 확인한다. 이전 배포를 되돌릴 때는 Cloudflare 대시보드의 이전 버전 또는 이전 Git 태그 checkout 후 재배포를 사용한다.

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
