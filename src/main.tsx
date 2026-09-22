import React, { lazy, Suspense } from 'react';
import ReactDOM from 'react-dom/client';
import './styles.css';
import './layout.css';

const Page = location.pathname.replace(/\/$/, '') === '/diagnostics' ? lazy(() => import('./live/LiveDiagnostics')) : lazy(() => import('./App'));
ReactDOM.createRoot(document.getElementById('root')!).render(<React.StrictMode><Suspense fallback={<p role="status">SoundField 불러오는 중…</p>}><Page /></Suspense></React.StrictMode>);
