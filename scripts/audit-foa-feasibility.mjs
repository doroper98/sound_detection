// EXP-022: 이상적인 ACN/SN3D 합성 신호만 사용한다. iPhone 정확도 검사가 아니다.
import assert from 'node:assert/strict';
import { writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

// The extended grid uses the actual Swift analyzer. No second JS implementation
// of production rejection logic and no generated signal enters the iPhone app.
const cliIndex = process.argv.indexOf('--grid-cli');
if (cliIndex >= 0) {
  const cli = process.argv[cliIndex + 1];
  assert.ok(cli, '--grid-cli requires the compiled foa-replay executable');
  const grid = JSON.parse(execFileSync(cli, ['--benchmark'], { encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 }));
  assert.equal(grid.conditions, 1440);
  assert.equal(grid.rows.length, 1440);
  assert.equal(grid.distributions.length, 12);
  assert.equal(grid.physicalAccuracyVerified, false);
  assert.equal(new Set(grid.rows.map(r => [r.snrDb, r.reflectionGain, r.azimuthDegrees, r.seed].join('/'))).size, 1440);
  assert.ok(grid.rows.every(r => r.errorDegrees === undefined || (Number.isFinite(r.errorDegrees) && r.errorDegrees >= 0 && r.errorDegrees <= 180)));
  grid.sourceCommit = process.env.GITHUB_SHA ?? 'local';
  grid.ciRunURL = process.env.GITHUB_RUN_ID ? 'https://github.com/doroper98/sound_detection/actions/runs/' + process.env.GITHUB_RUN_ID : null;
  const outputIndex = process.argv.indexOf('--output');
  const output = outputIndex >= 0 ? process.argv[outputIndex + 1] : new URL('../docs/reports/2026-09-24-foa-synthetic-grid.json', import.meta.url);
  writeFileSync(output, JSON.stringify(grid, null, 2) + '\n');
  console.log(JSON.stringify({ conditions: grid.conditions, distributions: grid.distributions, physicalAccuracyVerified: false }));
  process.exit(0);
}
const { default: FFT } = await import('fft.js');

const size = 4096, sampleRate = 48000, fft = new FFT(size);
const rad = degrees => degrees * Math.PI / 180;
const norm = v => Math.hypot(...v);
const direction = (azimuth, elevation = 0) => [
  Math.cos(rad(elevation)) * Math.cos(rad(azimuth)),
  Math.cos(rad(elevation)) * Math.sin(rad(azimuth)), Math.sin(rad(elevation))
];
const errorDegrees = (a, b) => Math.acos(Math.max(-1, Math.min(1,
  a.reduce((sum, value, i) => sum + value * b[i], 0) / (norm(a) * norm(b))))) * 180 / Math.PI;
const empty = () => Array.from({ length: 4 }, () => new Float64Array(size));
function addPlane(channels, azimuth, elevation, bins, gain = 1) {
  const [x, y, z] = direction(azimuth, elevation);
  // ACN 순서는 W,Y,Z,X. 방향은 합성 좌표계의 음원 방위이며 실제 카메라 축과는 미대응.
  const weights = [1, y, z, x];
  for (let i = 0; i < size; i++) {
    const s = gain * bins.reduce((sum, bin) => sum + Math.sin(2 * Math.PI * bin * i / size), 0) / Math.sqrt(bins.length);
    for (let channel = 0; channel < 4; channel++) channels[channel][i] += s * weights[channel];
  }
  return channels;
}
function addNoise(channels, seed, standardDeviation) {
  let state = seed;
  for (const channel of channels) for (let i = 0; i < size; i++) {
    state = (Math.imul(1664525, state) + 1013904223) >>> 0;
    channel[i] += (state / 2 ** 32 - 0.5) * Math.sqrt(12) * standardDeviation;
  }
}
function spectra(channels) {
  return channels.map(channel => {
    const output = fft.createComplexArray();
    fft.realTransform(output, channel);
    return output;
  });
}
function estimate(channels, lowerHz = 100, upperHz = 10000) {
  const [w, y, z, x] = spectra(channels), axes = [x, y, z];
  const cross = [0, 0, 0];
  let omniPower = 0, directionalPower = 0;
  for (let bin = 1; bin < size / 2; bin++) {
    const hz = bin * sampleRate / size;
    if (hz < lowerHz || hz > upperHz) continue;
    const j = bin * 2;
    omniPower += w[j] ** 2 + w[j + 1] ** 2;
    axes.forEach((axis, i) => {
      cross[i] += w[j] * axis[j] + w[j + 1] * axis[j + 1];
      directionalPower += axis[j] ** 2 + axis[j + 1] ** 2;
    });
  }
  const length = norm(cross);
  if (omniPower < 1e-12 || directionalPower < 1e-12 || length < 1e-9 * omniPower) {
    return { direction: null, reason: 'no_resolvable_vector' };
  }
  return { direction: cross.map(value => value / length),
    vectorCoherence: length / Math.sqrt(omniPower * directionalPower),
    note: '벡터 일관성은 실제 방향이 맞다는 확률이 아니다.' };
}

const cases = [];
for (const [azimuth, elevation] of [[0, 0], [90, 0], [-90, 0], [180, 0], [0, 90], [0, -90], [37, 24], [-123, -31]]) {
  const signal = addPlane(empty(), azimuth, elevation, [64, 128, 256, 512]);
  // W의 신호 RMS가 sqrt(0.5)이므로 채널별 잡음 표준편차 sqrt(0.5)/10 = W 기준 20dB SNR.
  addNoise(signal, 123 + cases.length, Math.sqrt(0.5) / 10);
  const result = estimate(signal);
  const error = errorDegrees(result.direction, direction(azimuth, elevation));
  assert.ok(error < 1, '이상적 FOA 단일 음원 방향 복원');
  cases.push({ azimuth, elevation, errorDegrees: error, ...result });
}
const twoSources = addPlane(addPlane(empty(), -60, 0, [64]), 60, 0, [192]);
const low = estimate(twoSources, 700, 800), high = estimate(twoSources, 2200, 2300);
assert.ok(errorDegrees(low.direction, direction(-60)) < 1e-4);
assert.ok(errorDegrees(high.direction, direction(60)) < 1e-4);
const broadband = estimate(twoSources);
assert.ok(errorDegrees(broadband.direction, direction(0)) < 1e-4);

// 순음에서 반사 지연이 정수 주기인 반례. 직접음과 반사가 같은 위상이 된다.
const reflected = addPlane(addPlane(empty(), 0, 0, [64]), 90, 0, [64], 1.4);
const reflectedEstimate = estimate(reflected);
const reflectionError = errorDegrees(reflectedEstimate.direction, direction(0));
assert.ok(reflectionError > 50 && reflectedEstimate.vectorCoherence > 0.999);
const opposing = estimate(addPlane(addPlane(empty(), 0, 0, [64]), 180, 0, [64]));
assert.equal(opposing.direction, null);
assert.equal(estimate(empty()).direction, null);

const report = {
  experiment: 'EXP-022', kind: '합성 FOA 수학/실패 반례, iPhone 실측 아님',
  input: { channelOrder: ['W', 'Y', 'Z', 'X'], normalization: 'SN3D', sampleRate, samples: size,
    model: '원거리 평면파; 실제 Apple 인코더/마이크/AR/카메라 축을 모사하지 않음',
    method: '대역별 Re(conj(W) * [X,Y,Z])의 합을 정규화',
    framing: '정수 FFT bin 신호, 직사각 창. 실제 신호용 STFT/창/시간 누적은 구현하지 않음' },
  singleSource20DbOmniSNR: cases,
  frequencySeparatedSources: { sourceHz: [750, 2250], sourceAzimuthDegrees: [-60, 60], low, high, broadband,
    finding: '주파수별 방향은 분리되지만 전 대역 평균은 실제 음원 없는 중앙을 가리킨다. 일반 음원 분리의 증거는 아님.' },
  coherentReflectionCounterexample: { directAzimuth: 0, reflectionAzimuth: 90, reflectionGain: 1.4,
    errorDegrees: reflectionError, ...reflectedEstimate,
    finding: '일관성이 거의 1이어도 직접음에서 50도 이상 틀릴 수 있다. 이 점수 하나로 확정 열섬을 만들면 안 된다.' },
  equalOpposingCoherentSources: opposing,
  deviceCaptureVerified: false, cameraAxesVerified: false, physicalAccuracyVerified: false
};
writeFileSync(new URL('../docs/reports/2026-09-23-foa-feasibility-synthetic.json', import.meta.url), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({ singleSourceCount: cases.length, maxSyntheticErrorDegrees: Math.max(...cases.map(x => x.errorDegrees)),
  reflectionErrorDegrees: reflectionError, reflectionCoherence: reflectedEstimate.vectorCoherence,
  assertions: 'PASS', deviceCaptureVerified: false }));
