export enum VideoPlaybackPhase {
  IDLE = 'idle',
  PREPARING = 'preparing',
  READY = 'ready',
  PLAYING = 'playing',
  PAUSED = 'paused',
  COMPLETED = 'completed',
  ERROR = 'error',
  RELEASED = 'released'
}

export interface VideoPlaybackState {
  readonly phase: VideoPlaybackPhase;
  readonly generation: number;
  readonly positionMs: number;
  readonly durationMs: number;
  readonly errorMessage?: string;
}

export function initialVideoPlaybackState(): VideoPlaybackState {
  return { phase: VideoPlaybackPhase.IDLE, generation: 0, positionMs: 0, durationMs: 0 };
}

export function beginVideoPreparing(state: VideoPlaybackState): VideoPlaybackState {
  if (state.phase === VideoPlaybackPhase.RELEASED) {
    return state;
  }
  return {
    phase: VideoPlaybackPhase.PREPARING,
    generation: state.generation + 1,
    positionMs: 0,
    durationMs: 0
  };
}

export function markVideoReady(state: VideoPlaybackState, generation: number, durationMs: number): VideoPlaybackState {
  if (!isCurrentPreparing(state, generation) || !isSafeDuration(durationMs)) {
    return state;
  }
  return {
    phase: VideoPlaybackPhase.READY,
    generation: state.generation,
    positionMs: 0,
    durationMs: durationMs
  };
}

export function markVideoPlaying(state: VideoPlaybackState, generation: number): VideoPlaybackState {
  if (generation !== state.generation ||
    (state.phase !== VideoPlaybackPhase.READY && state.phase !== VideoPlaybackPhase.PAUSED)) {
    return state;
  }
  return { phase: VideoPlaybackPhase.PLAYING, generation: state.generation, positionMs: state.positionMs, durationMs: state.durationMs };
}

export function pauseVideo(state: VideoPlaybackState): VideoPlaybackState {
  if (state.phase !== VideoPlaybackPhase.PLAYING) {
    return state;
  }
  return { phase: VideoPlaybackPhase.PAUSED, generation: state.generation, positionMs: state.positionMs, durationMs: state.durationMs };
}

export function updateVideoPosition(state: VideoPlaybackState, generation: number, positionMs: number): VideoPlaybackState {
  if (generation !== state.generation || state.phase !== VideoPlaybackPhase.PLAYING ||
    !Number.isSafeInteger(positionMs) || positionMs < 0 || positionMs > state.durationMs) {
    return state;
  }
  return { phase: state.phase, generation: state.generation, positionMs: positionMs, durationMs: state.durationMs };
}

export function completeVideo(state: VideoPlaybackState, generation: number): VideoPlaybackState {
  if (generation !== state.generation || state.phase === VideoPlaybackPhase.RELEASED) {
    return state;
  }
  return {
    phase: VideoPlaybackPhase.COMPLETED,
    generation: state.generation,
    positionMs: state.durationMs,
    durationMs: state.durationMs
  };
}

export function failVideo(state: VideoPlaybackState, generation: number): VideoPlaybackState {
  if (generation !== state.generation || state.phase === VideoPlaybackPhase.RELEASED) {
    return state;
  }
  return {
    phase: VideoPlaybackPhase.ERROR,
    generation: state.generation,
    positionMs: state.positionMs,
    durationMs: state.durationMs,
    errorMessage: '视频暂时无法播放，请重试'
  };
}

export function releaseVideo(state: VideoPlaybackState): VideoPlaybackState {
  return {
    phase: VideoPlaybackPhase.RELEASED,
    generation: state.generation + 1,
    positionMs: 0,
    durationMs: 0
  };
}

function isCurrentPreparing(state: VideoPlaybackState, generation: number): boolean {
  return state.phase === VideoPlaybackPhase.PREPARING && state.generation === generation;
}

function isSafeDuration(value: number): boolean {
  return Number.isSafeInteger(value) && value > 0;
}
