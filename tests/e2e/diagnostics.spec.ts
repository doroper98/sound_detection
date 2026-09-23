import { test, expect, type Page } from '@playwright/test';
import { readFileSync } from 'node:fs';

async function installMediaFixture(page: Page, mode: 'mono' | 'four' | 'duplicate' | 'ignored' | 'denied' | 'transport' | 'silent-right') {
  await page.addInitScript(mode => {
    const state = { requests: [] as string[], tracks: [] as MediaStreamTrack[] };
    Object.defineProperty(window, 'mediaFixture', { value: state });
    // Chromium's MediaStream -> Web Audio bridge converts tracks to stereo.
    // Four-channel UI cases inject a native synthetic Web Audio source at that
    // boundary; the real processor/analysis still run. These are not device tests.
    const nativeSource = AudioContext.prototype.createMediaStreamSource;
    const fixtureCounts = new WeakMap<MediaStream, number>();
    AudioContext.prototype.createMediaStreamSource = function(stream: MediaStream) {
      const count = fixtureCounts.get(stream);
      if (count === undefined || mode === 'mono' || mode === 'transport') return nativeSource.call(this, stream);
      const buffer = this.createBuffer(count, this.sampleRate, this.sampleRate);
      for (let c = 0; c < count; c++) {
        const samples = buffer.getChannelData(c);
        for (let i = 0; i < samples.length; i++) samples[i] = mode === 'silent-right' && c === 1 ? 0 : Math.sin(i * 2 * Math.PI * (mode === 'duplicate' ? 440 : 300 + c * 313) / this.sampleRate) * .1;
      }
      const source = this.createBufferSource(); source.buffer = buffer; source.loop = true; source.start();
      return source as unknown as MediaStreamAudioSourceNode;
    };
    Object.defineProperty(navigator.mediaDevices, 'getUserMedia', { configurable: true, value: async (constraints: MediaStreamConstraints) => {
      if (mode === 'denied') throw new DOMException('Denied for fixture', 'NotAllowedError');
      if (constraints.video) {
        state.requests.push('camera');
        const canvas = document.createElement('canvas'); canvas.width = 640; canvas.height = 480;
        const draw = () => { const c = canvas.getContext('2d')!; c.fillStyle = '#518878'; c.fillRect(0, 0, 640, 480); c.fillStyle = '#e0edd8'; c.fillRect(150, 100, 220, 260); };
        draw(); const stream = canvas.captureStream(10); const timer = setInterval(draw, 100); const track = stream.getVideoTracks()[0];
        const stop = track.stop.bind(track); track.stop = () => { stop(); clearInterval(timer); };
        state.tracks.push(track); return stream;
      }
      const audio = typeof constraints.audio === 'object' ? constraints.audio : {};
      const requested = typeof audio.channelCount === 'object' ? audio.channelCount.exact : undefined;
      state.requests.push(String(requested ?? 'default'));
      if (mode === 'mono' && requested) throw Object.assign(new DOMException('No requested channels', 'OverconstrainedError'), { constraint: 'channelCount' });
      const count = mode === 'mono' || mode === 'ignored' ? 1 : mode === 'silent-right' ? 2 : 4;
      const context = new AudioContext(); await context.resume();
      const destination = new MediaStreamAudioDestinationNode(context, { channelCount: count, channelCountMode: 'explicit', channelInterpretation: 'discrete' });
      const merger = context.createChannelMerger(count);
      if (mode === 'duplicate') {
        const oscillator = context.createOscillator(); oscillator.frequency.value = 440;
        for (let i = 0; i < count; i++) oscillator.connect(merger, 0, i);
        oscillator.start();
      } else for (let i = 0; i < count; i++) { const oscillator = context.createOscillator(); oscillator.frequency.value = 300 + i * 313; oscillator.connect(merger, 0, i); oscillator.start(); }
      merger.connect(destination);
      const track = destination.stream.getAudioTracks()[0]; const stop = track.stop.bind(track);
      track.stop = () => { stop(); void context.close().catch(() => {}); };
      Object.defineProperty(track, 'getSettings', { value: () => ({ channelCount: mode === 'ignored' ? 4 : count, sampleRate: context.sampleRate, deviceId: 'private-fixture-device', groupId: 'private-fixture-group' }) });
      Object.defineProperty(track, 'getCapabilities', { value: () => ({ channelCount: { min: 1, max: count } }) });
      fixtureCounts.set(destination.stream, count); state.tracks.push(track); return destination.stream;
    } });
  }, mode);
}

