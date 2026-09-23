import FFT from 'fft.js';

export type FrequencyBand = { minHz: number; maxHz: number };
export type Spectrum = {
  sampleRate: number; fftSize: number; binWidthHz: number;
  totalDbfs: number | null; bandDbfs: number | null; peakHz: number | null;
  clippedSamples: number; band: FrequencyBand; binsDbfs: (number | null)[];
};
const db = (power: number) => power > 0 ? 10 * Math.log10(power) : null;

/** One-sided, Hann-window power spectrum. Values are digital RMS, not SPL. */
export function analyzeSpectrum(samples: Float32Array, sampleRate: number, band: FrequencyBand): Spectrum {
  const size = samples.length;
  if (size < 64 || size > 65536 || (size & (size - 1)) || !samples.every(Number.isFinite)) throw new Error('Invalid PCM');
  if (!Number.isFinite(sampleRate) || sampleRate < 8000 || sampleRate > 192000) throw new Error('Invalid sample rate');
  if (!Number.isFinite(band.minHz) || !Number.isFinite(band.maxHz) || band.minHz < 0 || band.maxHz <= band.minHz) throw new Error('Invalid band');
  const fft = new FFT(size);
  const input = new Array<number>(size);
  let energy = 0; let windowEnergy = 0; let clippedSamples = 0;
  const mean = samples.reduce((sum, x) => sum + x, 0) / size;
  for (let i = 0; i < size; i++) {
    const window = .5 - .5 * Math.cos(2 * Math.PI * i / size);
    input[i] = (samples[i] - mean) * window;
    windowEnergy += window * window; energy += samples[i] * samples[i];
    if (Math.abs(samples[i]) >= 1) clippedSamples++;
  }
  const output: number[] = fft.createComplexArray();
  fft.realTransform(output, input);
  const binWidthHz = sampleRate / size;
  const effectiveBand = { minHz: Math.min(band.minHz, sampleRate / 2), maxHz: Math.min(band.maxHz, sampleRate / 2) };
  let bandPower = 0; let peakPower = 0; let peakBin = 0;
  const binsDbfs = Array.from({ length: size / 2 + 1 }, (_, k) => {
    const power = (output[2 * k] ** 2 + output[2 * k + 1] ** 2) * (k === 0 || k === size / 2 ? 1 : 2) / (size * windowEnergy);
    const hz = k * binWidthHz;
    if (effectiveBand.minHz < effectiveBand.maxHz && k > 0 && hz >= effectiveBand.minHz && hz <= effectiveBand.maxHz) {
      bandPower += power;
      if (power > peakPower) { peakPower = power; peakBin = k; }
    }
    return db(power);
  });
  return { sampleRate, fftSize: size, binWidthHz, totalDbfs: db(energy / size), bandDbfs: db(bandPower),
    peakHz: peakPower > 1e-10 ? peakBin * binWidthHz : null, clippedSamples, band: effectiveBand, binsDbfs };
}
