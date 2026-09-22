import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';

const version = JSON.parse(readFileSync('package.json', 'utf8')).version;

for (const mobile of [false, true]) test(`volume changes heatmap area and intensity in both modes (${mobile ? 'mobile' : 'desktop'})`, async ({ page }) => {
  if (mobile) await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/');
  const heatStats = () => page.getByTestId('heatmap-canvas').evaluate(async element => {
    // React commits the new level before PhoneView paints it on the next frame.
    // Wait through rendering, including other rAF callbacks in that frame.
    await new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => setTimeout(resolve, 0))));
    const canvas = element as HTMLCanvasElement;
    const pixels = canvas.getContext('2d')!.getImageData(0, 0, canvas.width, canvas.height).data;
    let area = 0; let alpha = 0; let warm = 0;
    for (let i = 0; i < pixels.length; i += 4) if (pixels[i + 3] > 0) {
      area++; alpha += pixels[i + 3];
      if (pixels[i] > 220 && pixels[i + 2] < 100) warm++;
    }
    return { area, alpha, warm };
  });
  for (const mode of ['마이크 추정', '정답 비교']) {
    await page.getByRole('button', { name: mode, exact: true }).click();
    if (mobile) await page.getByRole('button', { name: '실험 설정', exact: true }).click();
    await expect(page.getByTestId('pcm-level')).toBeVisible();
    await page.getByLabel('볼륨', { exact: true }).fill('50');
    await expect.poll(async () => (await heatStats()).area).toBeGreaterThan(0);
    const quietLevel = Number.parseFloat((await page.getByTestId('pcm-level').textContent())!);
    await expect.poll(async () => (await heatStats()).warm).toBe(0);
    const quiet = await heatStats();
    await page.getByLabel('볼륨', { exact: true }).fill('90');
    await expect.poll(async () => (await heatStats()).area).toBeGreaterThan(quiet.area * 1.1);
    const loud = await heatStats();
    expect(loud.alpha).toBeGreaterThan(quiet.alpha * 1.5);
    expect(loud.warm).toBeGreaterThan(quiet.warm);
    const loudLevel = Number.parseFloat((await page.getByTestId('pcm-level').textContent())!);
    expect(loudLevel - quietLevel).toBeCloseTo(40, 1);
    if (!mobile && mode === '정답 비교') await page.screenshot({ path: 'test-results/volume-90.png' });
    await page.getByLabel('볼륨', { exact: true }).fill('50');
    await expect.poll(async () => (await heatStats()).area).toBe(quiet.area);
    if (!mobile && mode === '정답 비교') await page.screenshot({ path: 'test-results/volume-50.png' });
    if (mobile) await page.getByRole('button', { name: '설정 패널 닫기', exact: true }).click();
  }
  await expect(page.getByTestId('phone-viewport')).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollHeight <= window.innerHeight && document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
});

