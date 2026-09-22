import { useEffect, useRef, useState } from 'react';
import type { Source } from './acoustics';

export function useAudio(source: Source, running: boolean) {
  const [enabled, setEnabled] = useState(false);
  const [error, setError] = useState('');
  const audio = useRef<{ context: AudioContext; oscillator: OscillatorNode; gain: GainNode } | null>(null);
  useEffect(() => () => { void audio.current?.context.close(); }, []);
  useEffect(() => {
    if (!audio.current) return;
    const { context, oscillator, gain } = audio.current;
    oscillator.frequency.setTargetAtTime(source.frequency, context.currentTime, 0.04);
    gain.gain.setTargetAtTime(enabled && running ? 0.035 * 10 ** ((source.db - 90) / 40) : 0, context.currentTime, 0.04);
  }, [source.frequency, source.db, enabled, running]);
  const toggle = async () => {
    try {
      if (!audio.current) {
        const context = new AudioContext(); const oscillator = context.createOscillator(); const gain = context.createGain();
        oscillator.connect(gain); gain.connect(context.destination); gain.gain.value = 0; oscillator.start();
        audio.current = { context, oscillator, gain };
      }
      await audio.current.context.resume(); setEnabled(value => !value); setError('');
    } catch { setError('이 브라우저에서 소리를 재생할 수 없습니다.'); }
  };
  return { enabled, error, toggle, stop: () => setEnabled(false) };
}
