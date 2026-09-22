# SoundField repository guide

Read GOAL.md, DEVLOG.md, WORKFLOWS.md and docs_canonical/ before substantive changes.

- Work against a requirement and a verifiable success criterion.
- Run `npm run gate` before committing. Run `npm run test:e2e` for interaction or renderer changes.
- A release atomically updates package.json, package-lock.json, CHANGELOG.md, DEVLOG.md and docs/releases/vX.Y.Z.md. Routine test builds do not create versions.
- Use `npm run release:prepare -- patch "summary"` (or minor/major), complete generated notes, and then verify. The UI reads the package version and the corresponding release file.
- Use TypeScript strict mode; no `any`, `@ts-ignore`, plaintext secrets or production debug logging.
- Keep pressure ground truth distinct from estimated likelihood. Never present a one-microphone direction or two-microphone single-pose solution as a unique 3D location.
- Device spacings are illustrative virtual presets, not validated physical specifications.
- Keep documentation in Korean. Preserve historical notes. Record failed approaches and fixes in DEVLOG.md.
- Existing user authorization governs publishing/deployment; do not request it again merely because the BP reference includes an approval example.

Reference: `docs_bp/README.md` explains the adaptation of the user's YK_BP guidelines.
