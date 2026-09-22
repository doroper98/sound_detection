import { describe, expect, it } from 'vitest';
import { analyzeSpectrum } from '../src/live/spectrum';

const tone = (hz: number, amplitude = .1, rate = 48000) => Float32Array.from({ length: 4096 }, (_, i) => amplitude * Math.sin(2 * Math.PI * hz * i / rate));
const full = { minHz: 20, maxHz: 96000 };

describe('real-input frequency analysis', () => {
  for (const rate of [44100, 48000]) it(`finds a 1 kHz tone at ${rate} Hz without assuming the sample rate`, () => {
    const result = analyzeSpectrum(tone(1000, .1, rate), rate, full);
    expect(Math.abs(result.peakHz! - 1000)).toBeLessThan(result.binWidthHz);
    expect(result.totalDbfs).toBeCloseTo(-23.01, 1);
    expect(result.bandDbfs).toBeCloseTo(-23.01, 1);
    expect(result.band.maxHz).toBe(rate / 2);
  });
  it('retains a fixed level scale when amplitude changes by 20 dB', () => {
    const a = analyzeSpectrum(tone(1500, .01), 48000, full);
    const b = analyzeSpectrum(tone(1500, .1), 48000, full);
    expect(b.totalDbfs! - a.totalDbfs!).toBeCloseTo(20, 4);
    expect(b.bandDbfs! - a.bandDbfs!).toBeCloseTo(20, 4);
    expect(b.peakHz).toBe(a.peakHz);
  });
  it('separates two frequency bands while preserving whole-channel RMS', () => {
    const samples = tone(375, .2).map((x, i) => x + toneHigh[i]);
    const low = analyzeSpectrum(samples, 48000, { minHz: 20, maxHz: 500 });
    const high = analyzeSpectrum(samples, 48000, { minHz: 2000, maxHz: 8000 });
    expect(low.peakHz).toBe(375); expect(high.peakHz).toBe(3000);
    expect(low.bandDbfs! - high.bandDbfs!).toBeCloseTo(20 * Math.log10(2), 4);
    expect(low.totalDbfs).toBe(high.totalDbfs);
    expect(high.bandDbfs).toBeCloseTo(-23.01, 2);
  });
  const toneHigh = tone(3000, .1);
  it('does not assign a frequency to silence, DC, or sub-threshold noise', () => {
    const silent = analyzeSpectrum(new Float32Array(4096), 48000, full);
    expect(silent.peakHz).toBeNull(); expect(silent.totalDbfs).toBeNull(); expect(silent.bandDbfs).toBeNull();
    expect(silent.binsDbfs.every(x => x === null)).toBe(true);
    expect(analyzeSpectrum(new Float32Array(4096).fill(.5), 48000, full).peakHz).toBeNull();
    expect(analyzeSpectrum(tone(1000, 1e-7), 48000, full).peakHz).toBeNull();
  });
  it('reports clipping and does not double Nyquist energy', () => {
    const nyquist = Float32Array.from({ length: 4096 }, (_, i) => i % 2 ? -1 : 1);
    const result = analyzeSpectrum(nyquist, 48000, full);
    expect(result.clippedSamples).toBe(4096);
    expect(result.totalDbfs).toBe(0); expect(result.bandDbfs).toBeCloseTo(0, 8);
    expect(result.peakHz).toBe(24000);
  });
  it('rejects invalid PCM/rates/bands and caps bands at Nyquist', () => {
    expect(() => analyzeSpectrum(new Float32Array(100), 48000, full)).toThrow();
    expect(() => analyzeSpectrum(new Float32Array(4096).fill(NaN), 48000, full)).toThrow();
    expect(() => analyzeSpectrum(tone(1000), NaN, full)).toThrow();
    expect(() => analyzeSpectrum(tone(1000), 48000, { minHz: 500, maxHz: 20 })).toThrow();
    const result = analyzeSpectrum(tone(1000), 8000, { minHz: 10000, maxHz: 20000 });
    expect(result.band).toEqual({ minHz: 4000, maxHz: 4000 });
  });
});
