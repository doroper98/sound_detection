import { readFileSync, writeFileSync, existsSync } from 'node:fs';

const [bump, summary] = process.argv.slice(2);
if (!['major', 'minor', 'patch'].includes(bump) || !summary?.trim() || /[\r\n]/.test(summary)) {
  console.error('Usage: npm run release:prepare -- patch "변경 요약"'); process.exit(1);
}
const read = path => readFileSync(path, 'utf8');
const pkg = JSON.parse(read('package.json')); const lock = JSON.parse(read('package-lock.json'));
const parts = pkg.version.split('.').map(Number); const index = ['major', 'minor', 'patch'].indexOf(bump);
parts[index]++; for (let i = index + 1; i < 3; i++) parts[i] = 0;
const version = parts.join('.'); const date = new Date().toISOString().slice(0, 10);
const notesPath = `docs/releases/v${version}.md`;
if (existsSync(notesPath)) throw new Error(`Release already exists: ${notesPath}`);
const changelog = read('CHANGELOG.md'); const devlog = read('DEVLOG.md');
const readme = read('README.md');
pkg.version = version; lock.version = version; lock.packages[''].version = version;
writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
writeFileSync('package-lock.json', JSON.stringify(lock, null, 2) + '\n');
writeFileSync('README.md', readme.replace(/현재 버전: \d+\.\d+\.\d+/, `현재 버전: ${version}`));
writeFileSync(notesPath, `# v${version} — ${date}\n\n${summary}\n\n## 변경\n\n- TODO: 사용자에게 달라진 동작을 구체적으로 기록합니다.\n\n## 검증\n\n- TODO: CLI Gate와 브라우저 검증 결과를 기록합니다.\n\n## 제한\n\n- TODO: 해당 버전의 알려진 제한을 기록합니다.\n`);
writeFileSync('CHANGELOG.md', changelog.replace('<!-- releases -->', `<!-- releases -->\n\n## [${version}] — ${date}\n\n- ${summary}\n- [릴리즈 노트](docs/releases/v${version}.md)`));
writeFileSync('DEVLOG.md', devlog.replace('<!-- improvements -->', `<!-- improvements -->\n\n### v${version} — ${date}\n\n| 변경 | 내용 |\n|---|---|\n| 릴리즈 | ${summary} |\n\nTODO: EXP ID, 요구사항, 변경 파일 및 검증 결과 기록.`));
console.log(`Prepared v${version}. Complete ${notesPath} and DEVLOG.md, then run npm run gate and npm run test:e2e. No commit, tag, or deployment was made.`);
