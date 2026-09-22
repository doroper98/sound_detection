import { describe, expect, it } from 'vitest';
import { readFileSync, readdirSync } from 'node:fs';
import { measureFrame, localize, distance, type AudioFrame, type Observation, type Vec3 } from '../packages/localization/src/index';
import { captureSimulation } from '../src/simulation';
import { INITIAL_RECEIVER, INITIAL_SOURCE, microphones } from '../src/acoustics';

function fixture(lag: number): AudioFrame {
  let seed = 120; const random = Array.from({ length: 5000 }, () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 4294967296 - 0.5; });
  const channels = [Float32Array.from(random.slice(500 - lag, 500 - lag + 4096)), Float32Array.from(random.slice(500, 4596))];
  return { channels, sampleRate: 48000, microphonePositions: [[-0.2, 0, 0], [0.2, 0, 0]], synchronized: true };
}

describe('standalone PCM engine with no scene or source input', () => {
  it.each([-29, -7, 0, 13, 31])('recovers a signed %i-sample delay from audio only', lag => {
    const measurement = measureFrame(fixture(lag));
    expect(measurement.observations[0].delay * 48000).toBeCloseTo(lag, 1);
    expect(measurement.method).toBe('gcc-phat');
  });
  it('rejects unsynchronized, silent, mismatched and single-channel captures', () => {
    expect(() => measureFrame({ ...fixture(1), synchronized: false })).toThrow(/Synchronized/);
    expect(() => measureFrame({ ...fixture(1), channels: [new Float32Array(4096), new Float32Array(4096)] })).toThrow(/silent/);
    expect(() => measureFrame({ ...fixture(1), channels: [new Float32Array(100), new Float32Array(200)] })).toThrow(/equal length/);
    expect(() => measureFrame({ ...fixture(1), channels: [new Float32Array(4096)] })).toThrow(/two channels/);
  });
  it('does not change a measurement when the unrelated 3D source moves', () => {
    const frame = fixture(9); const before = measureFrame(frame);
    captureSimulation({ ...INITIAL_SOURCE, position: [3, 2.7, 2] }, INITIAL_RECEIVER);
    expect(measureFrame(frame)).toEqual(before);
  });
  it('runs generated microphone PCM through the same engine and recovers propagation delay', () => {
    const { frame, observation, measurement } = captureSimulation(INITIAL_SOURCE, INITIAL_RECEIVER);
    const expected = (distance(INITIAL_SOURCE.position, frame.microphonePositions[0]) - distance(INITIAL_SOURCE.position, frame.microphonePositions[1])) / 343;
    expect(Math.abs(observation.delay - expected) * 48000).toBeLessThan(0.6);
    expect(measurement).toEqual(measureFrame(frame));
  });
  it('measures periodic phase from tone PCM without source coordinates', () => {
    const { frame } = captureSimulation({ ...INITIAL_SOURCE, signal: 'tone', frequency: 2000 }, INITIAL_RECEIVER);
    const observation = measureFrame(frame, { signal: 'tone', toneFrequencyHz: 2000 }).observations[0];
    const expected = (distance(INITIAL_SOURCE.position, frame.microphonePositions[0]) - distance(INITIAL_SOURCE.position, frame.microphonePositions[1])) / 343;
    const residual = (observation.delay - expected) * 2000;
    expect(Math.abs(residual - Math.round(residual))).toBeLessThan(0.01);
  });
  it('rotates the microphone axis between horizontal and vertical without changing spacing', () => {
    const horizontal = microphones({ ...INITIAL_RECEIVER, yaw: 0, pitch: 0, layout: 'horizontal' });
    const vertical = microphones({ ...INITIAL_RECEIVER, yaw: 0, pitch: 0, layout: 'vertical' });
    expect(horizontal[0][1]).toBe(horizontal[1][1]); expect(vertical[0][0]).toBe(vertical[1][0]);
    expect(distance(...horizontal)).toBeCloseTo(distance(...vertical));
  });
  it('localizes in a caller-defined coordinate system far outside the demo room', () => {
    const target: Vec3 = [101, 51, -30];
    const sensors: Vec3[] = [[99, 50, -28], [102, 50, -28], [100, 53, -28], [100, 50, -33]];
    const observations: Observation[] = sensors.slice(1).map(sensor => ({ microphones: [sensors[0], sensor], delay: (distance(target, sensors[0]) - distance(target, sensor)) / 343, sigma: 1e-5, frequency: 1000, signal: 'broadband' }));
    const result = localize(observations, { min: [98, 49, -34], max: [104, 54, -26], step: 0.2 })!;
    expect(distance(result.position, target)).toBeLessThan(0.01);
  });
  it('contains no imports from React, Three.js, the scene or the simulator', () => {
    for (const name of readdirSync('packages/localization/src').filter(name => name.endsWith('.ts'))) {
      const content = readFileSync(`packages/localization/src/${name}`, 'utf8');
      expect(content).not.toMatch(/from\s+['"](?:react|three|.*simulation|.*acoustics|.*room|.*App)/);
      expect(content).not.toMatch(/\b(?:window|document|navigator|INITIAL_SOURCE|ROOM)\b/);
    }
  });
});
