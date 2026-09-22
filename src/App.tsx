import { useMemo, useRef, useState, type ReactNode } from 'react';
import { Activity, ArrowDownToLine, ArrowUpRight, AudioLines, BookOpen, Box, Check, ChevronDown, CircleHelp, Crosshair, Focus, GitFork, History, Layers3, Maximize, Mic, MousePointer2, Move3D, Pause, Play, Plus, Radio, RotateCcw, ScanLine, Settings2, Signal, Smartphone, Volume2, VolumeX, Waves, X } from 'lucide-react';
import SpatialView from './components/SpatialView';
import PhoneView from './components/PhoneView';
import { clamp, DEVICES, distance, estimate, INITIAL_RECEIVER, INITIAL_SOURCE, isDistinctObservation, pressureAt, SEARCH_VOLUME, wavelength, type Observation, type Receiver, type Source, type Vec3 } from './acoustics';
import { useAudio } from './useAudio';
import { captureSimulation, simulateFrame } from './simulation';
import { HEAT_CEILING_DBFS, HEAT_FLOOR_DBFS, pcmStats } from './heatmap';

const releaseFiles = import.meta.glob('../docs/releases/*.md', { query: '?raw', import: 'default', eager: true });
const releaseNotes = String(releaseFiles[`../docs/releases/v${__APP_VERSION__}.md`] ?? '이 버전의 릴리즈 노트가 없습니다.');

function Control({ label, value, min, max, step = 1, unit, onChange, digits = 0 }: { label: string; value: number; min: number; max: number; step?: number; unit: string; onChange: (value: number) => void; digits?: number }) {
  return <div className="control">
    <div className="control-label"><label>{label}</label><div className="number-unit"><input aria-label={label} type="number" min={min} max={max} step={step} value={Number(value.toFixed(digits))} onChange={event => { if (event.target.value !== '' && Number.isFinite(event.target.valueAsNumber)) onChange(clamp(event.target.valueAsNumber, min, max)); }} /><span>{unit}</span></div></div>
    <input aria-label={`${label} 슬라이더`} type="range" min={min} max={max} step={step} value={value} onChange={event => onChange(Number(event.target.value))} style={{ '--range': `${(value - min) / (max - min) * 100}%` } as React.CSSProperties} />
  </div>;
}

function Modal({ children, title, onClose }: { children: ReactNode; title: string; onClose: () => void }) {
  const ref = useRef<HTMLDialogElement>(null);
  return <dialog ref={element => { ref.current = element; if (element && !element.open) element.showModal(); }} onCancel={onClose} onClick={event => { if (event.target === ref.current) onClose(); }}>
    <div className="modal-header"><h2>{title}</h2><button className="icon-button" aria-label="닫기" onClick={onClose}><X size={20} /></button></div>
    <div className="modal-body">{children}</div>
  </dialog>;
}

