import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const { version } = JSON.parse(read('package.json'));
const lock = JSON.parse(read('package-lock.json'));
assert.match(version, /^\d+\.\d+\.\d+$/);
assert.equal(lock.version, version, 'package-lock version mismatch');
assert.equal(lock.packages[''].version, version, 'package-lock root version mismatch');
assert.ok(read('README.md').includes(`현재 버전: ${version}`), 'README version mismatch');
assert.equal(JSON.parse(read('packages/localization/package.json')).version, version, 'Engine version mismatch');
assert.ok(read('CHANGELOG.md').includes(`## [${version}]`), 'Missing changelog entry');
assert.ok(read('DEVLOG.md').includes(`### v${version}`), 'Missing DEVLOG version');
assert.ok(!read('DEVLOG.md').includes('TODO:'), 'Complete DEVLOG before publishing');
const notes = read(`docs/releases/v${version}.md`);
assert.ok(notes.includes(`# v${version}`), 'Missing release notes title');
assert.ok(!notes.includes('TODO'), 'Complete release notes before publishing');
console.log(`Release metadata verified: v${version}`);
