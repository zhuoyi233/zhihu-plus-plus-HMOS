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

export function takeVideoPlaybackContext(videoId: string): VideoPlaybackContext | undefined {
  const context = pendingContext;
  pendingContext = undefined;
  return context?.videoId === videoId ? context : undefined;
}