export default function App() {
  const [source, setSource] = useState<Source>(INITIAL_SOURCE);
  const [receiver, setReceiver] = useState<Receiver>(INITIAL_RECEIVER);
  const [device, setDevice] = useState('iphone');
  const [mode, setMode] = useState<'pressure' | 'estimate'>('estimate');
  const [placement, setPlacement] = useState<'source' | 'receiver' | 'orbit'>('source');
  const [playing, setPlaying] = useState(true);
  const [heatmap, setHeatmap] = useState(true);
  const [opacity, setOpacity] = useState(0.68);
  const [observations, setObservations] = useState<Observation[]>([]);
  const [resetKey, setResetKey] = useState(0);
  const [modal, setModal] = useState<'guide' | 'releases' | null>(null);
  const [toast, setToast] = useState('');
  const [controlTab, setControlTab] = useState<'settings' | 'analysis'>('settings');
  const [mobileView, setMobileView] = useState<'space' | 'scanner'>('scanner');
  const [mobileSheet, setMobileSheet] = useState(false);
  const [settingsTab, setSettingsTab] = useState<'source' | 'device' | 'view'>('source');
  const toastTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const audio = useAudio(source, playing);
  const capture = useMemo(() => receiver.count === 2 ? captureSimulation(source, receiver) : null, [source, receiver]);
  const frame = useMemo(() => capture?.frame ?? simulateFrame(source, receiver), [capture, source, receiver]);
  const levels = useMemo(() => pcmStats(frame.channels), [frame]);
  const currentObservation = capture?.observation;
  const effectiveObservations = useMemo(() => !currentObservation ? [] : isDistinctObservation(currentObservation, observations) ? [...observations, currentObservation] : observations, [currentObservation, observations]);
  const result = useMemo(() => mode === 'estimate' ? estimate(effectiveObservations) : null, [mode, effectiveObservations]);
  const receivedDb = pressureAt(source, receiver.position);
  const notify = (message: string) => { setToast(message); clearTimeout(toastTimer.current); toastTimer.current = setTimeout(() => setToast(''), 3500); };
  const changeSource = (change: Partial<Source>) => { setSource(previous => ({ ...previous, ...change })); setObservations([]); };
  const changeArray = (change: Partial<Receiver>) => { setReceiver(previous => ({ ...previous, ...change })); setObservations([]); };
  const setCoordinate = (target: 'source' | 'receiver', axis: number, value: number) => {
    const original = target === 'source' ? source : receiver;
    const position = [...original.position] as Vec3; position[axis] = value;
    if (target === 'source') changeSource({ position }); else setReceiver(previous => ({ ...previous, position }));
  };
  const reset = () => {
    setSource(INITIAL_SOURCE); setReceiver(INITIAL_RECEIVER); setDevice('iphone'); setMode('estimate'); setPlacement('source'); setObservations([]); setPlaying(true); setHeatmap(true); setOpacity(0.68); setResetKey(value => value + 1); audio.stop(); notify('실험을 처음 상태로 되돌렸습니다.');
  };
  const saveObservation = () => {
    if (!currentObservation) { notify('도착 시간차 관측에는 마이크 두 개가 필요합니다.'); return; }
    if (!isDistinctObservation(currentObservation, observations)) { notify('휴대폰의 위치나 방향을 바꾼 뒤 다시 관측해 주세요.'); return; }
    if (observations.length >= 12) { notify('최대 12개 관측입니다. 관측을 지우고 다시 실험해 주세요.'); return; }
    setObservations(previous => [...previous, currentObservation]); setMode('estimate'); notify(`관측 ${observations.length + 1}개 저장 · 휴대폰을 옮겨 다음 관측을 추가하세요.`);
  };
  const exportExperiment = () => {
    const data = { schemaVersion: 2, appVersion: __APP_VERSION__, exportedAt: new Date().toISOString(), source, receiver, device, observations, result, engineInput: { ...frame, channels: frame.channels.map(channel => Array.from(channel)) }, engineOptions: { signal: source.signal, toneFrequencyHz: source.signal === 'tone' ? source.frequency : undefined }, searchVolume: SEARCH_VOLUME, engineOutput: capture?.measurement ?? null, assumptions: 'Synthetic PCM; standalone engine receives audio and microphone geometry only, never the source position. Free field; c=343 m/s; no reflections or diffraction; preset spacings are illustrative.' };
    const url = URL.createObjectURL(new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' }));
    const anchor = document.createElement('a'); anchor.href = url; anchor.download = `soundfield-v${__APP_VERSION__}-${new Date().toISOString().slice(0, 10)}.json`; anchor.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
    notify('실험 설정과 관측 결과를 JSON으로 내보냈습니다.');
  };
  const pointAtSource = () => {
    const delta = source.position.map((v, i) => v - receiver.position[i]);
    setReceiver(previous => ({ ...previous, yaw: Math.atan2(delta[0], -delta[2]), pitch: clamp(Math.atan2(delta[1], Math.hypot(delta[0], delta[2])), -1.2, 1.2) }));
  };

  return <div className="app-shell" data-mobile-view={mobileView} data-sheet={mobileSheet} data-controls={controlTab} data-settings={settingsTab}>
    <aside className="rail">
      <a className="brand-mark" href="#" aria-label="SoundField 홈"><AudioLines size={25} /></a>
      <div className="rail-navigation"><button className="rail-button active" title="시뮬레이터" aria-label="시뮬레이터" onClick={() => setModal(null)}><Box size={21} /></button><button className="rail-button" title="사용 가이드" aria-label="사용 가이드" onClick={() => setModal('guide')}><BookOpen size={21} /></button><button className="rail-button" title="릴리즈 노트" aria-label="릴리즈 노트" onClick={() => setModal('releases')}><History size={21} /></button></div>
      <a className="rail-button rail-bottom" href="https://github.com/doroper98/sound_detection" target="_blank" rel="noreferrer" aria-label="GitHub 저장소"><GitFork size={21} /></a>
      <div className="avatar">SF</div>
    </aside>
    <div className="main-shell">
      <header className="topbar"><div className="wordmark">soundfield<span>LAB</span></div><div className="breadcrumb">워크스페이스 <span>/</span> <strong>음향 위치 실험실</strong></div><div className="header-right"><span className="version-tag">v{__APP_VERSION__}</span><button className="text-button" aria-label="사용 가이드" onClick={() => setModal('guide')}><CircleHelp size={16} /><span>사용 가이드</span><ArrowUpRight size={14} /></button></div></header>
      <main>
        <div className="page-heading"><div><div className="eyebrow"><span /> SPATIAL ACOUSTICS SIMULATOR</div><h1>소리가 나는 곳을, 눈으로.</h1><p>공간에 소리를 놓고, 가상 마이크로 소리의 방향을 탐색해 보세요.</p></div><div className="heading-actions"><button className="button secondary" onClick={reset}><RotateCcw size={16} />초기화</button><button className="button primary" onClick={exportExperiment}><ArrowDownToLine size={16} />실험 내보내기</button></div></div>
        <div className="mobile-view-tabs segmented"><button className={mobileView === 'space' ? 'selected' : ''} onClick={() => setMobileView('space')}><Box size={15} />3D 공간</button><button className={mobileView === 'scanner' ? 'selected' : ''} onClick={() => setMobileView('scanner')}><ScanLine size={15} />사운드 스캔</button></div>
        <div className="workspace">
          <section className="scene-panel card">
            <div className="panel-heading"><div><span className="panel-icon"><Box size={17} /></span><h2>가상 공간</h2><span className="small-tag">3D SCENE</span></div><span className="room-label">스튜디오 룸 <ChevronDown size={14} /></span></div>
            <div className="scene-wrap">
              <SpatialView source={source} receiver={receiver} playing={playing} placement={placement} resetKey={resetKey} onPlace={point => {
                if (placement === 'source') { changeSource({ position: point }); notify('음원 위치를 변경했습니다. 높이는 아래에서 조절할 수 있어요.'); }
                if (placement === 'receiver') setReceiver(previous => ({ ...previous, position: [point[0], previous.position[1], point[2]] }));
              }} />
              <div className="scene-top"><span className="scene-badge"><span className="status-dot" />가상 시뮬레이션</span><span className="scene-size">8 × 7 × 3.2 m</span></div>
              <div className="scene-tools"><button className={placement === 'source' ? 'selected' : ''} title="음원 배치" aria-label="음원 배치" onClick={() => setPlacement('source')}><MousePointer2 size={18} /></button><button className={placement === 'receiver' ? 'selected' : ''} title="휴대폰 배치" aria-label="휴대폰 배치" onClick={() => setPlacement('receiver')}><Smartphone size={18} /></button><button className={placement === 'orbit' ? 'selected' : ''} title="공간 둘러보기" aria-label="공간 둘러보기" onClick={() => setPlacement('orbit')}><Move3D size={19} /></button><span /><button title="시점 초기화" aria-label="시점 초기화" onClick={() => setResetKey(value => value + 1)}><Maximize size={17} /></button></div>
              <div className="scene-legend"><span><i className="source-dot" />음원 01</span><span><i className="receiver-dot" />가상 마이크</span></div>
              <div className="axis-widget"><span className="axis-y">Y</span><span className="axis-z">Z</span><span className="axis-x">X</span><i /></div>
              <div className="scene-bottom"><MousePointer2 size={14} /><span>{placement === 'source' ? '물체나 바닥을 클릭하여 음원 배치' : placement === 'receiver' ? '바닥을 클릭하여 휴대폰 이동' : '드래그하여 공간 둘러보기'}</span><span className="scene-separator">·</span><span>드래그 회전 · 스크롤 확대</span></div>
            </div>
            <div className="scene-status"><div><span className="source-dot" /><strong>음원 01</strong><span className="coordinates" data-testid="source-coordinates">X {source.position[0].toFixed(2)} <i>/</i> Y {source.position[1].toFixed(2)} <i>/</i> Z {source.position[2].toFixed(2)} m</span></div><button className="text-button" onClick={() => setPlaying(value => !value)}>{playing ? <Pause size={14} /> : <Play size={14} />}{playing ? '파동 일시정지' : '파동 재생'}</button></div>
          </section>

          <section className="scanner-panel card">
            <div className="panel-heading"><div><span className="panel-icon"><ScanLine size={18} /></span><h2>사운드 스캐너</h2></div><span className="live-badge"><span />SIMULATED</span></div>
            <div className="scanner-body">
              <div className="segmented view-modes"><button className={mode === 'pressure' ? 'selected' : ''} onClick={() => setMode('pressure')}><Waves size={14} />정답 비교</button><button className={mode === 'estimate' ? 'selected' : ''} onClick={() => setMode('estimate')}><Crosshair size={14} />마이크 추정</button></div>
              <div className={`phone-frame ${device === 'ipad' ? 'tablet' : ''}`}>
                <PhoneView source={mode === 'pressure' ? source : null} candidate={mode === 'estimate' && effectiveObservations.length >= 3 && result && result.spread < 0.8 ? result.position : null} receiver={receiver} observations={effectiveObservations} levelDbfs={levels.levelDbfs} mode={mode} opacity={opacity} heatmap={heatmap} onLook={(yaw, pitch) => setReceiver(previous => ({ ...previous, yaw, pitch }))} />
                <div className="phone-shade" /><div className="dynamic-island" />
                <div className="phone-status"><span>9:41</span><div><Signal size={13} /><span className="battery" /></div></div>
                <div className="phone-app-heading"><AudioLines size={16} /><strong>SoundField</strong><span>SIM</span></div>
                <div className="phone-mode">{mode === 'pressure' ? 'REFERENCE · 정답 위치' : `${capture?.measurement.method.toUpperCase() ?? 'MONO'} · 음성 기반 추정`}</div>
                <div className="phone-level">수신 <output data-testid="pcm-level">{levels.levelDbfs.toFixed(1)} dBFS</output>{levels.clipped && <span> · 입력 포화</span>}</div>
                <div className="phone-reading"><span>{mode === 'pressure' ? '수신점의 가상 음압' : receiver.count === 1 ? '방향 정보 없음' : `${effectiveObservations.length}개 관측으로 추정`}</span><strong>{mode === 'pressure' ? receivedDb.toFixed(1) : receiver.count === 1 ? '—' : result?.candidates ?? '—'}<small>{mode === 'pressure' ? 'dB SPL' : receiver.count === 1 ? '' : '후보 격자'}</small></strong><span>{mode === 'pressure' ? '정답 비교용 · 탐지 결과 아님' : '색 = 수신 세기 × 적합도 · 띠 = 모호성'}</span></div>
                <div className="phone-bottom"><span><span className="status-dot" />{receiver.count} MIC</span><span>{Math.round(receiver.yaw * 180 / Math.PI)}° <i>AZ</i></span><span>{source.frequency.toFixed(0)} <i>Hz</i></span></div><div className="home-indicator" />
              </div>
              <div className="drag-hint"><Move3D size={14} />화면을 드래그하여 소리 둘러보기</div>
              <div className="heat-legend" title="고정 표시 척도 · PCM 수신 레벨에 방향 적합도를 반영한 시각화"><span>{HEAT_FLOOR_DBFS}</span><div /><span>{HEAT_CEILING_DBFS} dBFS</span></div>
              <div className="scanner-actions"><button className="button secondary" onClick={() => setHeatmap(value => !value)}><Layers3 size={14} />열지도 {heatmap ? 'ON' : 'OFF'}</button><button className="button secondary" onClick={pointAtSource} title="시뮬레이션 정답 위치를 바라봅니다"><Focus size={15} />음원 보기</button></div>
            </div>
          </section>

          <div className="dock-tabs"><button className={controlTab === 'settings' ? 'selected' : ''} onClick={() => { setMobileSheet(previous => controlTab === 'settings' ? !previous : true); setControlTab('settings'); }}><Settings2 size={15} />실험 설정</button><button className={controlTab === 'analysis' ? 'selected' : ''} onClick={() => { setMobileSheet(previous => controlTab === 'analysis' ? !previous : true); setControlTab('analysis'); }}><Activity size={15} />관측 & 추정 <span>{observations.length}</span></button><button className="sheet-close" aria-label="설정 패널 닫기" onClick={() => setMobileSheet(false)}><ChevronDown size={16} /></button></div>
          <section className="parameters card">
            <div className="panel-heading"><div><span className="panel-icon"><Settings2 size={17} /></span><h2>실험 설정</h2></div><span className="muted small">변경 사항이 바로 반영됩니다</span></div>
            <div className="settings-tabs segmented"><button className={settingsTab === 'source' ? 'selected' : ''} onClick={() => setSettingsTab('source')}>음원</button><button className={settingsTab === 'device' ? 'selected' : ''} onClick={() => setSettingsTab('device')}>마이크</button><button className={settingsTab === 'view' ? 'selected' : ''} onClick={() => setSettingsTab('view')}>공간·표시</button></div>
            <div className="parameter-columns">
              <div className="parameter-group"><h3><span className="section-number">01</span>음원 설정 <button className={`icon-button audio-button ${audio.enabled ? 'enabled' : ''}`} aria-label={audio.enabled ? '소리 끄기' : '주파수 미리듣기'} title="주파수 미리듣기 · 정현파" onClick={() => void audio.toggle()}>{audio.enabled ? <Volume2 size={16} /> : <VolumeX size={16} />}</button></h3>
                <Control label="볼륨" value={source.db} min={40} max={100} unit="dB @1m" onChange={db => changeSource({ db })} />
                <Control label="주파수" value={source.frequency} min={100} max={8000} step={10} unit="Hz" onChange={frequency => changeSource({ frequency })} />
                <Control label="파장" value={wavelength(source.frequency) * 100} min={4.2875} max={343} step={0.1} digits={2} unit="cm" onChange={cm => changeSource({ frequency: 34300 / cm })} />
                <div className="group-foot"><Waves size={13} />파장 = 음속 ÷ 주파수 · 음속 343 m/s</div>
              </div>
              <div className="parameter-group"><h3><span className="section-number">02</span>수음 장치</h3>
                <label className="field-label" htmlFor="device">가상 장치 프리셋</label><div className="select-wrap"><Smartphone size={16} /><select id="device" value={device} onChange={event => { setDevice(event.target.value); changeArray({ spacing: DEVICES.find(item => item.id === event.target.value)!.spacing }); }}>{DEVICES.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}</select><ChevronDown size={14} /></div>
                <div className="segmented mic-select"><button className={receiver.count === 1 ? 'selected' : ''} onClick={() => changeArray({ count: 1 })}><Mic size={14} />마이크 1개</button><button className={receiver.count === 2 ? 'selected' : ''} onClick={() => changeArray({ count: 2 })}><AudioLines size={14} />마이크 2개</button></div>
                <div className="array-layout"><label htmlFor="array-layout">배열 방향</label><select id="array-layout" value={receiver.layout} onChange={event => changeArray({ layout: event.target.value as Receiver['layout'] })}><option value="horizontal">좌우 · 방위 구분</option><option value="vertical">세로 · 고도 구분</option></select></div>
                <Control label="마이크 간격" value={receiver.spacing * 100} min={2} max={200} step={1} unit="cm" digits={0} onChange={cm => { setDevice('custom'); changeArray({ spacing: cm / 100 }); }} />
                <div className="group-foot">기종 이름은 실험 프리셋입니다. 실제 마이크 사양이 아닙니다.</div>
              </div>
              <div className="parameter-group"><h3><span className="section-number">03</span>공간 & 시각화</h3>
                <Control label="음원 높이" value={source.position[1]} min={0.1} max={3.1} step={0.05} digits={2} unit="m" onChange={value => setCoordinate('source', 1, value)} />
                <Control label="휴대폰 높이" value={receiver.position[1]} min={0.2} max={3} step={0.05} digits={2} unit="m" onChange={value => setCoordinate('receiver', 1, value)} />
                <Control label="열지도 불투명도" value={opacity * 100} min={0} max={100} unit="%" onChange={value => setOpacity(value / 100)} />
                <div className="group-foot"><Radio size={13} />자유 음장 모델 · 벽 반사와 차폐 미포함</div>
              </div>
            </div>
          </section>

          <section className="analysis-panel card"><div className="panel-heading"><div><span className="panel-icon"><Activity size={17} /></span><h2>관측 & 위치 추정</h2></div><span className="small-tag">EXPERIMENT</span></div>
            <div className="analysis-content"><div className="metric-grid"><div><span>수신 PCM 레벨</span><strong>{levels.levelDbfs.toFixed(1)}<small>dBFS</small></strong><em>{levels.clipped ? '입력 포화 · 볼륨을 낮추세요' : '48 kHz · 4096 samples'}</em></div><div><span>음성에서 추출한 시간차</span><strong>{currentObservation ? (currentObservation.delay * 1e6).toFixed(1) : '—'}<small>μs</small></strong><em>{capture?.measurement.method.toUpperCase() ?? '마이크 2개 필요'}</em></div></div>
              <div className="analysis-note"><span className="note-dot" /><p>{receiver.count === 1 ? '마이크 1개로는 방향을 알 수 없습니다. 2개로 바꾸어 도착 시간차를 비교해 보세요.' : observations.length < 3 ? '마이크 2개의 한 번 관측으로는 위치가 하나로 정해지지 않습니다. 위치·높이를 바꿔 관측을 모아 보세요.' : `20 cm 격자 탐색 · 후보 범위 ${result ? result.spread.toFixed(2) : '—'} m. 여러 후보가 남으면 다른 위치와 높이에서 관측하세요.`}</p></div>
              <div className="signal-control"><label htmlFor="signal">측정 신호 모델</label><select id="signal" value={source.signal} onChange={event => changeSource({ signal: event.target.value as Source['signal'] })}><option value="broadband">광대역 · 비주기 시간차</option><option value="tone">단일 주파수 · 위상 모호성</option></select></div>
              <div className="observation-actions"><button className="button primary" onClick={saveObservation} disabled={receiver.count === 1}><Plus size={15} />관측 저장 <span>{observations.length}/12</span></button><button className="icon-button" aria-label="관측 지우기" title="관측 지우기" onClick={() => { setObservations([]); notify('저장한 관측을 지웠습니다.'); }}><RotateCcw size={16} /></button></div>
              {result && observations.length >= 3 && <div className="estimate-result" data-testid="estimate-result">최고 후보 ({result.position.map(v => v.toFixed(1)).join(', ')}) m<br />설정 정답과의 격자 오차 {distance(source.position, result.position).toFixed(2)} m · 정확도 보장 아님</div>}
              <details className="coordinates-detail"><summary>좌표로 정밀 배치</summary>{(['source', 'receiver'] as const).map(target => <div className="coordinate-row" key={target}><span>{target === 'source' ? '음원' : '휴대폰'}</span>{['X', 'Y', 'Z'].map((axis, index) => <label key={axis}>{axis}<input aria-label={`${target === 'source' ? '음원' : '휴대폰'} ${axis} 좌표`} type="number" step="0.1" value={(target === 'source' ? source : receiver).position[index].toFixed(2)} onChange={event => { if (Number.isFinite(event.target.valueAsNumber)) setCoordinate(target, index, clamp(event.target.valueAsNumber, index === 1 ? 0.2 : index === 0 ? -3.7 : -3.2, index === 1 ? 3 : index === 0 ? 3.7 : 3.2)); }} /></label>)}</div>)}</details>
            </div>
          </section>
        </div>
        <footer><span><span className="status-dot" />모든 계산은 이 브라우저에서 실행됩니다</span><span>가상 실험 · 실제 마이크 수음 아님 <i>·</i> SoundField Lab v{__APP_VERSION__}</span></footer>
      </main>
    </div>
    {(toast || audio.error) && <div role="status" className="toast"><Check size={17} />{audio.error || toast}</div>}
    {modal === 'guide' && <Modal title="SoundField 실험 가이드" onClose={() => setModal(null)}>
      <p>소리가 발생하는 위치와 가상 마이크의 관측을 비교하는 3D 실험실입니다.</p>
      <ol><li><strong>음원 배치</strong> — 왼쪽 물체나 바닥을 클릭하고, 음원 높이를 조절합니다.</li><li><strong>신호 설정</strong> — 볼륨과 주파수를 바꿉니다. 파장은 음속 343 m/s에 맞춰 연동됩니다. 미리듣기는 작은 음량의 정현파이며 dB SPL 보정 출력이 아닙니다.</li><li><strong>둘러보기</strong> — 오른쪽 화면을 드래그하거나 방향키로 회전합니다. ‘음원 보기’는 설정한 정답 방향을 보여주는 보조 기능입니다.</li><li><strong>위치 추정</strong> — 마이크 2개를 선택하고 관측을 저장합니다. 왼쪽 휴대폰 도구로 장치를 옮기고 높이·방향도 바꾸어 3개 이상의 관측을 수집합니다.</li><li><strong>비교·저장</strong> — 간격과 신호 모델을 바꾸어 후보가 얼마나 넓게 남는지 비교하고, 결과를 JSON으로 내보냅니다.</li></ol>
      <h3>열지도 읽기</h3><p><strong>정답 비교</strong>는 정답 위치에 비교용 표식을 겹치며 실제 탐지 결과가 아닙니다. <strong>마이크 추정</strong>은 PCM에서 얻은 시간차로 시야의 방향 후보를 계산합니다. 3D 물체나 음원 좌표를 사용하지 않습니다. 띠가 넓게 남으면 방향을 아직 구분할 수 없는 상태입니다.</p>
      <p>두 모드 모두 PCM 수신 레벨을 고정 색상 척도에 반영합니다. 볼륨이 커지면 색이 강해지고 표시 임계값을 넘는 영역이 넓어집니다. 표시 면적은 음원의 실제 크기나 위치 정확도가 아닙니다. dBFS는 디지털 신호 레벨이며 실제 dB SPL로 교정되지 않았습니다. 입력 포화가 표시되면 볼륨을 낮추세요.</p>
      <h3>독립 음향 엔진</h3><p>합성 마이크 PCM → GCC-PHAT 또는 순음 위상 측정 → 후보 위치 탐색으로 처리합니다. 엔진은 음성 샘플, 샘플링 주파수, 동기화 여부, 마이크 배치만 받습니다. 탐색 범위는 호출하는 앱이 지정합니다. 내보낸 JSON의 engineInput은 3D 화면 없이 다시 분석할 수 있으며 정답 좌표는 별도의 비교 데이터입니다.</p>
      <h3>배열 방향</h3><p>좌우 배열은 좌우 방위에, 세로 배열은 높낮이에 민감합니다. 두 마이크 중 한 배열이 모든 3D 방향에 더 정확한 것은 아닙니다. 여러 위치·높이에서 관측하거나 다채널 배열이 필요합니다.</p>
      <h3>이번 실험의 가정</h3><p>벽과 물체는 배경입니다. 반사·흡음·회절·차폐와 실제 장치 잡음은 포함하지 않습니다. PCM은 합성한 동기화 채널이며 실제 수음은 아닙니다. 광대역 모델은 주파수 설정의 2배를 필터 척도로 쓰는 잡음, 순음 모델은 설정 주파수의 정현파입니다. 기종별 간격은 예시값입니다.</p>
      <p>마이크 1개는 방향 정보가 없고, 2개는 한 번의 측정으로 3D 좌표를 유일하게 결정하지 못합니다. 단일 주파수에서는 간격이 커지면 위상 모호성이 늘 수 있습니다. 관측 누적은 고정된 음원과 정확히 알려진 마이크 위치·방향을 가정합니다. 음원·신호·배열 설정을 바꾸면 기존 관측을 지웁니다.</p>
      <p><a href="https://github.com/doroper98/sound_detection/blob/main/docs_canonical/ACOUSTICS.md" target="_blank" rel="noreferrer">음향 모델과 실제 휴대폰 확장 계획 <ArrowUpRight size={13} /></a></p>
    </Modal>}
    {modal === 'releases' && <Modal title="릴리즈 노트" onClose={() => setModal(null)}><div className="release-content">{releaseNotes.split('\n').map((line, index) => line.startsWith('#') ? <h3 key={index}>{line.replace(/^#+\s*/, '')}</h3> : line.trim() ? <p key={index}>{line}</p> : null)}</div><a href="https://github.com/doroper98/sound_detection/releases" target="_blank" rel="noreferrer">GitHub 릴리즈 전체 보기 <ArrowUpRight size={13} /></a></Modal>}
  </div>;
}
