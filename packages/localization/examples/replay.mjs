import { readFileSync } from 'node:fs';
import { measureFrame, localize } from '../dist/index.js';

if (!process.argv[2]) throw new Error('Usage: node packages/localization/examples/replay.mjs experiment.json');
const experiment = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const frame = experiment.engineInput;
if (!frame) throw new Error('Export from SoundField v0.2.0 or later');
const measurement = measureFrame({ ...frame, channels: frame.channels.map(channel => Float32Array.from(channel)) }, experiment.engineOptions);
const result = localize(measurement.observations, experiment.searchVolume);
// Deliberately never reads experiment.source, receiver, result, or rendered scene data.
console.log(JSON.stringify({ measurement, result }, null, 2));