const liveTracks = (page: Page) => page.evaluate(() => (window as unknown as { mediaFixture: { tracks: MediaStreamTrack[] } }).mediaFixture.tracks.filter(track => track.readyState === 'live').length);
async function downloadResult(page: Page) {
  const waiting = page.waitForEvent('download'); await page.getByRole('button', { name: 'JSON 저장' }).click();
  return JSON.parse(readFileSync((await (await waiting).path())!, 'utf8'));
}

test('mobile camera and mono fallback report actual channels, stop tracks, and fit the viewport', async ({ page }) => {
  const errors: string[] = []; page.on('pageerror', error => errors.push(error.message));
  await page.setViewportSize({ width: 390, height: 844 }); await installMediaFixture(page, 'mono'); await page.goto('/diagnostics');
  expect(await liveTracks(page)).toBe(0);
  await page.getByRole('button', { name: '카메라 시작', exact: true }).click();
  await expect(page.getByText('CAMERA ON', { exact: true })).toBeVisible();
  await expect.poll(() => page.getByTestId('live-video').evaluate(video => (video as HTMLVideoElement).videoWidth)).toBe(640);
  await page.getByRole('button', { name: '4채널 검사 시작' }).click();
  await expect(page.getByRole('status')).toContainText('검사가 끝나', { timeout: 20000 });
  await expect(page.getByTestId('probe-verdict')).toContainText('안정 수신 미확인');
  const result = await downloadResult(page);
  expect(result.attempts.map((a: { requested: number | string }) => a.requested)).toEqual([4, 2, 'default']);
  // Actual browser conversion, not the requested/source count: mono -> stereo.
  expect(result.attempts[2].settings.channelCount).toBe(1);
  expect(result.attempts[2].observedChannelCounts).toEqual([2]);
  expect(result.attempts[2].duplicatePairs).toContain('1–2');
  expect(result.physicalMicrophonesVerified).toBe(false); expect(result.localizationEnabled).toBe(false);
  expect(JSON.stringify(result)).not.toContain('private-fixture'); expect(JSON.stringify(result)).not.toContain('source.position');
  expect(await liveTracks(page)).toBe(1);
  await page.getByRole('button', { name: '카메라 중지' }).click(); expect(await liveTracks(page)).toBe(0);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth && document.documentElement.scrollHeight <= innerHeight)).toBe(true);
  await page.screenshot({ path: 'test-results/live-mobile.png' }); expect(errors).toEqual([]);
});

test('reports real Chromium MediaStream conversion instead of trusting a four-channel track', async ({ page }) => {
  await installMediaFixture(page, 'transport'); await page.goto('/diagnostics');
  await page.getByRole('button', { name: '4채널 검사 시작' }).click();
  await expect(page.getByRole('status')).toContainText('검사가 끝나', { timeout: 30000 });
  const result = await downloadResult(page);
  expect(result.attempts[0].settings.channelCount).toBe(4);
  expect(result.attempts[0].observedChannelCounts).toEqual([2]);
  expect(result.physicalMicrophonesVerified).toBe(false);
});

for (const mode of ['four', 'duplicate', 'ignored'] as const) test(`observes ${mode} PCM without claiming physical microphones`, async ({ page }) => {
  await installMediaFixture(page, mode); await page.goto('/diagnostics'); await page.getByRole('button', { name: '4채널 검사 시작' }).click();
  await expect(page.getByRole('status')).toContainText('검사가 끝나', { timeout: 30000 });
  const result = await downloadResult(page);
  expect(result.attempts[0].observedChannelCounts).toEqual([mode === 'ignored' ? 1 : 4]);
  expect(result.verdict).toContain(mode === 'ignored' ? '안정 수신 미확인' : mode === 'duplicate' ? '중복 신호 의심' : '4채널 PCM 수신 확인');
  expect(result.physicalMicrophonesVerified).toBe(false); expect(result.hardwareSynchronizationVerified).toBe(false);
  expect(await liveTracks(page)).toBe(0);
  if (mode === 'four') await page.screenshot({ path: 'test-results/live-desktop.png' });
});

