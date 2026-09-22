/** Display weighting only. No scene/source input and no changes to localization. */
export const HEAT_FLOOR_DBFS = -85;
export const HEAT_CEILING_DBFS = -30;

export function pcmStats(channels: readonly Float32Array[]) {
  let energy = 0; let count = 0; let clipped = 0;
  for (const channel of channels) for (const sample of channel) {
    energy += sample * sample; count++;
    if (Math.abs(sample) >= 1) clipped++;
  }
  return { levelDbfs: energy > 0 && count > 0 ? 10 * Math.log10(energy / count) : -Infinity, clipped: clipped > 0 };
}

export function heatIntensity(response: number, levelDbfs: number) {
  if (!(response > 0) || !Number.isFinite(levelDbfs)) return 0;
  // This is a visualization score, not a reconstructed SPL field or confidence.
  const weightedLevel = levelDbfs + 10 * Math.log10(Math.min(1, response));
  return Math.max(0, Math.min(1, (weightedLevel - HEAT_FLOOR_DBFS) / (HEAT_CEILING_DBFS - HEAT_FLOOR_DBFS)));
}
