import { VideoRepository } from 'data';
import { VideoPlaybackSource, VideoSourceResolver } from './VideoPlaybackController';
import { VideoPlaybackContext } from './VideoPlaybackHandoff';

export class RepositoryVideoSourceResolver implements VideoSourceResolver {
  private readonly repository: VideoRepository;
  private readonly context: VideoPlaybackContext;

  constructor(repository: VideoRepository, context: VideoPlaybackContext) {
    this.repository = repository;
    this.context = context;
  }

  resolve(contentId: string): Promise<VideoPlaybackSource | undefined> {
    if (contentId !== this.context.videoId) {
      return Promise.resolve(undefined);
    }
    return this.repository.resolvePlaybackUrl({
      videoId: this.context.videoId,
      contentId: this.context.contentId,
      contentType: this.context.contentType
    }).then((url: string | undefined): VideoPlaybackSource | undefined => {
      return url === undefined ? undefined : { contentId: contentId, url: url };
    });
  }
}
