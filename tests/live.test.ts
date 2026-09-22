import { describe, expect, it, vi, afterEach } from 'vitest';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { analyzeChannels, probeVerdict, type ProbeAttempt } from '../src/live/analysis';
import { requestMedia } from '../src/live/probe';

const tone = (frequency: number) => Float32Array.from({ length: 4096 }, (_, i) => Math.sin(i * frequency * 2 * Math.PI / 48000) * 0.1);
const captured = (count: number, reported = count): ProbeAttempt => ({ requested: 4, status: 'captured', settings: { channelCount: reported }, observedChannelCounts: [count], frameCount: 8, sampleCount: 32768, activeChannels: Array.from({ length: count }, (_, i) => i + 1), duplicatePairs: [] });

describe('live diagnostics do not equate channels with physical microphones', () => {
  it('separates silence, identical signals, and different waveforms', () => {
    const silence = analyzeChannels([new Float32Array(4096), new Float32Array(4096)]);
    expect(silence.channels[0].levelDbfs).toBeNull(); expect(silence.pairs[0].duplicateSuspected).toBe(false);
    expect(analyzeChannels([tone(500), tone(500)]).pairs[0].duplicateSuspected).toBe(true);
    const four = analyzeChannels([tone(300), tone(700), tone(1300), tone(1900)]);
    expect(four.channels.every(channel => channel.active)).toBe(true);
    expect(four.pairs).toHaveLength(6); expect(four.pairs.every(pair => !pair.duplicateSuspected)).toBe(true);
  });
  it('refuses invalid PCM and keeps quiet channels indeterminate', () => {
    expect(() => analyzeChannels([])).toThrow();
    expect(() => analyzeChannels([tone(300), new Float32Array(40)])).toThrow();
    expect(() => analyzeChannels([new Float32Array([NaN])])).toThrow();
    expect(probeVerdict([{ ...captured(4), activeChannels: [1] }]).title).toContain('신호 확인 필요');
  });
  it('uses observed counts, never trusting an accepted four-channel request alone', () => {
    expect(probeVerdict([captured(1, 4)]).title).toContain('안정 수신 미확인');
    expect(probeVerdict([{ ...captured(4), observedChannelCounts: [2, 4] }]).title).toContain('안정 수신 미확인');
    expect(probeVerdict([captured(4, 2)]).title).toContain('불일치');
    expect(probeVerdict([{ ...captured(4), duplicatePairs: ['1–2'] }]).title).toContain('중복');
    expect(probeVerdict([captured(4)]).detail).toContain('미검증');
    expect(probeVerdict([]).title).toContain('데이터 없음');
  });
});

describe('AudioWorklet transport', () => {
  it('preserves four input channels across variable block sizes and resets on channel changes', () => {
    type Processor = { process: (inputs: Float32Array[][], outputs: Float32Array[][]) => boolean };
    let construct: (() => Processor) | undefined;
    const frames: { channels: Float32Array[]; sampleRate: number }[] = [];
    runInNewContext(readFileSync('public/audio-diagnostics.worklet.js', 'utf8'), {
      Float32Array, sampleRate: 48000,
      AudioWorkletProcessor: class { port = { postMessage: (frame: typeof frames[number]) => frames.push(frame) }; },
      registerProcessor: (_name: string, ctor: new () => Processor) => { construct = () => new ctor(); },
    });
    const processor = construct!(); const output = new Float32Array(128).fill(1);
    for (const length of [128, 256, 512, 3200]) processor.process([Array.from({ length: 4 }, (_, c) => new Float32Array(length).fill((c + 1) / 10))], [[output]]);
    expect(frames).toHaveLength(1); expect(frames[0].channels).toHaveLength(4);
    frames[0].channels.forEach((channel, i) => expect(channel.every(x => Math.abs(x - (i + 1) / 10) < 1e-7)).toBe(true));
    expect(output.every(x => x === 0)).toBe(true);
    processor.process([[new Float32Array(4096).fill(0.7)]], [[output]]);
    expect(frames[1].channels).toHaveLength(1); expect(frames[1].sampleRate).toBe(48000);
  });
});

afterEach(() => vi.unstubAllGlobals());
it('stops a late permission result after cancellation without leaking capture', async () => {
  let resolve!: (stream: MediaStream) => void;
  vi.stubGlobal('navigator', { mediaDevices: { getUserMedia: () => new Promise<MediaStream>(done => { resolve = done; }) } });
  const controller = new AbortController(); const result = requestMedia({ audio: true }, controller.signal);
  controller.abort(); await expect(result).rejects.toMatchObject({ name: 'AbortError' });
  const stop = vi.fn(); resolve({ getTracks: () => [{ stop }] } as unknown as MediaStream);
  await Promise.resolve(); expect(stop).toHaveBeenCalledOnce();
});
