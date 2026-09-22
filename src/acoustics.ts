export type Vec3 = [number, number, number];
export type Signal = 'broadband' | 'tone';
export type Source = { position: Vec3; db: number; frequency: number; signal: Signal };
export type Receiver = { position: Vec3; yaw: number; pitch: number; count: 1 | 2; spacing: number };
export type Observation = { microphones: [Vec3, Vec3]; delay: number; sigma: number; frequency: number; signal: Signal };
export const SPEED_OF_SOUND = 343;
export const ROOM = { width: 8, depth: 7, height: 3.2 };
export const INITIAL_SOURCE: Source = { position: [-1.4, 1.1, -1.5], db: 72, frequency: 1000, signal: 'broadband' };
export const INITIAL_RECEIVER: Receiver = { position: [0.7, 1.3, 2.5], yaw: -0.45, pitch: -0.04, count: 2, spacing: 0.12 };
export const DEVICES = [
  { id: 'iphone', name: 'iPhone 15 Pro', spacing: 0.12, caption: '스마트폰 · 가상 간격 12 cm' },
  { id: 'ipad', name: 'iPad Pro 11″', spacing: 0.2, caption: '태블릿 · 가상 간격 20 cm' },
  { id: 'galaxy', name: 'Galaxy S24', spacing: 0.13, caption: '스마트폰 · 가상 간격 13 cm' },
  { id: 'custom', name: '사용자 정의 배열', spacing: 0.5, caption: '실험용 · 자유로운 마이크 간격' },
];
export const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value));
export const distance = (a: Vec3, b: Vec3) => Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);
export const wavelength = (frequency: number) => SPEED_OF_SOUND / frequency;
export const pressureAt = (source: Source, point: Vec3) => source.db - 20 * Math.log10(Math.max(0.1, distance(source.position, point)));

export function microphones(receiver: Receiver): [Vec3, Vec3] {
  const { yaw, pitch, spacing, position } = receiver;
  const axis = [Math.cos(yaw) * Math.cos(pitch), Math.sin(pitch), -Math.sin(yaw) * Math.cos(pitch)];
  return [-1, 1].map(sign => position.map((v, i) => v + sign * axis[i] * spacing / 2) as Vec3) as [Vec3, Vec3];
}
export const delayAt = (point: Vec3, pair: [Vec3, Vec3]) => (distance(point, pair[0]) - distance(point, pair[1])) / SPEED_OF_SOUND;

export function observe(source: Source, receiver: Receiver): Observation {
  const pair = microphones(receiver);
  const snr = clamp(pressureAt(source, receiver.position) - 35, 0, 40);
  // Illustrative timing uncertainty, not a measured device calibration.
  const sigma = Math.max(5e-6, 1 / (2 * Math.PI * source.frequency * Math.sqrt(10 ** (snr / 10))));
  return { microphones: pair, delay: delayAt(source.position, pair), sigma, frequency: source.frequency, signal: source.signal };
}

export function residualCost(point: Vec3, observations: Observation[]): number {
  let cost = 0;
  for (const observation of observations) {
    let residual = delayAt(point, observation.microphones) - observation.delay;
    if (observation.signal === 'tone') residual -= Math.round(residual * observation.frequency) / observation.frequency;
    cost += (residual / observation.sigma) ** 2;
  }
  return cost;
}

export const likelihood = (point: Vec3, observations: Observation[]) => observations.length ? Math.exp(-0.5 * residualCost(point, observations)) : 0;

export function isDistinctObservation(next: Observation, saved: Observation[]) {
  return saved.every(previous => distance(next.microphones[0], previous.microphones[0]) + distance(next.microphones[1], previous.microphones[1]) > 0.08);
}

export function estimate(observations: Observation[]) {
  if (!observations.length) return null;
  const candidates: { position: Vec3; cost: number }[] = [];
  let best = { position: [0, 0, 0] as Vec3, cost: Infinity };
  // A 20 cm grid deliberately reports resolution; no access to source ground truth.
  for (let x = -3.8; x <= 3.81; x += 0.2) {
    for (let y = 0.1; y <= 3.11; y += 0.2) {
      for (let z = -3.3; z <= 3.31; z += 0.2) {
        const position: Vec3 = [x, y, z];
        const cost = residualCost(position, observations);
        const candidate = { position, cost };
        candidates.push(candidate);
        if (cost < best.cost) best = candidate;
      }
    }
  }
  const plausible = candidates.filter(candidate => candidate.cost <= best.cost + 3);
  const spread = Math.max(...plausible.map(candidate => distance(candidate.position, best.position)));
  return { ...best, candidates: plausible.length, spread, resolution: 0.2 };
}

export function heatColor(value: number): [number, number, number] {
  const stops = [[43, 80, 224], [28, 175, 234], [49, 221, 157], [224, 230, 56], [255, 157, 35], [249, 48, 57]];
  const t = clamp(value, 0, 1) * (stops.length - 1);
  const a = Math.min(stops.length - 2, Math.floor(t));
  return stops[a].map((v, i) => Math.round(v + (stops[a + 1][i] - v) * (t - a))) as [number, number, number];
}
