# SoundField repository guide

Read GOAL.md, DEVLOG.md, WORKFLOWS.md and docs_canonical/ before substantive changes.

- Work against a requirement and a verifiable success criterion.
- Run `npm run gate` before committing. Run `npm run test:e2e` for interaction or renderer changes.
- A release atomically updates package.json, package-lock.json, CHANGELOG.md, DEVLOG.md and docs/releases/vX.Y.Z.md. Routine test builds do not create versions.
- Use `npm run release:prepare -- patch "summary"` (or minor/major), complete generated notes, and then verify. The UI reads the package version and the corresponding release file.
- Use TypeScript strict mode; no `any`, `@ts-ignore`, plaintext secrets or production debug logging.
- Keep pressure ground truth distinct from estimated likelihood. Never present a one-microphone direction or two-microphone single-pose solution as a unique 3D location.
- `packages/localization` must remain UI/DOM/scene independent. Feed microphone PCM into measureFrame; source coordinates belong only to src/simulation.ts and explicit reference/evaluation UI. Do not reintroduce analytic ground-truth TDOA into production inference.
- Preserve viewport fitting and mobile preview visibility when editing controls. Check both page overflow axes and hidden-tab resize behavior.
- Device spacings are illustrative virtual presets, not validated physical specifications.
- Keep documentation in Korean. Preserve historical notes. Record failed approaches and fixes in DEVLOG.md.
- Add new GOAL.md requirements as table rows only; put build history and validation narratives in DEVLOG.md. New failures must state whether the next measurement can resolve them (Y/N) and the exact required files. Research recording/replay precedes new IPA delivery; algorithm changes require the recorded-data baseline.
- Existing user authorization governs publishing/deployment; do not request it again merely because the BP reference includes an approval example.

Reference: `docs_bp/README.md` explains the adaptation of the user's YK_BP guidelines.
