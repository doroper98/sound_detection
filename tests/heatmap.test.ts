import { describe, expect, it } from 'vitest';
import { captureSimulation, simulateFrame } from '../src/simulation';
import { INITIAL_RECEIVER, INITIAL_SOURCE } from '../src/acoustics';
import { heatIntensity, pcmStats } from '../src/heatmap';

describe('volume and display level are independent from localization', () => {
  it.each(['broadband', 'tone'] as const)('preserves delay while tracking every 10 dB step for %s', signal => {
    const captures = [40, 50, 60, 70, 80, 90, 100].map(db => captureSimulation({ ...INITIAL_SOURCE, signal, db }, INITIAL_RECEIVER));
    for (let i = 1; i < captures.length; i++) {
      expect(captures[i].measurement.levelDbfs - captures[i - 1].measurement.levelDbfs).toBeCloseTo(10, 4);
      expect(captures[i].observation.delay).toBeCloseTo(captures[0].observation.delay, 8);
      expect(pcmStats(captures[i].frame.channels).levelDbfs).toBeCloseTo(captures[i].measurement.levelDbfs, 8);
      expect(pcmStats(captures[i].frame.channels).clipped).toBe(false);
    }
  });
  it('bounds overloaded PCM, reports clipping and supports mono levels without inventing a direction', () => {
    const frame = simulateFrame({ ...INITIAL_SOURCE, db: 100, signal: 'tone', position: INITIAL_RECEIVER.position }, { ...INITIAL_RECEIVER, count: 1 });
    expect(frame.channels).toHaveLength(1);
    expect(frame.channels[0].every(sample => Math.abs(sample) <= 1)).toBe(true);
    expect(pcmStats(frame.channels).clipped).toBe(true);
    expect(Number.isFinite(pcmStats(frame.channels).levelDbfs)).toBe(true);
    expect(pcmStats([new Float32Array(100)]).levelDbfs).toBe(-Infinity);
  });
  it('uses a fixed display threshold and never creates heat from a zero directional response', () => {
    expect(heatIntensity(1, -100)).toBe(0);
    expect(heatIntensity(1, -35)).toBeGreaterThan(heatIntensity(1, -65));
    expect(heatIntensity(0.01, -65)).toBe(0);
    expect(heatIntensity(0.01, -35)).toBeGreaterThan(0);
    expect(heatIntensity(0, 0)).toBe(0);
    expect(heatIntensity(1, -Infinity)).toBe(0);
    expect(heatIntensity(1, NaN)).toBe(0);
  });
});
