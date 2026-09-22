import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e', timeout: 120000, fullyParallel: false, workers: 1,
  use: { baseURL: process.env.PLAYWRIGHT_BASE_URL || 'http://127.0.0.1:5173', browserName: 'chromium', viewport: { width: 1440, height: 1100 }, launchOptions: { args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] }, screenshot: 'only-on-failure', trace: 'retain-on-failure' },
  webServer: process.env.PLAYWRIGHT_BASE_URL ? undefined : { command: 'npm run dev -- --port 5173', url: 'http://127.0.0.1:5173', reuseExistingServer: !process.env.CI },
});