test('permission denial is visible', async ({ page }) => {
  await installMediaFixture(page, 'denied'); await page.goto('/diagnostics');
  await page.getByRole('button', { name: '카메라 시작', exact: true }).click(); await expect(page.getByRole('alert')).toContainText('권한');
  await page.getByRole('button', { name: '4채널 검사 시작' }).click();
  await expect(page.getByRole('status')).toContainText('권한');
  await expect(page.getByTestId('probe-verdict')).toContainText('데이터 없음');
});

test('unsupported capture is explained and its environment report can be saved', async ({ page }) => {
  await page.addInitScript(() => Object.defineProperty(navigator, 'mediaDevices', { value: undefined, configurable: true }));
  await page.setViewportSize({ width: 390, height: 844 }); await page.goto('/diagnostics');
  await page.getByRole('button', { name: '카메라 시작', exact: true }).click();
  await expect(page.getByRole('alert')).toContainText('사용할 수 없습니다');
  await page.getByRole('button', { name: '4채널 검사 시작' }).click();
  await expect(page.getByRole('status')).toContainText('사용할 수 없습니다');
  const result = await downloadResult(page);
  expect(result.environment.getUserMedia).toBe(false); expect(result.attempts).toEqual([]);
  expect(result.localizationEnabled).toBe(false);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth && document.documentElement.scrollHeight <= innerHeight)).toBe(true);
});

test('a running probe can be stopped and page exit releases the camera', async ({ page }) => {
  await installMediaFixture(page, 'four'); await page.goto('/diagnostics');
  await page.getByRole('button', { name: '4채널 검사 시작' }).click();
  await expect.poll(() => liveTracks(page)).toBeGreaterThan(0);
  await page.getByRole('button', { name: '검사 중지', exact: true }).click();
  await expect.poll(() => liveTracks(page)).toBe(0); await expect(page.getByRole('status')).toContainText('중지');
  await page.getByRole('button', { name: '카메라 시작', exact: true }).click();
  await expect(page.getByText('CAMERA ON', { exact: true })).toBeVisible();
  await page.evaluate(() => window.dispatchEvent(new Event('pagehide')));
  await expect.poll(() => liveTracks(page)).toBe(0);
});

test('continuous mono analysis measures tone and band levels, exports statistics, and restarts', async ({ page }) => {
  const errors: string[] = []; page.on('pageerror', error => errors.push(error.message));
  await installMediaFixture(page, 'silent-right'); await page.setViewportSize({ width: 390, height: 844 }); await page.goto('/listen');
  expect(await liveTracks(page)).toBe(0);
  await page.getByRole('button', { name: '카메라 시작', exact: true }).click();
  await expect(page.getByText('CAMERA ON', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: '분석 시작', exact: true }).click();
  await expect(page.getByRole('status')).toContainText('실시간 분석 중');
  await expect.poll(async () => Number((await page.getByTestId('spectrum-peak').innerText()).replaceAll(',', ''))).toBeGreaterThan(285);
  const peak = Number((await page.getByTestId('spectrum-peak').innerText()).replaceAll(',', ''));
  expect(peak).toBeLessThan(315);
  await expect(page.getByTestId('spectrum-total')).toHaveText(/-23\./);
  const waiting = page.waitForEvent('download'); await page.getByRole('button', { name: '분석 JSON 저장' }).click();
  const report = JSON.parse(readFileSync((await (await waiting).path())!, 'utf8'));
  expect(report.reportType).toBe('live-spectrum'); expect(report.stats.channels).toHaveLength(2);
  expect(report.stats.channels[1].peak).toBe(0); expect(report.localizationEnabled).toBe(false);
  expect(report.spectrum.peakHz).toBeGreaterThan(285); expect(report.selectedChannel).toBe(1);
  expect(JSON.stringify(report)).not.toMatch(/private-fixture|binsDbfs|source.position/);
  await page.getByLabel('분석 대역', { exact: true }).selectOption('1');
  await expect(page.getByTestId('spectrum-band')).toHaveText(/-23\./);
  await page.getByLabel('분석 대역', { exact: true }).selectOption('3');
  await expect.poll(async () => Number(await page.getByTestId('spectrum-band').innerText())).toBeLessThan(-80);
  await page.getByLabel('분석 채널', { exact: true }).selectOption('1');
  await expect(page.getByTestId('spectrum-total')).toHaveText('—'); await expect(page.getByTestId('spectrum-peak')).toHaveText('—');
  await page.getByLabel('분석 채널', { exact: true }).selectOption('0');
  await page.getByLabel('분석 대역', { exact: true }).selectOption('0');
  await expect(page.getByTestId('spectrum-total')).toHaveText(/-23\./);
  await page.getByLabel('실시간 소리 분석', { exact: true }).evaluate(panel => { panel.scrollTop = 0; });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth && document.documentElement.scrollHeight <= innerHeight)).toBe(true);
  await expect.poll(() => page.getByLabel('실제 주파수 분석 결과').evaluate(el => el.getBoundingClientRect().bottom <= innerHeight - 10)).toBe(true);
  await page.screenshot({ path: 'test-results/spectrum-mobile.png' });
  await page.setViewportSize({ width: 1366, height: 768 });
  await page.getByLabel('실시간 소리 분석', { exact: true }).evaluate(panel => { panel.scrollTop = 0; });
  await expect.poll(() => page.getByLabel('실제 주파수 분석 결과').evaluate(el => el.getBoundingClientRect().bottom <= innerHeight - 20)).toBe(true);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth && document.documentElement.scrollHeight <= innerHeight)).toBe(true);
  await page.screenshot({ path: 'test-results/spectrum-desktop.png' });
  await page.getByRole('button', { name: '분석 중지', exact: true }).click();
  await expect.poll(() => liveTracks(page)).toBe(1); await expect(page.getByRole('status')).toContainText('마이크를 해제');
  await page.getByRole('button', { name: '분석 시작', exact: true }).click();
  await expect(page.getByRole('status')).toContainText('실시간 분석 중');
  await page.evaluate(() => window.dispatchEvent(new Event('pagehide')));
  await expect.poll(() => liveTracks(page)).toBe(0);
  expect(errors).toEqual([]);
});

