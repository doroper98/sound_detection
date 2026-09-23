import { useEffect, useRef, useState } from 'react';
import { ArrowDownToLine, Mic, Square } from 'lucide-react';
import { analyzeChannels, type CaptureSettings, type FrameStats } from './analysis';
import { errorExplanation, mediaError } from './probe';
import { monitorMicrophone } from './monitor';
import { analyzeSpectrum, type Spectrum } from './spectrum';

const BANDS = [
  { label: '전체 · 20 Hz 이상', minHz: 20, maxHz: 96000 },
  { label: '저역 · 20–500 Hz', minHz: 20, maxHz: 500 },
  { label: '중역 · 500–2,000 Hz', minHz: 500, maxHz: 2000 },
  { label: '고역 · 2,000–8,000 Hz', minHz: 2000, maxHz: 8000 },
] as const;
type Snapshot = { spectrum: Spectrum; stats: FrameStats; selectedChannel: number; capturedAt: string; frameCount: number; sampleCount: number };
const level = (value: number | null | undefined) => value == null ? '—' : value.toFixed(1);

function SpectrumPlot({ spectrum }: { spectrum: Spectrum | undefined }) {
  const upper = spectrum ? spectrum.sampleRate / 2 : 24000;
  const x = (hz: number) => 36 + Math.log(Math.max(20, hz) / 20) / Math.log(upper / 20) * 300;
  const y = (db: number | null) => 16 + (1 - Math.max(0, Math.min(1, ((db ?? -100) + 100) / 100))) * 124;
  const bars = Array.from({ length: 100 }, (_, i) => {
    const lo = 20 * (upper / 20) ** (i / 100); const hi = 20 * (upper / 20) ** ((i + 1) / 100);
    let power: number | null = null;
    if (spectrum) for (let k = Math.max(1, Math.ceil(lo / spectrum.binWidthHz)); k < spectrum.binsDbfs.length && k * spectrum.binWidthHz < hi; k++) {
      const value = spectrum.binsDbfs[k]; if (value !== null && (power === null || value > power)) power = value;
    }
    return <rect key={i} x={x(lo)} y={y(power)} width={2.3} height={140 - y(power)} rx={.6} fill="#48b886" />;
  });
  return <figure className="spectrum-plot"><svg viewBox="0 0 354 169" role="img" aria-label="주파수별 디지털 레벨 스펙트럼" data-testid="spectrum-plot">
    <rect x="36" y="16" width="300" height="124" rx="3" fill="#102e25" />
    {spectrum && <rect x={x(spectrum.band.minHz)} y="16" width={Math.max(0, x(spectrum.band.maxHz) - x(spectrum.band.minHz))} height="124" fill="#7abb8a" opacity=".14" />}
    {[0, -50, -100].map(db => <g key={db}><line x1="36" x2="336" y1={y(db)} y2={y(db)} stroke="#48705b" strokeWidth=".5" /><text x="30" y={y(db) + 3} textAnchor="end">{db}</text></g>)}
    {bars}
    {[20, 100, 1000, 10000].filter(hz => hz <= upper).map(hz => <text key={hz} x={x(hz)} y="158" textAnchor="middle">{hz >= 1000 ? `${hz / 1000}k` : hz}</text>)}
    <text x="341" y="158">Hz</text>
  </svg><figcaption>고정 −100~0 dBFS/bin · 밝은 영역은 선택 대역</figcaption></figure>;
}

