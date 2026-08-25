import {
  beginVideoPreparing,
  completeVideo,
  failVideo,
  initialVideoPlaybackState,
  markVideoPlaying,
  markVideoReady,
  pauseVideo,
  releaseVideo,
  updateVideoPosition,
  VideoPlaybackPhase,
  VideoPlaybackState
} from './VideoPlaybackState';

/** 已解析、可交给播放器的媒体地址；页面本身不从内容 ID 推导或请求该地址。 */
export interface VideoPlaybackSource {
  readonly contentId: string;
  readonly url: string;
}

export interface VideoPlayerCallbacks {
  readonly onReady: (durationMs: number) => void;
  readonly onPosition: (positionMs: number) => void;
  readonly onCompleted: () => void;
  readonly onError: () => void;
}

/**
 * 平台播放器窄接口。
 *
 * 真实实现须在 API 24 设备上完成 AVPlayer 与 XComponent surface 的联合验收后注入；
 * 此接口不接受 Cookie、请求头或知乎接口凭证，避免页面层越权取得会话信息。
 */
export interface VideoPlayerAdapter {
  prepare(source: VideoPlaybackSource, callbacks: VideoPlayerCallbacks): Promise<void>;
  play(): Promise<void>;
  pause(): Promise<void>;
  seek(positionMs: number): Promise<void>;
  release(): Promise<void>;
}

/** 播放地址由数据层提供；默认实现只拒绝，绝不发起猜测性网络请求。 */
export interface VideoSourceResolver {
  resolve(contentId: string): Promise<VideoPlaybackSource | undefined>;
}

export interface VideoPlaybackPageViewState {
  readonly playback: VideoPlaybackState;
  readonly message: string;
}

export type VideoPlaybackStateListener = (state: VideoPlaybackPageViewState) => void;

export class UnavailableVideoSourceResolver implements VideoSourceResolver {
  resolve(_contentId: string): Promise<VideoPlaybackSource | undefined> {
    return Promise.resolve(undefined);
  }
}

export class UnavailableVideoPlayerAdapter implements VideoPlayerAdapter {
  prepare(_source: VideoPlaybackSource, _callbacks: VideoPlayerCallbacks): Promise<void> {
    return Promise.reject(new Error('当前设备尚未配置视频播放器'));
  }

  play(): Promise<void> {
    return Promise.reject(new Error('当前设备尚未配置视频播放器'));
  }

  pause(): Promise<void> {
    return Promise.resolve();
  }

  seek(_positionMs: number): Promise<void> {
    return Promise.resolve();
  }

  release(): Promise<void> {
    return Promise.resolve();
  }
}

/** 将异步播放器回调纳入 VideoPlaybackState 的 generation 门禁。 */
export class VideoPlaybackController {
  private playback: VideoPlaybackState = initialVideoPlaybackState();
  private active: boolean = false;
  private source: VideoPlaybackSource | undefined = undefined;
  private readonly sourceResolver: VideoSourceResolver;
  private readonly player: VideoPlayerAdapter;
  private readonly listener: VideoPlaybackStateListener;

  constructor(sourceResolver: VideoSourceResolver, player: VideoPlayerAdapter, listener: VideoPlaybackStateListener) {
    this.sourceResolver = sourceResolver;
    this.player = player;
    this.listener = listener;
  }

  activate(contentId: string): void {
    this.active = true;
    this.prepare(contentId);
  }

  deactivate(): void {
    this.active = false;
    this.source = undefined;
    this.playback = releaseVideo(this.playback);
    this.notify('播放器已释放');
    this.player.release().catch((_error: Error): void => {
    });
  }

  play(): void {
    const generation = this.playback.generation;
    if (!this.active || (this.playback.phase !== VideoPlaybackPhase.READY && this.playback.phase !== VideoPlaybackPhase.PAUSED)) {
      return;
    }
    this.player.play().then((): void => {
      if (!this.active || generation !== this.playback.generation) {
        return;
      }
      this.playback = markVideoPlaying(this.playback, generation);
      this.notify('正在播放');
    }).catch((_error: Error): void => {
      this.failCurrent(generation);
    });
  }

  pause(): void {
    const generation = this.playback.generation;
    if (!this.active || this.playback.phase !== VideoPlaybackPhase.PLAYING) {
      return;
    }
    this.player.pause().then((): void => {
      if (!this.active || generation !== this.playback.generation) {
        return;
      }
      this.playback = pauseVideo(this.playback);
      this.notify('已暂停');
    }).catch((_error: Error): void => {
      this.failCurrent(generation);
    });
  }

  seek(positionMs: number): void {
    const generation = this.playback.generation;
    if (!this.active || this.playback.phase !== VideoPlaybackPhase.PLAYING) {
      return;
    }
    this.player.seek(positionMs).then((): void => {
      if (!this.active || generation !== this.playback.generation) {
        return;
      }
      this.playback = updateVideoPosition(this.playback, generation, positionMs);
      this.notify('正在播放');
    }).catch((_error: Error): void => {
      this.failCurrent(generation);
    });
  }

  private prepare(contentId: string): void {
    this.source = undefined;
    this.playback = beginVideoPreparing(this.playback);
    const generation = this.playback.generation;
    this.notify('正在准备视频…');
    this.sourceResolver.resolve(contentId).then((source: VideoPlaybackSource | undefined): void => {
      if (!this.active || generation !== this.playback.generation) {
        return;
      }
      if (source === undefined || source.contentId !== contentId || !isSafeHttpsVideoUrl(source.url)) {
        this.failCurrent(generation, '该视频暂时没有可用的受信任播放源');
        return;
      }
      this.source = source;
      this.player.prepare(source, this.callbacksFor(generation)).catch((_error: Error): void => {
        this.failCurrent(generation);
      });
    }).catch((_error: Error): void => {
      this.failCurrent(generation, '无法获取视频播放信息，请稍后重试');
    });
  }

  private callbacksFor(generation: number): VideoPlayerCallbacks {
    return {
      onReady: (durationMs: number): void => {
        if (!this.active || generation !== this.playback.generation) {
          return;
        }
        this.playback = markVideoReady(this.playback, generation, durationMs);
        if (this.playback.phase === VideoPlaybackPhase.READY) {
          this.notify('视频已就绪');
        }
      },
      onPosition: (positionMs: number): void => {
        if (!this.active || generation !== this.playback.generation) {
          return;
        }
        this.playback = updateVideoPosition(this.playback, generation, positionMs);
        if (this.playback.phase === VideoPlaybackPhase.PLAYING) {
          this.notify('正在播放');
        }
      },
      onCompleted: (): void => {
        if (!this.active || generation !== this.playback.generation) {
          return;
        }
        this.playback = completeVideo(this.playback, generation);
        this.notify('播放完成');
      },
      onError: (): void => {
        this.failCurrent(generation);
      }
    };
  }

  private failCurrent(generation: number, message: string = '视频暂时无法播放，请重试'): void {
    if (!this.active || generation !== this.playback.generation) {
      return;
    }
    this.playback = failVideo(this.playback, generation);
    this.notify(message);
  }

  private notify(message: string): void {
    this.listener({ playback: this.playback, message: message });
  }
}

/** 首个切片只接受格式安全的 https 媒体地址；域名信任由数据层 resolver 的白名单负责。 */
export function isSafeHttpsVideoUrl(value: string): boolean {
  return /^https:\/\/[A-Za-z0-9][A-Za-z0-9.-]{0,252}(?::[0-9]{1,5})?(?:\/[A-Za-z0-9%&=._~!$'()*+,;:@/?-]*)?$/.test(value);
}