test('live monitor handles permission denial and missing capture without auto-starting', async ({ page }) => {
  await installMediaFixture(page, 'denied'); await page.goto('/listen');
  await page.getByRole('button', { name: '분석 시작', exact: true }).click();
  await expect(page.getByRole('status')).toContainText('권한');
  await expect(page.getByRole('button', { name: '분석 시작', exact: true })).toBeEnabled();
  await expect(page.getByRole('button', { name: '분석 JSON 저장' })).toBeDisabled();
  expect(await liveTracks(page)).toBe(0);
  await page.evaluate(() => Object.defineProperty(navigator, 'mediaDevices', { value: undefined }));
  await page.getByRole('button', { name: '분석 시작', exact: true }).click();
  await expect(page.getByRole('status')).toContainText('사용할 수 없습니다');
});

test('cancels pending permission and disposes its late result without restarting capture', async ({ page }) => {
  await page.addInitScript(() => {
    const state = { resolve: undefined as ((stream: MediaStream) => void) | undefined, stream: undefined as MediaStream | undefined };
    Object.defineProperty(window, 'pendingMedia', { value: state });
    Object.defineProperty(navigator.mediaDevices, 'getUserMedia', { value: () => new Promise<MediaStream>(resolve => { state.resolve = resolve; }) });
  });
  await page.goto('/listen'); await page.getByRole('button', { name: '분석 시작', exact: true }).click();
  await expect.poll(() => page.evaluate(() => !!(window as unknown as { pendingMedia: { resolve?: unknown } }).pendingMedia.resolve)).toBe(true);
  await page.getByRole('button', { name: '분석 중지', exact: true }).click();
  await page.evaluate(() => {
    const state = (window as unknown as { pendingMedia: { resolve: (stream: MediaStream) => void; stream?: MediaStream } }).pendingMedia;
    state.stream = document.createElement('canvas').captureStream(); state.resolve(state.stream);
  });
  await expect.poll(() => page.evaluate(() => (window as unknown as { pendingMedia: { stream: MediaStream } }).pendingMedia.stream.getTracks().every(track => track.readyState === 'ended'))).toBe(true);
  await expect(page.getByRole('status')).toContainText('중지'); await expect(page.getByTestId('spectrum-total')).toHaveText('—');
});
