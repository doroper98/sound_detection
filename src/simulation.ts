/** The only PCM generator that knows the source position. Never imported by the engine. */
import { measureFrame, type AudioFrame } from '../packages/localization/src/index';
import { distance, microphones, pressureAt, type Receiver, type Source } from './acoustics';

function random(seed: number) {
  let state = seed >>> 0;
  return () => { state = (Math.imul(state, 1664525) + 1013904223) >>> 0; return state / 4294967296; };
}

export function simulateFrame(source: Source, receiver: Receiver): AudioFrame {
  const sampleRate = 48000; const size = 4096; const pair = microphones(receiver);
  const offsets = pair.map(point => distance(source.position, point) / 343 * sampleRate);
  const maxOffset = Math.ceil(Math.max(...offsets)) + 4;
  const rng = random(92841); const raw = new Float32Array(size + maxOffset + 8);
  // Broadband excitation with a controllable spectral scale, generated before propagation.
  const alpha = 1 - Math.exp(-2 * Math.PI * Math.min(18000, source.frequency * 2) / sampleRate);
  let filtered = 0;
  for (let i = 0; i < raw.length; i++) { filtered += alpha * ((rng() * 2 - 1) - filtered); raw[i] = filtered; }
  const channels = pair.map((point, channel) => {
    // Fixed virtual gain, with headroom for the volume slider. Clip the waveform
    // only at full scale; capping its gain made different loud inputs identical.
    const samples = new Float32Array(size); const amplitude = 0.015 * 10 ** ((pressureAt(source, point) - 65) / 20);
    for (let i = 0; i < size; i++) {
      const t = i + maxOffset - offsets[channel]; const floor = Math.floor(t); const fraction = t - floor;
      const sample = amplitude * (source.signal === 'tone' ? Math.sin(2 * Math.PI * source.frequency * t / sampleRate) : raw[floor] * (1 - fraction) + raw[floor + 1] * fraction);
      samples[i] = Math.max(-1, Math.min(1, sample));
    }
    return samples;
  });
  return { channels: channels.slice(0, receiver.count), sampleRate, microphonePositions: pair.slice(0, receiver.count), synchronized: true };
}

export function captureSimulation(source: Source, receiver: Receiver) {
  const frame = simulateFrame(source, receiver);
  const measurement = measureFrame(frame, { signal: source.signal, toneFrequencyHz: source.signal === 'tone' ? source.frequency : undefined });
  return { frame, measurement, observation: measurement.observations[0] };
}
