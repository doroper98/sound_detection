import type { Observation, SearchVolume, Vec3 } from './types.js';

export const distance = (a: Vec3, b: Vec3) => Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);
export const delayAt = (point: Vec3, pair: [Vec3, Vec3], speedOfSound = 343) => (distance(point, pair[0]) - distance(point, pair[1])) / speedOfSound;

export function residualCost(point: Vec3, observations: Observation[], speedOfSound = 343) {
  let cost = 0;
  for (const observation of observations) {
    let residual = delayAt(point, observation.microphones, speedOfSound) - observation.delay;
    if (observation.signal === 'tone') residual -= Math.round(residual * observation.frequency) / observation.frequency;
    cost += (residual / observation.sigma) ** 2;
  }
  return cost;
}
export const likelihood = (point: Vec3, observations: Observation[], speedOfSound = 343) => observations.length ? Math.exp(-0.5 * residualCost(point, observations, speedOfSound)) : 0;

export function localize(observations: Observation[], volume: SearchVolume) {
  if (!observations.length) return null;
  if (volume.speedOfSound !== undefined && (!Number.isFinite(volume.speedOfSound) || volume.speedOfSound <= 0)) throw new Error('Invalid speed of sound');
  if (!Number.isFinite(volume.step) || volume.step <= 0 || ![...volume.min, ...volume.max].every(Number.isFinite)) throw new Error('Invalid search volume');
  const counts = volume.min.map((value, axis) => Math.floor((volume.max[axis] - value) / volume.step + 1e-7) + 1);
  if (counts.some(count => count < 1) || counts.reduce((a, b) => a * b, 1) > 1_000_000) throw new Error('Search volume must contain 1 to 1,000,000 grid points');
  for (const observation of observations) {
    if (!Number.isFinite(observation.delay) || !Number.isFinite(observation.sigma) || observation.sigma <= 0 || !observation.microphones.flat().every(Number.isFinite) || (observation.signal === 'tone' && (!Number.isFinite(observation.frequency) || observation.frequency <= 0))) throw new Error('Invalid observation');
  }
  const candidates: { position: Vec3; cost: number }[] = [];
  let best = { position: [0, 0, 0] as Vec3, cost: Infinity };
  for (let x = 0; x < counts[0]; x++) for (let y = 0; y < counts[1]; y++) for (let z = 0; z < counts[2]; z++) {
    const position: Vec3 = [volume.min[0] + x * volume.step, volume.min[1] + y * volume.step, volume.min[2] + z * volume.step];
    const candidate = { position, cost: residualCost(position, observations, volume.speedOfSound) };
    candidates.push(candidate); if (candidate.cost < best.cost) best = candidate;
  }
  const plausible = candidates.filter(candidate => candidate.cost <= best.cost + 3);
  let spread = 0;
  for (const candidate of plausible) spread = Math.max(spread, distance(candidate.position, best.position));
  return { ...best, candidates: plausible.length, spread, resolution: volume.step };
}

/** Evaluate an acoustic camera ray without a scene, a mesh, or a source position. */
export function rayLikelihood(origin: Vec3, direction: Vec3, observations: Observation[], ranges: number[]) {
  let best = 0;
  for (const range of ranges) {
    const point: Vec3 = [origin[0] + direction[0] * range, origin[1] + direction[1] * range, origin[2] + direction[2] * range];
    best = Math.max(best, likelihood(point, observations));
  }
  return best;
}
