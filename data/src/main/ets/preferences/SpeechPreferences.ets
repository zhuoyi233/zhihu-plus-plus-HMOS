export interface SpeechPreferences {
  speed: number;
  pitch: number;
  person: number;
  language: string;
  style: string;
}

export function defaultSpeechPreferences(): SpeechPreferences {
  return {
    speed: 1,
    pitch: 1,
    person: 13,
    language: 'zh-CN',
    style: 'interaction-broadcast'
  };
}

function normalizeSpeechScale(value: number): number {
  if (!Number.isFinite(value)) {
    return 1;
  }
  return Math.min(2, Math.max(0.5, Math.round(value * 10) / 10));
}

export function normalizeSpeechPreferences(value: SpeechPreferences): SpeechPreferences {
  const rawLanguage = value.language.trim();
  const language = rawLanguage === 'zh_CN' ? 'zh-CN' : (rawLanguage === 'en_US' ? 'en-US' : rawLanguage);
  const style = value.style.trim();
  return {
    speed: normalizeSpeechScale(value.speed),
    pitch: normalizeSpeechScale(value.pitch),
    // 音色由 Core Speech Kit 动态返回，不再把可选 person 限制在内置音色中。
    person: value.person === 0 ? 13 :
      (Number.isFinite(value.person) && value.person >= 0 ? Math.round(value.person) : 13),
    language: language.length > 0 && language.length <= 16 ? language : 'zh-CN',
    style: style.length > 0 && style.length <= 64 ? style : 'interaction-broadcast'
  };
}
