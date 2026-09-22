import { afterEach, expect, it, vi } from 'vitest';
import { monitorMicrophone } from '../src/live/monitor';

function fixture() {
  const track = new EventTarget();
  Object.assign(track, { readyState: 'live', getSettings: () => ({ channelCount: 1, sampleRate: 48000 }) });
  const stop = vi.fn();
  const stream = { getTracks: () => [{ stop }], getAudioTracks: () => [track] };
  const close = vi.fn(() => Promise.resolve());
  const disconnect = vi.fn();
  const port = { onmessage: null as ((event: MessageEvent) => void) | null, close: vi.fn() };
  const graph = () => ({ connect: vi.fn(), disconnect, gain: { value: 1 } });
  vi.stubGlobal('navigator', { mediaDevices: { getUserMedia: vi.fn(async () => stream) } });
  vi.stubGlobal('AudioContext', class {
    state = 'running'; destination = {}; audioWorklet = { addModule: async () => {} };
    resume = async () => {}; close = close; createMediaStreamSource = graph; createGain = graph;
  });
  vi.stubGlobal('AudioWorkletNode', class { port = port; connect = vi.fn(); disconnect = disconnect; onprocessorerror = null; });
  return { track, stop, close, disconnect, port };
}
afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers(); });

it('times out a stalled PCM route and releases every resource', async () => {
  vi.useFakeTimers(); const f = fixture(); const onFrame = vi.fn();
  const result = monitorMicrophone({ signal: new AbortController().signal, onSettings: vi.fn(), onFrame });
  const rejected = expect(result).rejects.toMatchObject({ name: 'TimeoutError' });
  await vi.advanceTimersByTimeAsync(8100); await rejected;
  expect(f.stop).toHaveBeenCalledOnce(); expect(f.close).toHaveBeenCalledOnce();
  expect(f.port.close).toHaveBeenCalledOnce(); expect(onFrame).not.toHaveBeenCalled();
  expect(vi.getTimerCount()).toBe(0);
});

it('ends on device removal and leaves no pending timers', async () => {
  vi.useFakeTimers(); const f = fixture();
  const result = monitorMicrophone({ signal: new AbortController().signal, onSettings: vi.fn(), onFrame: vi.fn() });
  const rejected = expect(result).rejects.toMatchObject({ name: 'NotReadableError' });
  await vi.advanceTimersByTimeAsync(0); f.track.dispatchEvent(new Event('ended')); await rejected;
  expect(f.stop).toHaveBeenCalledOnce(); expect(f.port.onmessage).toBeNull(); expect(vi.getTimerCount()).toBe(0);
});

it('Stop resolves the monitor and prevents delivery of further PCM', async () => {
  vi.useFakeTimers(); const f = fixture(); const controller = new AbortController(); const onFrame = vi.fn();
  const result = monitorMicrophone({ signal: controller.signal, onSettings: vi.fn(), onFrame });
  await vi.advanceTimersByTimeAsync(0);
  const handler = f.port.onmessage!; handler({ data: { channels: [new Float32Array(4096)], sampleRate: 48000 } } as MessageEvent);
  controller.abort(); await result;
  handler({ data: {} } as MessageEvent);
  expect(onFrame).toHaveBeenCalledOnce(); expect(f.port.close).toHaveBeenCalledOnce(); expect(vi.getTimerCount()).toBe(0);
});
