import { VideoParentContentType } from 'data';

export interface VideoPlaybackContext {
  readonly videoId: string;
  readonly contentId: string;
  readonly contentType: VideoParentContentType;
}

let pendingContext: VideoPlaybackContext | undefined = undefined;

export function stageVideoPlaybackContext(context: VideoPlaybackContext): void {
  pendingContext = context;
}

/** 连续阅读必须绑定触发视频的回答，而非当前滚动焦点或路由种子。 */
export function stageAnswerVideoPlayback(answerId: string, videoId: string): void {
  stageVideoPlaybackContext({ videoId: videoId, contentId: answerId, contentType: 'answer' });
}

export function takeVideoPlaybackContext(videoId: string): VideoPlaybackContext | undefined {
  const context = pendingContext;
  pendingContext = undefined;
  return context?.videoId === videoId ? context : undefined;
}
