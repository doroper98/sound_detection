import { analyzeChannels, requestLabel, type FrameStats, type ProbeAttempt, type RequestKind } from './analysis';

export const stopStream = (stream: MediaStream | null) => stream?.getTracks().forEach(track => track.stop());
const aborted = () => new DOMException('검사를 중지했습니다.', 'AbortError');

/** getUserMedia cannot be cancelled; dispose a late result after UI cancellation. */
export function requestMedia(constraints: MediaStreamConstraints, signal: AbortSignal): Promise<MediaStream> {
  if (signal.aborted) return Promise.reject(aborted());
  return new Promise((resolve, reject) => {
    const onAbort = () => reject(aborted());
    signal.addEventListener('abort', onAbort, { once: true });
    navigator.mediaDevices.getUserMedia(constraints).then(stream => {
      signal.removeEventListener('abort', onAbort);
      if (signal.aborted) { stopStream(stream); reject(aborted()); } else resolve(stream);
    }, error => { signal.removeEventListener('abort', onAbort); reject(error); });
  });
}

export function mediaError(error: unknown) {
  const name = error instanceof Error ? error.name : 'UnknownError';
  const constraint = typeof error === 'object' && error !== null && 'constraint' in error && typeof error.constraint === 'string' ? error.constraint : undefined;
  return { name, constraint };
}

export function errorExplanation(name: string) {
  const messages: Record<string, string> = {
    NotAllowedError: '권한이 거절되었거나 사이트 설정에서 차단됐습니다. Safari의 이 웹사이트 카메라·마이크 권한을 확인해 주세요.',
    NotFoundError: '사용 가능한 입력 장치를 찾지 못했습니다.',
    NotReadableError: '장치를 열지 못했습니다. 다른 녹음·카메라 앱을 닫은 뒤 다시 시도해 주세요.',
    OverconstrainedError: '요청한 채널 수 또는 입력 조건을 제공하지 못했습니다.',
    AbortError: '검사를 중지했습니다.',
    TimeoutError: '음성 샘플이 도착하지 않았습니다. Safari에서 다시 시작해 주세요.',
    NotSupportedError: '이 브라우저에서 필요한 오디오 수집 기능을 사용할 수 없습니다.',
  };
  return messages[name] ?? '입력 장치를 시작하지 못했습니다. 브라우저 설정을 확인하고 다시 시도해 주세요.';
}

type Callbacks = { signal: AbortSignal; onProgress: (message: string) => void; onAttempt: (attempt: ProbeAttempt) => void; onLevel: (stats: FrameStats) => void };

function collect(context: AudioContext, stream: MediaStream, attempt: ProbeAttempt, callbacks: Callbacks) {
  return new Promise<void>((resolve, reject) => {
    const source = context.createMediaStreamSource(stream);
    const processor = new AudioWorkletNode(context, 'diagnostic-capture', { numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [1], channelCountMode: 'max', channelInterpretation: 'discrete' });
    const mute = context.createGain(); mute.gain.value = 0;
    let settled = false; let measuredFrom = 0;
    const finish = (error?: Error) => {
      if (settled) return; settled = true;
      clearTimeout(timeout); callbacks.signal.removeEventListener('abort', onAbort);
      source.disconnect(); processor.disconnect(); mute.disconnect(); processor.port.onmessage = null; processor.port.close();
      error ? reject(error) : resolve();
    };
    const onAbort = () => finish(aborted());
    const timeout = setTimeout(() => finish(new DOMException('No PCM', 'TimeoutError')), 8000);
    callbacks.signal.addEventListener('abort', onAbort, { once: true });
    processor.onprocessorerror = () => finish(new Error('AudioWorkletError'));
    processor.port.onmessage = (event: MessageEvent<{ channels: Float32Array[]; sampleRate: number }>) => {
      try {
        const { channels, sampleRate } = event.data;
        const stats = analyzeChannels(channels);
        if (!measuredFrom) measuredFrom = performance.now();
        if (!attempt.observedChannelCounts.includes(channels.length)) attempt.observedChannelCounts.push(channels.length);
        attempt.frameCount++; attempt.sampleCount += channels[0].length; attempt.pcmSampleRate = sampleRate; attempt.latest = stats;
        stats.channels.forEach((channel, index) => { if (channel.active && !attempt.activeChannels.includes(index + 1)) attempt.activeChannels.push(index + 1); });
        stats.pairs.forEach(pair => { const key = pair.channels.join('–'); if (pair.duplicateSuspected && !attempt.duplicatePairs.includes(key)) attempt.duplicatePairs.push(key); });
        callbacks.onLevel(stats);
        if (attempt.frameCount >= 4 && performance.now() - measuredFrom >= 1600) finish();
      } catch { finish(new Error('Invalid PCM')); }
    };
    source.connect(processor); processor.connect(mute); mute.connect(context.destination);
    if (callbacks.signal.aborted) finish(aborted());
  });
}

