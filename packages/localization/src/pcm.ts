import FFT from 'fft.js';
import { distance } from './solver.js';
import type { AudioFrame, Measurement, MeasurementOptions, Observation } from './types.js';

const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value));

function validate(frame: AudioFrame) {
  if (!frame.synchronized) throw new Error('Synchronized channels with a shared sample clock are required');
  if (!Number.isFinite(frame.sampleRate) || frame.sampleRate < 8000 || frame.sampleRate > 192000) throw new Error('sampleRate must be 8000–192000 Hz');
  if (frame.channels.length < 2 || frame.channels.length !== frame.microphonePositions.length) throw new Error('At least two channels and matching microphone positions are required');
  const size = frame.channels[0].length;
  if (size < 64 || size > 65536) throw new Error('Use 64–65536 samples per frame');
  for (const channel of frame.channels) if (channel.length !== size || !channel.every(Number.isFinite)) throw new Error('Channels must have equal length and finite samples');
  if (!frame.microphonePositions.flat().every(Number.isFinite)) throw new Error('Invalid microphone positions');
}

export function measureFrame(frame: AudioFrame, options: MeasurementOptions = {}): Measurement {
  validate(frame);
  const speed = options.speedOfSound ?? 343;
  if (!Number.isFinite(speed) || speed <= 0) throw new Error('Invalid speed of sound');
  const signal = options.signal ?? 'broadband'; const size = frame.channels[0].length;
  const nfft = 2 ** Math.ceil(Math.log2(size * 2)); const fft = new FFT(nfft);
  const energy = frame.channels.map(channel => channel.reduce((sum, sample) => sum + sample * sample, 0) / size);
  if (energy.some(value => value < 1e-12)) throw new Error('Signal is silent or too quiet');
  const spectra: number[][] = []; const prepared: number[][] = [];
  for (const channel of frame.channels) {
    const mean = channel.reduce((sum, sample) => sum + sample, 0) / size;
    const samples = new Array<number>(nfft).fill(0);
    for (let i = 0; i < size; i++) samples[i] = (channel[i] - mean) * (0.5 - 0.5 * Math.cos(2 * Math.PI * i / (size - 1)));
    const spectrum: number[] = fft.createComplexArray(); fft.realTransform(spectrum, samples); fft.completeSpectrum(spectrum);
    spectra.push(spectrum); prepared.push(samples);
  }
  let peakBin = 1;
  const power = (spectrum: number[], k: number) => spectrum[k * 2] ** 2 + spectrum[k * 2 + 1] ** 2;
  for (let k = 2; k < nfft / 2; k++) if (power(spectra[0], k) > power(spectra[0], peakBin)) peakBin = k;
  const frequency = options.toneFrequencyHz ?? peakBin * frame.sampleRate / nfft;
  if (!Number.isFinite(frequency) || frequency <= 0 || frequency >= frame.sampleRate / 2) throw new Error('Invalid tone frequency');
  const observations: Observation[] = []; let minimumRatio = Infinity;
  for (let channelIndex = 1; channelIndex < frame.channels.length; channelIndex++) {
    const pair: Observation['microphones'] = [frame.microphonePositions[0], frame.microphonePositions[channelIndex]];
    const spacing = distance(...pair); if (spacing < 0.001) throw new Error('Microphones must be separated');
    const maxLag = Math.ceil(spacing / speed * frame.sampleRate);
    if (maxLag >= size / 2) throw new Error('Audio frame is too short for the microphone spacing');
    let delay: number; let sigma: number; let ratio = 1;
    if (signal === 'tone') {
      const phases = [0, channelIndex].map(index => {
        let real = 0; let imaginary = 0;
        for (let i = 0; i < size; i++) { const angle = 2 * Math.PI * frequency * i / frame.sampleRate; real += prepared[index][i] * Math.cos(angle); imaginary -= prepared[index][i] * Math.sin(angle); }
        return Math.atan2(imaginary, real);
      });
      const phase = Math.atan2(Math.sin(phases[0] - phases[1]), Math.cos(phases[0] - phases[1]));
      delay = -phase / (2 * Math.PI * frequency); sigma = Math.max(0.5 / frame.sampleRate, 0.02 / frequency);
    } else {
      const a = spectra[0]; const b = spectra[channelIndex]; const cross: number[] = fft.createComplexArray();
      let maxMagnitude = 0;
      for (let k = 0; k < nfft; k++) {
        const re = a[2 * k] * b[2 * k] + a[2 * k + 1] * b[2 * k + 1];
        const im = a[2 * k + 1] * b[2 * k] - a[2 * k] * b[2 * k + 1];
        cross[2 * k] = re; cross[2 * k + 1] = im; maxMagnitude = Math.max(maxMagnitude, Math.hypot(re, im));
      }
      for (let k = 0; k < nfft; k++) {
        const magnitude = Math.hypot(cross[2 * k], cross[2 * k + 1]);
        const weight = magnitude > maxMagnitude * 1e-5 ? 1 / magnitude : 0;
        cross[2 * k] *= weight; cross[2 * k + 1] *= weight;
      }
      const correlation: number[] = fft.createComplexArray(); fft.inverseTransform(correlation, cross);
      const at = (lag: number) => correlation[((lag + nfft) % nfft) * 2];
      let peak = -Infinity; let lag = 0; let squared = 0;
      for (let i = -maxLag; i <= maxLag; i++) { const value = at(i); squared += value * value; if (value > peak) { peak = value; lag = i; } }
      const denominator = at(lag - 1) - 2 * peak + at(lag + 1);
      const correction = Math.abs(denominator) > 1e-12 ? clamp(0.5 * (at(lag - 1) - at(lag + 1)) / denominator, -0.5, 0.5) : 0;
      delay = clamp((lag + correction) / frame.sampleRate, -spacing / speed, spacing / speed);
      ratio = peak / Math.max(1e-12, Math.sqrt(squared / (2 * maxLag + 1)));
      let halfWidth = 1;
      while (halfWidth < maxLag && (at(lag - halfWidth) > peak / 2 || at(lag + halfWidth) > peak / 2)) halfWidth++;
      sigma = Math.max(0.5 / frame.sampleRate, halfWidth / (frame.sampleRate * Math.max(3, ratio * 2)));
    }
    minimumRatio = Math.min(minimumRatio, ratio);
    observations.push({ microphones: pair.map(point => [...point]) as Observation['microphones'], delay, sigma, frequency, signal });
  }
  return { observations, levelDbfs: 10 * Math.log10(energy.reduce((a, b) => a + b, 0) / energy.length), method: signal === 'tone' ? 'tone-phase' : 'gcc-phat', sampleRate: frame.sampleRate, sampleCount: size, peakRatio: minimumRatio };
}
