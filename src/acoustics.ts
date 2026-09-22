import { localize, type SearchVolume } from '../packages/localization/src/index';
import { distance } from '../packages/localization/src/solver';
import type { Vec3, Signal, Observation } from '../packages/localization/src/types';
export { delayAt, distance, likelihood, residualCost } from '../packages/localization/src/solver';
export type { Vec3, Signal, Observation } from '../packages/localization/src/types';
export type Source = { position: Vec3; db: number; frequency: number; signal: Signal };
export type Receiver = { position: Vec3; yaw: number; pitch: number; count: 1 | 2; spacing: number; layout: 'horizontal' | 'vertical' };
export const SPEED_OF_SOUND = 343;
export const ROOM = { width: 8, depth: 7, height: 3.2 };
export const INITIAL_SOURCE: Source = { position: [-1.4, 1.1, -1.5], db: 72, frequency: 1000, signal: 'broadband' };
export const INITIAL_RECEIVER: Receiver = { position: [0.7, 1.3, 2.5], yaw: -0.45, pitch: -0.04, count: 2, spacing: 0.12, layout: 'horizontal' };
export const DEVICES = [
  { id: 'iphone', name: 'iPhone 15 Pro', spacing: 0.12, caption: '스마트폰 · 가상 간격 12 cm' },
  { id: 'ipad', name: 'iPad Pro 11″', spacing: 0.2, caption: '태블릿 · 가상 간격 20 cm' },
  { id: 'galaxy', name: 'Galaxy S24', spacing: 0.13, caption: '스마트폰 · 가상 간격 13 cm' },
  { id: 'custom', name: '사용자 정의 배열', spacing: 0.5, caption: '실험용 · 자유로운 마이크 간격' },
];
export const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value));
export const wavelength = (frequency: number) => SPEED_OF_SOUND / frequency;
export const pressureAt = (source: Source, point: Vec3) => source.db - 20 * Math.log10(Math.max(0.1, distance(source.position, point)));

export function microphones(receiver: Receiver): [Vec3, Vec3] {
  const { yaw, pitch, spacing, position } = receiver;
  const axis = receiver.layout === 'horizontal'
    ? [Math.cos(yaw), 0, Math.sin(yaw)]
    : [-Math.sin(yaw) * Math.sin(pitch), Math.cos(pitch), Math.cos(yaw) * Math.sin(pitch)];
  return [-1, 1].map(sign => position.map((v, i) => v + sign * axis[i] * spacing / 2) as Vec3) as [Vec3, Vec3];
}


export function isDistinctObservation(next: Observation, saved: Observation[]) {
  return saved.every(previous => distance(next.microphones[0], previous.microphones[0]) + distance(next.microphones[1], previous.microphones[1]) > 0.08);
}

export const SEARCH_VOLUME: SearchVolume = { min: [-3.8, 0.1, -3.3], max: [3.8, 3.1, 3.3], step: 0.2 };
export const estimate = (observations: Observation[]) => localize(observations, SEARCH_VOLUME);

export function heatColor(value: number): [number, number, number] {
  const stops = [[43, 80, 224], [28, 175, 234], [49, 221, 157], [224, 230, 56], [255, 157, 35], [249, 48, 57]];
  const t = clamp(Number.isFinite(value) ? value : 0, 0, 1) * (stops.length - 1);
  const a = Math.min(stops.length - 2, Math.floor(t));
  return stops[a].map((v, i) => Math.round(v + (stops[a + 1][i] - v) * (t - a))) as [number, number, number];
}
