export type Vec3 = [number, number, number];
export type Signal = 'broadband' | 'tone';
export type Observation = {
  microphones: [Vec3, Vec3];
  /** Arrival time at microphone 0 minus arrival time at microphone 1, seconds. */
  delay: number;
  sigma: number;
  frequency: number;
  signal: Signal;
};
export type AudioFrame = {
  channels: Float32Array[];
  sampleRate: number;
  /** Microphone locations in one calibrated coordinate frame, metres. */
  microphonePositions: Vec3[];
  /** Captured simultaneously by the same sample clock. Independent phones do not qualify. */
  synchronized: boolean;
};
export type MeasurementOptions = { speedOfSound?: number; signal?: Signal; toneFrequencyHz?: number };
export type Measurement = {
  observations: Observation[];
  levelDbfs: number;
  method: 'gcc-phat' | 'tone-phase';
  sampleRate: number;
  sampleCount: number;
  /** Heuristic peak prominence; not a calibrated confidence. */
  peakRatio: number;
};
export type SearchVolume = { min: Vec3; max: Vec3; step: number; speedOfSound?: number };
