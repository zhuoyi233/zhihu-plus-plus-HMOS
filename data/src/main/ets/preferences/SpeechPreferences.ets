export interface SpeechPreferences {
  speed: number;
  pitch: number;
  person: number;
}

export function defaultSpeechPreferences(): SpeechPreferences {
  return {
    speed: 1,
    pitch: 1,
    person: 0
  };
}

function normalizeSpeechScale(value: number): number {
  if (!Number.isFinite(value)) {
    return 1;
  }
  return Math.min(2, Math.max(0.5, Math.round(value * 10) / 10));
}

export function normalizeSpeechPreferences(value: SpeechPreferences): SpeechPreferences {
  return {
    speed: normalizeSpeechScale(value.speed),
    pitch: normalizeSpeechScale(value.pitch),
    // 0/13 均为系统内置聆小珊音色；21 需要额外下载，不在应用内静默触发下载。
    person: value.person === 13 ? 13 : 0
  };
}
