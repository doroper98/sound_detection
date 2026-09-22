import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { readFileSync } from 'node:fs';

const { version } = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf8'));
export default defineConfig({
  plugins: [react(), { name: 'release-version', generateBundle() { this.emitFile({ type: 'asset', fileName: 'version.json', source: JSON.stringify({ version }) }); } }],
  define: { __APP_VERSION__: JSON.stringify(version) },
  build: { rollupOptions: { output: { manualChunks: (id: string) => id.includes('/three/') ? 'three' : undefined } } },
});
