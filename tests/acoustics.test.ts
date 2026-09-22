import { describe, expect, it } from 'vitest';
import { delayAt, distance, estimate, INITIAL_RECEIVER, INITIAL_SOURCE, isDistinctObservation, likelihood, microphones, observe, pressureAt, wavelength, type Receiver, type Source, type Vec3 } from '../src/acoustics';

describe('free-field acoustics and observability', () => {
  it('links frequency and wavelength at 343 m/s', () => { expect(wavelength(1000)).toBeCloseTo(0.343); expect(wavelength(343)).toBe(1); });
  it('reduces pressure by about 6 dB when distance doubles', () => {
    const source: Source = { ...INITIAL_SOURCE, position: [0, 0, 0] };
    expect(pressureAt(source, [1, 0, 0]) - pressureAt(source, [2, 0, 0])).toBeCloseTo(6.0206, 3);
    expect(Number.isFinite(pressureAt(source, [0, 0, 0]))).toBe(true);
  });
  it('keeps physical microphone spacing under rotations', () => {
    const pair = microphones({ ...INITIAL_RECEIVER, yaw: 1.2, pitch: 0.7, spacing: 0.9 });
    expect(distance(...pair)).toBeCloseTo(0.9, 10);
  });
  it('has zero broadside delay and bounded signed delay', () => {
    const pair: [Vec3, Vec3] = [[-0.1, 0, 0], [0.1, 0, 0]];
    expect(delayAt([0, 3, 0], pair)).toBe(0);
    expect(delayAt([3, 0, 0], pair)).toBeCloseTo(0.2 / 343);
    expect(delayAt([-3, 0, 0], pair)).toBeCloseTo(-0.2 / 343);
  });
  it('does not invent a position without observations', () => { expect(estimate([])).toBeNull(); expect(likelihood([0, 0, 0], [])).toBe(0); });
  it('keeps a broad region for one pair observation', () => {
    const result = estimate([observe(INITIAL_SOURCE, INITIAL_RECEIVER)])!;
    expect(result.candidates).toBeGreaterThan(100); expect(result.spread).toBeGreaterThan(2);
  });
  it('narrows a static source using independent poses and heights', () => {
    const source: Source = { ...INITIAL_SOURCE, position: [-1.4, 1.1, -1.5] };
    const poses: Receiver[] = [INITIAL_RECEIVER,
      { ...INITIAL_RECEIVER, position: [-2.7, 0.5, 1], yaw: 0.7, pitch: 0.3, spacing: 0.4 },
      { ...INITIAL_RECEIVER, position: [2.3, 2.8, -0.4], yaw: -0.9, pitch: -0.6, spacing: 0.4 },
      { ...INITIAL_RECEIVER, position: [0, 1.8, -2.8], yaw: 1.8, pitch: 0.4, spacing: 0.4 }];
    const result = estimate(poses.map(pose => observe(source, pose)))!;
    expect(distance(source.position, result.position)).toBeLessThan(0.21);
    expect(result.candidates).toBeLessThan(10);
  });
  it('rejects repeated poses but accepts a translated receiver', () => {
    const observation = observe(INITIAL_SOURCE, INITIAL_RECEIVER);
    expect(isDistinctObservation(observation, [observation])).toBe(false);
    expect(isDistinctObservation(observe(INITIAL_SOURCE, { ...INITIAL_RECEIVER, position: [2, 1, 1] }), [observation])).toBe(true);
  });
  it('retains periodic ambiguity for a single frequency', () => {
    const tone = observe({ ...INITIAL_SOURCE, frequency: 8000, signal: 'tone' }, { ...INITIAL_RECEIVER, spacing: 2 });
    const shifted = { ...tone, delay: tone.delay + 1 / tone.frequency };
    expect(likelihood(INITIAL_SOURCE.position, [shifted])).toBeCloseTo(1);
    expect(likelihood(INITIAL_SOURCE.position, [{ ...shifted, signal: 'broadband' }])).toBeLessThan(0.01);
  });
});