export async function probeMicrophones(callbacks: Callbacks): Promise<ProbeAttempt[]> {
  if (!navigator.mediaDevices?.getUserMedia || !globalThis.AudioContext) throw new DOMException('Unavailable', 'NotSupportedError');
  // Called directly by the start button: unlock audio before awaiting permission.
  const context = new AudioContext();
  const resume = context.resume();
  void resume.catch(() => {});
  let current: MediaStream | null = null;
  const onAbort = () => { stopStream(current); void context.close().catch(() => {}); };
  callbacks.signal.addEventListener('abort', onAbort, { once: true });
  const attempts: ProbeAttempt[] = [];
  try {
    if (!context.audioWorklet) throw new DOMException('AudioWorklet unavailable', 'NotSupportedError');
    await context.audioWorklet.addModule('/audio-diagnostics.worklet.js');
    for (const requested of [4, 2, 'default'] as const satisfies readonly RequestKind[]) {
      if (callbacks.signal.aborted) throw aborted();
      callbacks.onProgress(`${requestLabel(requested)} · 권한 허용 후 주변에서 소리를 내 주세요`);
      const attempt: ProbeAttempt = { requested, status: 'error', observedChannelCounts: [], frameCount: 0, sampleCount: 0, activeChannels: [], duplicatePairs: [] };
      try {
        current = await requestMedia({ video: false, audio: { ...(requested === 'default' ? {} : { channelCount: { exact: requested } }), echoCancellation: false, noiseSuppression: false, autoGainControl: false } }, callbacks.signal);
        const track = current.getAudioTracks()[0];
        const { channelCount, sampleRate, sampleSize, echoCancellation, noiseSuppression, autoGainControl } = track.getSettings();
        attempt.settings = { channelCount, sampleRate, sampleSize, echoCancellation, noiseSuppression, autoGainControl };
        try {
          const capabilities = track.getCapabilities?.();
          attempt.capabilities = capabilities ? { channelCount: capabilities.channelCount, sampleRate: capabilities.sampleRate } : undefined;
        } catch { /* Capability metadata is optional; still measure delivered PCM. */ }
        callbacks.onProgress(`${requestLabel(requested)} · 실제 음성 채널 수집 중`);
        // resume() was initiated from the user gesture. A suspended context times out
        // visibly; its pending promise must not keep Stop from cancelling the probe.
        await collect(context, current, attempt, callbacks);
        attempt.status = 'captured';
      } catch (error) {
        if (callbacks.signal.aborted) throw aborted();
        attempt.error = mediaError(error);
        attempt.status = attempt.error.name === 'OverconstrainedError' ? 'rejected' : 'error';
      } finally { stopStream(current); current = null; }
      attempts.push(attempt); callbacks.onAttempt(attempt);
      if (attempt.error && attempt.error.name !== 'OverconstrainedError') break;
    }
    return attempts;
  } finally {
    stopStream(current); callbacks.signal.removeEventListener('abort', onAbort);
    if (context.state !== 'closed') await context.close().catch(() => {});
  }
}
