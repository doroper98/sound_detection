import { useEffect, useRef, useState } from 'react';
import { ArrowDownToLine, ArrowLeft, Camera, Check, Copy, Mic, Square } from 'lucide-react';
import { probeVerdict, requestLabel, type FrameStats, type ProbeAttempt } from './analysis';
import { errorExplanation, mediaError, probeMicrophones, requestMedia, stopStream } from './probe';
import './live.css';
import LiveSpectrum from './LiveSpectrum';

export default function LiveDiagnostics() {
  const listening = location.pathname.replace(/\/$/, '') === '/listen';
  const [monitorRunning, setMonitorRunning] = useState(false);
  const video = useRef<HTMLVideoElement>(null);
  const cameraStream = useRef<MediaStream | null>(null);
  const cameraController = useRef<AbortController | null>(null);
  const micController = useRef<AbortController | null>(null);
  const [cameraState, setCameraState] = useState<'off' | 'waiting' | 'on'>('off');
  const [cameraError, setCameraError] = useState('');
  const [cameraSettings, setCameraSettings] = useState<{ width?: number; height?: number; frameRate?: number; facingMode?: string } | null>(null);
  const [running, setRunning] = useState(false);
  const [status, setStatus] = useState('카메라를 켠 뒤 4채널 검사를 시작하세요. 마이크만 검사해도 됩니다.');
  const [attempts, setAttempts] = useState<ProbeAttempt[]>([]);
  const [levels, setLevels] = useState<FrameStats | null>(null);
  const [finished, setFinished] = useState(false);
  const [startedAt, setStartedAt] = useState<string | null>(null);
  const [cameraDuringProbe, setCameraDuringProbe] = useState(false);
  const [declaredDevice, setDeclaredDevice] = useState('iPhone 17 Pro');
  const [declaredOs, setDeclaredOs] = useState('');
  const [copied, setCopied] = useState(false);
  const [shareError, setShareError] = useState('');
  const verdict = probeVerdict(attempts);

  const stopCamera = () => {
    cameraController.current?.abort(); cameraController.current = null;
    stopStream(cameraStream.current); cameraStream.current = null;
    if (video.current) video.current.srcObject = null;
    setCameraState('off');
  };
  const stopMicrophone = () => {
    if (!micController.current) return;
    micController.current?.abort(); micController.current = null;
    setRunning(false); setLevels(null); setFinished(false); setStatus('검사를 중지했습니다. 완료된 요청의 기록은 남아 있습니다.');
  };
  useEffect(() => {
    const onHidden = () => { if (document.hidden) { stopCamera(); stopMicrophone(); } };
    const onPageHide = () => { stopCamera(); stopMicrophone(); };
    document.addEventListener('visibilitychange', onHidden); window.addEventListener('pagehide', onPageHide);
    return () => {
      document.removeEventListener('visibilitychange', onHidden); window.removeEventListener('pagehide', onPageHide);
      cameraController.current?.abort(); micController.current?.abort(); stopStream(cameraStream.current);
    };
  }, []);

  const startCamera = async () => {
    stopCamera(); setCameraError(''); setCameraSettings(null);
    const controller = new AbortController(); cameraController.current = controller; setCameraState('waiting');
    try {
      if (!navigator.mediaDevices?.getUserMedia) throw new DOMException('Unavailable', 'NotSupportedError');
      const stream = await requestMedia({ audio: false, video: { facingMode: { ideal: 'environment' }, width: { ideal: 1280 }, height: { ideal: 720 } } }, controller.signal);
      if (controller.signal.aborted) { stopStream(stream); return; }
      cameraStream.current = stream;
      const { width, height, frameRate, facingMode } = stream.getVideoTracks()[0].getSettings();
      setCameraSettings({ width, height, frameRate, facingMode });
      video.current!.srcObject = stream;
      await video.current!.play();
      if (!controller.signal.aborted) setCameraState('on');
    } catch (error) {
      if (!controller.signal.aborted) { stopCamera(); setCameraError(errorExplanation(mediaError(error).name)); }
    }
  };

  const startProbe = async () => {
    micController.current?.abort();
    const controller = new AbortController(); micController.current = controller;
    setAttempts([]); setLevels(null); setFinished(false); setRunning(true); setCopied(false); setShareError('');
    setStartedAt(new Date().toISOString()); setCameraDuringProbe(cameraState === 'on');
    try {
      const measured = await probeMicrophones({
        signal: controller.signal,
        onProgress: value => { if (!controller.signal.aborted) setStatus(value); },
        onAttempt: value => { if (!controller.signal.aborted) setAttempts(previous => [...previous, value]); },
        onLevel: value => { if (!controller.signal.aborted) setLevels(value); },
      });
      if (!controller.signal.aborted) {
        const failed = measured.find(a => a.status === 'error');
        setFinished(true); setStatus(failed?.error ? `${errorExplanation(failed.error.name)} 마이크를 해제했습니다.` : '검사가 끝나 마이크를 해제했습니다. 결과를 복사해 공유할 수 있습니다.');
      }
    } catch (error) {
      if (!controller.signal.aborted) setStatus(errorExplanation(mediaError(error).name));
    } finally {
      if (micController.current === controller) { micController.current = null; setRunning(false); setLevels(null); }
    }
  };

  const report = () => ({
    schemaVersion: 1, appVersion: __APP_VERSION__, startedAt, exportedAt: new Date().toISOString(),
    declaredDevice, declaredOs, userAgent: navigator.userAgent, secureContext: window.isSecureContext,
    status, environment: { getUserMedia: !!navigator.mediaDevices?.getUserMedia, audioContext: !!globalThis.AudioContext, audioWorkletNode: typeof AudioWorkletNode !== 'undefined' },
    supportedConstraints: navigator.mediaDevices?.getSupportedConstraints?.() ?? {},
    cameraActiveAtProbeStart: cameraDuringProbe, cameraSettings, completed: finished, attempts,
    audioRoute: 'getUserMedia → MediaStreamAudioSourceNode → AudioWorklet',
    verdict: verdict.title,
    physicalMicrophonesVerified: false, hardwareSynchronizationVerified: false, localizationEnabled: false,
    note: 'Browser PCM channel count is not physical microphone count. No camera frames, voice samples, device IDs, or group IDs are included. No source coordinates are used.',
  });
  const reportText = () => JSON.stringify(report(), null, 2);
  const copyReport = async () => {
    try { await navigator.clipboard.writeText(reportText()); setCopied(true); setShareError(''); }
    catch { setShareError('복사 권한이 없습니다. JSON 저장을 사용해 주세요.'); }
  };
  const downloadReport = () => {
    const url = URL.createObjectURL(new Blob([reportText()], { type: 'application/json' }));
    const a = document.createElement('a'); a.href = url; a.download = `soundfield-mic-diagnostic-v${__APP_VERSION__}.json`; a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  };
  const meter = levels ?? attempts.at(-1)?.latest;

  return <div className={`live-page${listening ? ' live-listening' : ''}`}>
    <header className="live-header"><a href="/" aria-label="시뮬레이터로 돌아가기"><ArrowLeft size={17} /><span>soundfield</span></a><span className="live-version">실제 수음 · v{__APP_VERSION__}</span></header>
    <div className="live-title"><div><span className="eyebrow">{listening ? 'LIVE SOUND' : 'DEVICE CHECK'}</span><h1>{listening ? '주변 소리의 주파수와 음량' : '내 아이폰은 몇 채널을 들을까?'}</h1><p>카메라와 실제 수음 확인 · 음원 위치 추정은 아직 미검증입니다.</p></div><span className="live-target">iPhone 17 Pro · Safari</span></div>
    <nav className="live-mode-nav" aria-label="실제 수음 모드"><a href="/listen" aria-current={listening ? 'page' : undefined}>실시간 분석</a><a href="/diagnostics" aria-current={!listening ? 'page' : undefined}>채널 검사</a></nav>
    <div className="live-grid">
      <section className="live-preview" aria-label="실제 카메라 미리보기">
        <video ref={video} autoPlay playsInline muted data-testid="live-video" />
        {cameraState !== 'on' && <div className="camera-placeholder"><Camera size={34} /><strong>{cameraState === 'waiting' ? '카메라 권한을 기다립니다' : '실제 카메라 영상'}</strong><p>후면 카메라로 주변을 비추며<br />마이크의 입력을 검사할 수 있습니다.</p></div>}
        <div className="live-preview-top"><span className={cameraState === 'on' ? 'capture-on' : ''}>{cameraState === 'on' ? 'CAMERA ON' : 'CAMERA OFF'}</span><span>위치 열지도 없음</span></div>
        <div className="live-meter"><span>{running || monitorRunning ? '실시간 PCM · 가장 큰 채널' : '마이크 대기'}</span><strong>{levels && levels.channels.some(c => c.levelDbfs !== null) ? Math.max(...levels.channels.map(c => c.levelDbfs ?? -Infinity)).toFixed(1) : '—'}<small>dBFS</small></strong><p>디지털 음량 · 실제 dB SPL 교정 전</p></div>
        {cameraError && <p className="camera-error" role="alert">{cameraError}</p>}
        <div className="live-camera-controls"><button className="button secondary" disabled={(running || monitorRunning) && cameraState === 'off'} onClick={cameraState === 'off' ? () => void startCamera() : stopCamera}>{cameraState === 'off' ? <Camera size={16} /> : <Square size={15} />}{cameraState === 'off' ? '카메라 시작' : '카메라 중지'}</button></div>
      </section>
      <section className="live-diagnostics" aria-label={listening ? '실시간 소리 분석' : '마이크 채널 진단'}>
        {listening ? <LiveSpectrum cameraWaiting={cameraState === 'waiting'} onLevel={setLevels} onRunning={setMonitorRunning} /> : <>
        <div className="live-diag-intro"><h2>4개 마이크, 웹에서도 쓸 수 있을까요?</h2><p>4채널 필수 → 2채널 필수 → 기본 입력 순서로 요청하고 실제 PCM을 확인합니다. 검사를 시작한 뒤 손뼉이나 목소리로 소리를 내 주세요.</p><p className="live-route-hint">내장 마이크 검사 시 AirPods·외장 오디오 연결을 해제하세요. 기종명은 직접 입력한 기록이며 자동 판별값이 아닙니다.</p></div>
        <div className="live-device-fields"><label>검사 기종<input value={declaredDevice} onChange={e => setDeclaredDevice(e.target.value)} placeholder="iPhone 17 Pro" /></label><label>iOS / OS 버전<input value={declaredOs} onChange={e => setDeclaredOs(e.target.value)} placeholder="설정 → 일반 → 정보" /></label></div>
        <div className="live-probe-actions"><button className="button primary" disabled={running || cameraState === 'waiting'} onClick={() => void startProbe()}><Mic size={16} />{running ? '검사 중…' : '4채널 검사 시작'}</button>{running && <button className="button secondary" onClick={stopMicrophone}><Square size={15} />검사 중지</button>}</div>
        <p className="live-status" role="status">{status}</p>
        <div className="probe-table-wrap"><table className="probe-table"><thead><tr><th>요청</th><th>브라우저 설정</th><th>Web Audio PCM</th></tr></thead><tbody>{attempts.length ? attempts.map(attempt => <tr key={attempt.requested}><th>{attempt.requested === 'default' ? '기본' : `${attempt.requested}채널 필수`}</th><td>{attempt.settings?.channelCount !== undefined ? `${attempt.settings.channelCount}채널` : '미보고'}{attempt.status === 'rejected' && <small>요청 거절</small>}</td><td>{attempt.observedChannelCounts.length ? `${attempt.observedChannelCounts.join(' / ')}채널` : '미수신'}<small>{attempt.frameCount ? `${attempt.frameCount}프레임 · ${attempt.pcmSampleRate} Hz` : attempt.error?.name ?? ''}</small></td></tr>) : <tr><td colSpan={3}>검사 전 · 아직 실제 수음 결과가 없습니다.</td></tr>}</tbody></table></div>
        <p className="live-route-note">PCM은 이 웹앱에 전달된 신호입니다. 브라우저가 중간에 채널을 혼합·복제할 수 있어 물리 마이크 수와 다를 수 있습니다.</p>
        {attempts.length > 0 && <div className="probe-verdict" data-testid="probe-verdict"><span>{finished ? '검사 결과' : '진행 기록 · 최종 결과 아님'}</span><h3>{verdict.title}</h3><p>{verdict.detail}</p><strong>물리 마이크 독립성 / 시간 동기화: 미검증</strong></div>}
        {meter && <div className="channel-meters" aria-label="채널별 수신 음량">{meter.channels.map((channel, index) => <div key={index}><span>CH {index + 1}</span><meter min={-100} max={0} value={channel.levelDbfs ?? -100} /><strong>{channel.levelDbfs === null ? '무음' : `${channel.levelDbfs.toFixed(1)} dBFS`}</strong></div>)}</div>}
        <details className="probe-details"><summary>세부 설정·검사 방법</summary><p>4채널이 보여도 4개 물리 마이크의 독립 원음이라는 뜻은 아닙니다. 같은 파형은 복제를 의심할 근거이고, 다른 파형도 독립성을 증명하지 않습니다. 기기별 센서 위치·지연·영상 정렬을 실측해야 방향 추정을 연결할 수 있습니다.</p><p>현재 시뮬레이터는 합성 신호와 알려진 센서 위치를 사용합니다. ‘정답 비교’는 지정한 위치를 직접 표시하므로 실제 아이폰 정확도의 근거가 아닙니다.</p>{attempts.map(attempt => <div key={attempt.requested}><h4>{requestLabel(attempt.requested)}</h4><p>{attempt.error ? `${attempt.error.name}${attempt.error.constraint ? ` (${attempt.error.constraint})` : ''} · ${errorExplanation(attempt.error.name)}` : `수신 ${attempt.sampleCount} samples`}</p><pre>{JSON.stringify({ settings: attempt.settings, capabilities: attempt.capabilities, pairs: attempt.latest?.pairs }, null, 2)}</pre></div>)}<a href="https://github.com/doroper98/sound_detection/blob/main/docs_canonical/LIVE_CAMERA_PLAN.md" target="_blank" rel="noreferrer">실기기 검증 계획 보기</a></details>
        <div className="live-export"><button className="button secondary" disabled={!startedAt || running} onClick={() => void copyReport()}>{copied ? <Check size={15} /> : <Copy size={15} />}{copied ? '결과 복사됨' : '결과 복사'}</button><button className="button secondary" disabled={!startedAt || running} onClick={downloadReport}><ArrowDownToLine size={15} />JSON 저장</button></div>
        {shareError && <p role="alert">{shareError}</p>}
        <p className="live-privacy">영상·음성은 이 기기에서만 처리합니다. 결과에는 채널 통계와 브라우저 정보만 포함하며 원음·영상·장치 ID를 저장하거나 서버로 보내지 않습니다. 백그라운드로 이동하면 캡처를 중지합니다.</p>
        </>}
      </section>
    </div>
  </div>;
}
