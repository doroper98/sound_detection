export type ChannelStats = { levelDbfs: number | null; peak: number; active: boolean };
export type PairStats = { channels: [number, number]; correlation: number | null; relativeDifference: number | null; duplicateSuspected: boolean };
export type FrameStats = { channels: ChannelStats[]; pairs: PairStats[] };
export type RequestKind = 4 | 2 | 'default';
export type CaptureSettings = Pick<MediaTrackSettings, 'channelCount' | 'sampleRate' | 'sampleSize' | 'echoCancellation' | 'noiseSuppression' | 'autoGainControl'>;
export type ProbeAttempt = {
  requested: RequestKind;
  status: 'captured' | 'rejected' | 'error';
  settings?: CaptureSettings;
  capabilities?: { channelCount?: ULongRange; sampleRate?: ULongRange };
  observedChannelCounts: number[];
  frameCount: number;
  sampleCount: number;
  pcmSampleRate?: number;
  latest?: FrameStats;
  activeChannels: number[];
  duplicatePairs: string[];
  error?: { name: string; constraint?: string };
};

/** Signal diagnostics only; dissimilar waveforms do not prove independent sensors. */
export function analyzeChannels(channels: readonly Float32Array[]): FrameStats {
  const size = channels[0]?.length ?? 0;
  if (!size || !channels.every(channel => channel.length === size && channel.every(Number.isFinite))) throw new Error('Invalid PCM frame');
  const stats = channels.map(channel => {
    let energy = 0; let peak = 0;
    for (const x of channel) { energy += x * x; peak = Math.max(peak, Math.abs(x)); }
    const power = energy / size;
    return { levelDbfs: power > 0 ? 10 * Math.log10(power) : null, peak, active: power > 1e-10 };
  });
  const pairs: PairStats[] = [];
  for (let a = 0; a < channels.length; a++) for (let b = a + 1; b < channels.length; b++) {
    let aa = 0; let bb = 0; let ab = 0; let sa = 0; let sb = 0; let difference = 0;
    for (let i = 0; i < size; i++) {
      const x = channels[a][i]; const y = channels[b][i];
      aa += x * x; bb += y * y; ab += x * y; sa += x; sb += y; difference += (x - y) ** 2;
    }
    const denominator = Math.sqrt(Math.max(0, aa - sa * sa / size) * Math.max(0, bb - sb * sb / size));
    const active = stats[a].active && stats[b].active;
    const relativeDifference = active ? Math.sqrt(difference / Math.max(1e-30, (aa + bb) / 2)) : null;
    pairs.push({ channels: [a + 1, b + 1], correlation: active && denominator > 1e-20 ? Math.max(-1, Math.min(1, (ab - sa * sb / size) / denominator)) : null, relativeDifference, duplicateSuspected: relativeDifference !== null && relativeDifference < 1e-5 });
  }
  return { channels: stats, pairs };
}

export function probeVerdict(attempts: ProbeAttempt[]) {
  const captured = attempts.filter(a => a.status === 'captured' && a.frameCount >= 4);
  const four = captured.find(a => a.observedChannelCounts.length === 1 && a.observedChannelCounts[0] === 4);
  if (four) {
    if (four.settings?.channelCount !== undefined && four.settings.channelCount !== 4) return { title: '설정과 PCM 채널 수 불일치', detail: '4채널 형태의 PCM을 받았지만 설정값과 다릅니다. 추가 검증이 필요합니다.' };
    if (four.activeChannels.length < 4) return { title: '4채널 형식 수신 · 신호 확인 필요', detail: '모든 채널에서 충분한 신호가 확인되지 않았습니다. 무음은 마이크 고장의 증거가 아닙니다.' };
    if (four.duplicatePairs.length) return { title: '4채널 형식 수신 · 중복 신호 의심', detail: `동일 파형 의심 쌍: ${four.duplicatePairs.join(', ')}. 독립 마이크 4개 사용으로 판정하지 않습니다.` };
    return { title: '4채널 PCM 수신 확인', detail: '이 브라우저 경로에서 4채널을 받았습니다. 물리 마이크의 독립성·동기화·위치 정확도는 아직 미검증입니다.' };
  }
  if (captured.length) return { title: '4채널 안정 수신 미확인', detail: `Web Audio PCM: ${[...new Set(captured.flatMap(a => a.observedChannelCounts))].sort().join(', ')}채널. 현재 기기·브라우저·입력 경로의 결과이며 모든 Safari에 대한 판정은 아닙니다.` };
  return { title: '채널 판정에 필요한 데이터 없음', detail: '권한과 입력 장치를 확인하고 다시 검사해 주세요. 요청 거절만으로 물리 마이크 수를 알 수는 없습니다.' };
}

export const requestLabel = (kind: RequestKind) => kind === 'default' ? '기본 입력' : `${kind}채널 필수 요청`;