test('places a source, links acoustics, rotates the phone, changes microphone modes and exports', async ({ page }) => {
  const errors: string[] = []; page.on('pageerror', error => errors.push(error.message));
  await page.goto('/'); await expect(page.getByRole('heading', { name: '소리가 나는 곳을, 눈으로.' })).toBeVisible();
  const settings = () => page.getByRole('button', { name: '실험 설정', exact: true }).click();
  const analysis = () => page.locator('.dock-tabs').getByRole('button', { name: /관측/ }).click();
  const canvas = page.getByTestId('spatial-canvas'); await expect(canvas).toBeVisible();
  await page.getByLabel('주파수', { exact: true }).fill('2000');
  await expect(page.getByLabel('파장', { exact: true })).toHaveValue('17.15');
  await page.getByLabel('파장', { exact: true }).fill('34.3');
  await expect(page.getByLabel('주파수', { exact: true })).toHaveValue('1000');
  const original = await page.getByTestId('source-coordinates').textContent();
  const roomBounds = (await canvas.boundingBox())!;
  await canvas.click({ position: { x: roomBounds.width * 0.5, y: roomBounds.height * 0.58 } });
  await expect(page.getByTestId('source-coordinates')).not.toHaveText(original!);
  const phone = page.getByTestId('phone-viewport'); const bounds = (await phone.boundingBox())!;
  const initialAzimuth = await page.locator('.phone-bottom').textContent();
  await page.mouse.move(bounds.x + 100, bounds.y + 160); await page.mouse.down(); await page.mouse.move(bounds.x + 160, bounds.y + 175, { steps: 8 }); await page.mouse.up();
  await expect(page.locator('.phone-bottom')).not.toHaveText(initialAzimuth!);
  await page.getByRole('button', { name: '마이크', exact: true }).click();
  await page.getByRole('button', { name: '마이크 1개', exact: true }).click(); await page.getByRole('button', { name: '마이크 추정', exact: true }).click();
  await expect(page.getByText('방향 정보 없음', { exact: true })).toBeVisible();
  await analysis();
  await expect(page.getByRole('button', { name: /관측 저장/ })).toBeDisabled();
  await settings();
  await page.getByRole('button', { name: '마이크 2개', exact: true }).click();
  await page.getByLabel('배열 방향').selectOption('vertical');
  await expect(page.getByLabel('배열 방향')).toHaveValue('vertical');
  await analysis();
  await page.getByRole('button', { name: /관측 저장/ }).click();
  await expect(page.getByRole('button', { name: /관측 저장/ })).toContainText('1/12');
  await settings(); await page.getByRole('button', { name: '공간·표시', exact: true }).click(); await page.getByLabel('음원 높이', { exact: true }).fill('1.5');
  await expect(page.locator('.dock-tabs').getByRole('button', { name: /관측/ })).toContainText('0');
  await page.getByRole('button', { name: '마이크', exact: true }).click(); await page.getByLabel('가상 장치 프리셋').selectOption('ipad');
  await expect(page.getByLabel('마이크 간격', { exact: true })).toHaveValue('20');
  await analysis();
  await page.getByRole('button', { name: /관측 저장/ }).click();
  await settings(); await page.getByRole('button', { name: '공간·표시', exact: true }).click(); await page.getByLabel('휴대폰 높이', { exact: true }).fill('2.5'); await analysis();
  await page.getByRole('button', { name: /관측 저장/ }).click();
  await page.getByText('좌표로 정밀 배치', { exact: true }).click();
  await page.getByLabel('휴대폰 X 좌표', { exact: true }).fill('-2');
  await page.getByRole('button', { name: /관측 저장/ }).click();
  await expect(page.getByTestId('estimate-result')).toBeVisible();
  const downloadPromise = page.waitForEvent('download'); await page.getByRole('button', { name: '실험 내보내기' }).click();
  const download = await downloadPromise; expect(download.suggestedFilename()).toContain(`soundfield-v${version}`);
  const exported = JSON.parse(readFileSync((await download.path())!, 'utf8'));
  expect(exported.appVersion).toBe(version); expect(exported.observations).toHaveLength(3); expect(exported.receiver.position[0]).toBe(-2);
  expect(exported.engineInput.channels[0]).toHaveLength(4096); expect(exported.engineInput).not.toHaveProperty('source');
  await page.getByRole('button', { name: '릴리즈 노트', exact: true }).click();
  await expect(page.getByRole('dialog')).toContainText(`v${version}`);
  await page.getByRole('button', { name: '닫기', exact: true }).click();
  await page.getByRole('button', { name: '초기화', exact: true }).click();
  await settings();
  await page.getByRole('button', { name: '음원', exact: true }).click();
  await expect(page.getByLabel('주파수', { exact: true })).toHaveValue('1000');
  await page.getByRole('button', { name: '마이크', exact: true }).click();
  await expect(page.getByRole('button', { name: '마이크 2개', exact: true })).toHaveClass('selected');
  expect(errors).toEqual([]);
  expect(await page.evaluate(() => document.documentElement.scrollHeight <= window.innerHeight)).toBe(true);
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({ path: 'test-results/desktop.png', fullPage: true });
});

