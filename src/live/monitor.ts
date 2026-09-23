import { requestMedia, stopStream } from './probe';
import type { CaptureSettings } from './analysis';

export type PcmFrame = { channels: Float32Array[]; sampleRate: number };
type MonitorCallbacks = {
  signal: AbortSignal;
  onSettings: (settings: CaptureSettings) => void;
  onFrame: (frame: PcmFrame) => void;
};

/** Resolves on Stop; rejects on lost/invalid input. No speaker monitoring or recording. */
export async function monitorMicrophone({ signal, onSettings, onFrame }: MonitorCallbacks): Promise<void> {
  if (signal.aborted) return;
  if (!navigator.mediaDevices?.getUserMedia || !globalThis.AudioContext || !globalThis.AudioWorkletNode) throw new DOMException('Unavailable', 'NotSupportedError');
  const context = new AudioContext();
  void context.resume().catch(() => {});
  let stream: MediaStream | null = null;
  let source: MediaStreamAudioSourceNode | undefined;
  let processor: AudioWorkletNode | undefined;
  let mute: GainNode | undefined;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let settle: ((error?: Error) => void) | undefined;
  const abort = () => {
    stopStream(stream); settle?.();
    void context.close().catch(() => {});
  };
  const ended = () => settle?.(new DOMException('Input ended', 'NotReadableError'));
  signal.addEventListener('abort', abort, { once: true });
  try {
    if (!context.audioWorklet) throw new DOMException('Unavailable', 'NotSupportedError');
    await context.audioWorklet.addModule('/audio-diagnostics.worklet.js');
    if (signal.aborted) return;
    stream = await requestMedia({ video: false, audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false } }, signal);
    if (signal.aborted) return;
    const track = stream.getAudioTracks()[0];
    if (!track || track.readyState === 'ended') throw new DOMException('Input ended', 'NotReadableError');
    const { channelCount, sampleRate, sampleSize, echoCancellation, noiseSuppression, autoGainControl } = track.getSettings();
    onSettings({ channelCount, sampleRate, sampleSize, echoCancellation, noiseSuppression, autoGainControl });
    source = context.createMediaStreamSource(stream);
    processor = new AudioWorkletNode(context, 'diagnostic-capture', { numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [1], channelCountMode: 'max', channelInterpretation: 'discrete' });
    mute = context.createGain(); mute.gain.value = 0;
    await new Promise<void>((resolve, reject) => {
      let settled = false;
      settle = error => { if (settled) return; settled = true; error ? reject(error) : resolve(); };
      const watch = () => {
        clearTimeout(timer);
        timer = setTimeout(() => settle?.(new DOMException('No PCM', 'TimeoutError')), 8000);
      };
      track.addEventListener('ended', ended);
      processor!.onprocessorerror = () => settle?.(new DOMException('Processor failed', 'NotReadableError'));
      processor!.port.onmessage = (event: MessageEvent<PcmFrame>) => {
        if (signal.aborted || settled) return;
        try { onFrame(event.data); watch(); }
        catch { settle?.(new DOMException('Invalid PCM', 'NotReadableError')); }
      };
      watch();
      source!.connect(processor!); processor!.connect(mute!); mute!.connect(context.destination);
      if (signal.aborted) settle();
    });
  } catch (error) {
    if (!signal.aborted) throw error;
  } finally {
    clearTimeout(timer); signal.removeEventListener('abort', abort);
    stream?.getAudioTracks().forEach(track => track.removeEventListener('ended', ended));
    source?.disconnect(); processor?.disconnect(); mute?.disconnect();
    if (processor) { processor.port.onmessage = null; processor.onprocessorerror = null; processor.port.close(); }
    stopStream(stream);
    if (context.state !== 'closed') await context.close().catch(() => {});
  }
}