export default function LiveSpectrum({ cameraWaiting, onLevel, onRunning }: {
  cameraWaiting: boolean; onLevel: (stats: FrameStats | null) => void; onRunning: (running: boolean) => void;
}) {
  const controller = useRef<AbortController | null>(null);
  const config = useRef({ channel: 0, band: 0 });
  const [running, setRunning] = useState(false);
  const [status, setStatus] = useState('분석 시작을 누르면 실제 마이크로 주변 소리를 분석합니다.');
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null);
  const [settings, setSettings] = useState<CaptureSettings | null>(null);
  const [channel, setChannel] = useState(0);
  const [band, setBand] = useState(0);
  const [startedAt, setStartedAt] = useState<string | null>(null);
  const stop = () => {
    controller.current?.abort(); controller.current = null;
    setRunning(false); onRunning(false); onLevel(null);
    setStatus('분석을 중지하고 마이크를 해제했습니다. 마지막 측정값을 표시합니다.');
  };
  useEffect(() => {
    const hidden = () => { if (document.hidden && controller.current) stop(); };
    const pageHide = () => { if (controller.current) stop(); };
    document.addEventListener('visibilitychange', hidden); window.addEventListener('pagehide', pageHide);
    return () => { controller.current?.abort(); document.removeEventListener('visibilitychange', hidden); window.removeEventListener('pagehide', pageHide); };
  }, []);
  const start = async () => {
    controller.current?.abort(); const current = new AbortController(); controller.current = current;
    setRunning(true); onRunning(true); setSnapshot(null); setSettings(null); onLevel(null);
    setStartedAt(new Date().toISOString()); setStatus('마이크 권한을 기다립니다. 주변에서 소리를 내 주세요.');
    let frames = 0; let samples = 0;
    try {
      await monitorMicrophone({
        signal: current.signal,
        onSettings: value => { if (!current.signal.aborted) { setSettings(value); setStatus('입력을 연결했습니다. 소리 샘플을 기다립니다.'); } },
        onFrame: frame => {
          if (current.signal.aborted) return;
          const stats = analyzeChannels(frame.channels);
          const selectedChannel = Math.min(config.current.channel, frame.channels.length - 1);
          const spectrum = analyzeSpectrum(frame.channels[selectedChannel], frame.sampleRate, BANDS[config.current.band]);
          frames++; samples += frame.channels[0].length;
          if (selectedChannel !== config.current.channel) { config.current.channel = selectedChannel; setChannel(selectedChannel); }
          setSnapshot({ spectrum, stats, selectedChannel: selectedChannel + 1, capturedAt: new Date().toISOString(), frameCount: frames, sampleCount: samples });
          onLevel(stats); setStatus('실시간 분석 중 · 다른 앱으로 이동하면 수음을 중지합니다.');
        },
      });
    } catch (error) {
      if (!current.signal.aborted) setStatus(`${errorExplanation(mediaError(error).name)} 마이크를 해제했습니다.`);
    } finally {
      if (controller.current === current) { controller.current = null; setRunning(false); onRunning(false); onLevel(null); }
    }
  };
  const download = () => {
    if (!snapshot) return;
    const { spectrum, ...summary } = snapshot;
    const { binsDbfs: _bins, ...spectrumSummary } = spectrum;
    const report = {
      schemaVersion: 1, reportType: 'live-spectrum', appVersion: __APP_VERSION__, startedAt,
      exportedAt: new Date().toISOString(), userAgent: navigator.userAgent, settings,
      ...summary, spectrum: spectrumSummary,
      physicalMicrophonesVerified: false, hardwareSynchronizationVerified: false, localizationEnabled: false,
      note: 'Digital RMS dBFS; not calibrated SPL. Frequency is not source identity or direction. No raw audio, video, device IDs, or group IDs.',
    };
    const url = URL.createObjectURL(new Blob([JSON.stringify(report, null, 2)], { type: 'application/json' }));
    const a = document.createElement('a'); a.href = url; a.download = `soundfield-spectrum-${Date.now()}.json`; a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  };
  const spectrum = snapshot?.spectrum;
  const active = snapshot?.stats.channels.filter(c => c.active).length ?? 0;
  return <>
    <div className="live-diag-intro"><h2>지금 들리는 소리 분석</h2><p>카메라는 먼저 켜고, 분석 시작을 누르세요.</p></div>
    <div className="live-probe-actions spectrum-actions"><button className="button primary" disabled={running || cameraWaiting} onClick={() => void start()}><Mic size={16} />{running ? '분석 중…' : '분석 시작'}</button>{running && <button className="button secondary" onClick={stop}><Square size={15} />분석 중지</button>}</div>
    <p className="live-status" role="status">{status}</p>
    <div className="spectrum-selects"><label>입력 채널<select aria-label="분석 채널" value={channel} disabled={!running || !snapshot} onChange={e => { const value = Number(e.target.value); config.current.channel = value; setChannel(value); }}>{(snapshot?.stats.channels ?? [null]).map((c, i) => <option value={i} key={i}>CH {i + 1}{c && !c.active ? ' · 신호 미확인' : ''}</option>)}</select></label><label>주파수 대역<select aria-label="분석 대역" value={band} onChange={e => { const value = Number(e.target.value); config.current.band = value; setBand(value); if (!running) setSnapshot(null); }}>{BANDS.map((b, i) => <option value={i} key={i}>{b.label}</option>)}</select></label></div>
    <SpectrumPlot spectrum={spectrum} />
    <div className="spectrum-metrics" aria-label="실제 주파수 분석 결과">
      <div><span>선택 채널 전체</span><strong data-testid="spectrum-total">{level(spectrum?.totalDbfs)}</strong><small>dBFS RMS</small></div>
      <div><span>선택 대역 음량</span><strong data-testid="spectrum-band">{level(spectrum?.bandDbfs)}</strong><small>dBFS RMS</small></div>
      <div><span>대역 내 최대 성분</span><strong data-testid="spectrum-peak">{spectrum?.peakHz == null ? '—' : Math.round(spectrum.peakHz).toLocaleString()}</strong><small>Hz</small></div>
    </div>
    <p className="live-route-note">{snapshot ? `CH ${snapshot.selectedChannel} · PCM ${snapshot.stats.channels.length}채널 / 신호 ${active}채널 · ${spectrum!.sampleRate.toLocaleString()} Hz · 주파수 간격 ${spectrum!.binWidthHz.toFixed(1)} Hz · ${snapshot.frameCount}프레임` : '측정 전 · 실제 마이크 입력을 기다립니다.'}</p>
    {snapshot && <p className="live-route-note">측정 대역 {spectrum!.band.minHz.toLocaleString()}–{spectrum!.band.maxHz.toLocaleString()} Hz · {running ? '갱신 중' : '중지된 마지막 측정'}</p>}
    {!!spectrum?.clippedSamples && <p className="spectrum-warning" role="alert">입력이 포화됐습니다. 소리에서 거리를 두고 다시 측정하세요.</p>}
    {snapshot && <div className="channel-meters" aria-label="채널별 수신 음량">{snapshot.stats.channels.map((c, i) => <div key={i}><span>CH {i + 1}</span><meter min={-100} max={0} value={c.levelDbfs ?? -100} /><strong>{c.levelDbfs === null ? '무음' : `${c.levelDbfs.toFixed(1)} dBFS`}</strong></div>)}</div>}
    <div className="probe-verdict"><h3>위치·거리: 측정하지 않음</h3><p>{snapshot && active < 2 ? '현재 신호가 있는 입력은 1채널 이하입니다. ' : ''}주파수는 소리의 성분이며 방향이나 음원 종류를 뜻하지 않습니다. 레벨은 보정된 소음계 dB SPL이 아닙니다.</p></div>
    <button className="button secondary" disabled={!snapshot} onClick={download}><ArrowDownToLine size={15} />분석 JSON 저장</button>
    <details className="probe-details"><summary>수음 설정</summary><p>반향 제거·잡음 억제·자동 이득 해제를 요청합니다. 아래는 브라우저가 보고한 실제 설정이며, 누락 항목은 미보고입니다.</p><pre>{JSON.stringify(settings ?? {}, null, 2)}</pre><p>4096개 샘플에 Hann 창과 FFT를 적용합니다. 시간파형 RMS와 창 보정 대역 RMS는 신호 변화에 따라 다를 수 있습니다. 무음 또는 매우 작은 신호에서는 최대 성분을 표시하지 않습니다.</p></details>
    <p className="live-privacy">소리는 이 기기에서만 처리하고 재생하지 않습니다. JSON에는 마지막 측정 통계만 저장하며 원음·영상·장치 ID를 포함하지 않습니다.</p>
  </>;
}
