import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';

const version = JSON.parse(readFileSync('package.json', 'utf8')).version;

test('places a source, links acoustics, rotates the phone, changes microphone modes and exports', async ({ page }) => {
  const errors: string[] = []; page.on('pageerror', error => errors.push(error.message));
  await page.goto('/'); await expect(page.getByRole('heading', { name: '소리가 나는 곳을, 눈으로.' })).toBeVisible();
  const canvas = page.getByTestId('spatial-canvas'); await expect(canvas).toBeVisible();
  await page.getByLabel('주파수', { exact: true }).fill('2000');
  await expect(page.getByLabel('파장', { exact: true })).toHaveValue('17.15');
  await page.getByLabel('파장', { exact: true }).fill('34.3');
  await expect(page.getByLabel('주파수', { exact: true })).toHaveValue('1000');
  const original = await page.getByTestId('source-coordinates').textContent();
  await canvas.click({ position: { x: 360, y: 255 } });
  await expect(page.getByTestId('source-coordinates')).not.toHaveText(original!);
  const phone = page.getByTestId('phone-viewport'); const bounds = (await phone.boundingBox())!;
  const initialAzimuth = await page.locator('.phone-bottom').textContent();
  await page.mouse.move(bounds.x + 100, bounds.y + 160); await page.mouse.down(); await page.mouse.move(bounds.x + 160, bounds.y + 175, { steps: 8 }); await page.mouse.up();
  await expect(page.locator('.phone-bottom')).not.toHaveText(initialAzimuth!);
  await page.getByRole('button', { name: '마이크 1개', exact: true }).click(); await page.getByRole('button', { name: '마이크 추정', exact: true }).click();
  await expect(page.getByText('방향 정보 없음', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: /관측 저장/ })).toBeDisabled();
  await page.getByRole('button', { name: '마이크 2개', exact: true }).click();
  await page.getByRole('button', { name: /관측 저장/ }).click();
  await expect(page.getByRole('button', { name: /관측 저장/ })).toContainText('1/12');
  await page.getByLabel('음원 높이', { exact: true }).fill('1.5');
  await expect(page.getByRole('button', { name: /관측 저장/ })).toContainText('0/12');
  await page.getByLabel('가상 장치 프리셋').selectOption('ipad');
  await expect(page.getByLabel('마이크 간격', { exact: true })).toHaveValue('20');
  await page.getByRole('button', { name: /관측 저장/ }).click();
  await page.getByLabel('휴대폰 높이', { exact: true }).fill('2.5');
  await page.getByRole('button', { name: /관측 저장/ }).click();
  await page.getByText('좌표로 정밀 배치', { exact: true }).click();
  await page.getByLabel('휴대폰 X 좌표', { exact: true }).fill('-2');
  await page.getByRole('button', { name: /관측 저장/ }).click();
  await expect(page.getByTestId('estimate-result')).toBeVisible();
  const downloadPromise = page.waitForEvent('download'); await page.getByRole('button', { name: '실험 내보내기' }).click();
  const download = await downloadPromise; expect(download.suggestedFilename()).toContain(`soundfield-v${version}`);
  const exported = JSON.parse(readFileSync((await download.path())!, 'utf8'));
  expect(exported.appVersion).toBe(version); expect(exported.observations).toHaveLength(3); expect(exported.receiver.position[0]).toBe(-2);
  await page.getByRole('button', { name: '릴리즈 노트', exact: true }).click();
  await expect(page.getByRole('dialog')).toContainText(`v${version}`);
  await page.getByRole('button', { name: '닫기', exact: true }).click();
  await page.getByRole('button', { name: '초기화', exact: true }).click();
  await expect(page.getByLabel('주파수', { exact: true })).toHaveValue('1000');
  await expect(page.getByRole('button', { name: '마이크 2개', exact: true })).toHaveClass('selected');
  expect(errors).toEqual([]);
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({ path: 'test-results/desktop.png', fullPage: true });
});

test('has a functional heatmap and accessible guide on mobile', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 }); await page.goto('/');
  await expect(page.getByTestId('heatmap-canvas')).toBeVisible();
  await expect.poll(() => page.getByTestId('heatmap-canvas').evaluate(element => {
    const canvas = element as HTMLCanvasElement; const data = canvas.getContext('2d')!.getImageData(0, 0, canvas.width, canvas.height).data;
    return data.some((value, index) => index % 4 === 3 && value > 0);
  })).toBe(true);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await page.getByRole('button', { name: '열지도 ON' }).click();
  await expect.poll(() => page.getByTestId('heatmap-canvas').evaluate(element => {
    const canvas = element as HTMLCanvasElement; return canvas.getContext('2d')!.getImageData(0, 0, canvas.width, canvas.height).data.some(value => value > 0);
  })).toBe(false);
  await page.getByRole('button', { name: '사용 가이드', exact: true }).first().click();
  await expect(page.getByRole('dialog')).toBeVisible(); await page.keyboard.press('Escape'); await expect(page.getByRole('dialog')).toHaveCount(0);
  await page.getByRole('button', { name: '열지도 OFF' }).click();
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({ path: 'test-results/mobile.png', fullPage: true });
});