test('compact controls preserve scene space on laptop and phone', async ({ page }) => {
  for (const viewport of [{ width: 1366, height: 768 }, { width: 390, height: 844 }]) {
    await page.setViewportSize(viewport); await page.goto('/');
    if (viewport.width < 760) {
      await page.getByRole('button', { name: '3D 공간', exact: true }).click();
      await page.getByRole('button', { name: '실험 설정', exact: true }).click();
    }
    for (const tab of ['음원', '마이크', '공간·표시']) {
      await page.getByRole('button', { name: tab, exact: true }).click();
      const panel = (await page.locator('.parameters').boundingBox())!;
      const scene = (await page.getByTestId('spatial-canvas').boundingBox())!;
      expect(panel.height).toBeLessThanOrEqual(viewport.width < 760 ? 180 : 115);
      expect(scene.height).toBeGreaterThan(360);
      expect(await page.locator('.parameters').evaluate(el => el.scrollHeight <= el.clientHeight && el.scrollWidth <= el.clientWidth)).toBe(true);
    }
    expect(await page.evaluate(() => document.documentElement.scrollHeight <= innerHeight && document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    await page.screenshot({ path: `test-results/compact-${viewport.width}.png` });
  }
});

test('has a functional heatmap and accessible guide on mobile', async ({ page }) => {
  const errors: string[] = []; page.on('pageerror', error => errors.push(error.message));
  await page.setViewportSize({ width: 390, height: 844 }); await page.goto('/');
  await expect(page.getByTestId('heatmap-canvas')).toBeVisible();
  await expect.poll(() => page.getByTestId('heatmap-canvas').evaluate(element => {
    const canvas = element as HTMLCanvasElement; const data = canvas.getContext('2d')!.getImageData(0, 0, canvas.width, canvas.height).data;
    return data.some((value, index) => index % 4 === 3 && value > 0);
  })).toBe(true);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  expect(await page.evaluate(() => document.documentElement.scrollHeight <= window.innerHeight)).toBe(true);
  await page.getByRole('button', { name: '열지도 ON' }).click();
  await expect.poll(() => page.getByTestId('heatmap-canvas').evaluate(element => {
    const canvas = element as HTMLCanvasElement; return canvas.getContext('2d')!.getImageData(0, 0, canvas.width, canvas.height).data.some(value => value > 0);
  })).toBe(false);
  await page.locator('.header-right').getByRole('button', { name: '사용 가이드', exact: true }).click();
  await expect(page.getByRole('dialog')).toBeVisible(); await page.keyboard.press('Escape'); await expect(page.getByRole('dialog')).toHaveCount(0);
  await page.getByRole('button', { name: '열지도 OFF' }).click();
  await page.getByRole('button', { name: '실험 설정', exact: true }).click();
  await expect(page.getByLabel('주파수', { exact: true })).toBeVisible();
  await expect(page.getByTestId('phone-viewport')).toBeVisible();
  await page.getByLabel('주파수', { exact: true }).fill('2500');
  await page.getByRole('button', { name: '마이크', exact: true }).click();
  await expect(page.getByLabel('배열 방향')).toBeVisible();
  await page.screenshot({ path: 'test-results/mobile-settings.png', fullPage: true });
  await page.getByRole('button', { name: '설정 패널 닫기', exact: true }).click();
  await page.getByRole('button', { name: '3D 공간', exact: true }).click(); await expect(page.getByTestId('spatial-canvas')).toBeVisible();
  await page.getByRole('button', { name: '사운드 스캔', exact: true }).click();
  await expect.poll(() => page.getByTestId('heatmap-canvas').evaluate(element => {
    const canvas = element as HTMLCanvasElement; return canvas.getContext('2d')!.getImageData(0, 0, canvas.width, canvas.height).data.some(value => value > 0);
  })).toBe(true);
  expect(errors).toEqual([]);
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({ path: 'test-results/mobile.png', fullPage: true });
});
