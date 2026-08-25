import media from '@ohos.multimedia.media';
import { VideoPlaybackSource, VideoPlayerAdapter, VideoPlayerCallbacks } from './VideoPlaybackController';

/** API 26 平台层实际需要观察的 AVPlayer 状态。 */
export type Api26VideoPlayerState = 'prepared' | 'completed';

export type Api26VideoPlayerStateListener = (state: Api26VideoPlayerState) => void;
export type Api26VideoPlayerErrorListener = () => void;

/**
 * 对 AVPlayer 的窄封装，便于在 Hypium 中验证资源释放和 XComponent 绑定。
 * 该接口不提供 Header、Cookie 或任意网络选项；媒体 URL 必须已由数据层解析并校验。
 */
export interface Api26NativeVideoPlayer {
  setSource(url: string): void;
  setSurfaceId(surfaceId: string): void;
  getDuration(): number;
  onStateChange(listener: Api26VideoPlayerStateListener): void;
  onError(listener: Api26VideoPlayerErrorListener): void;
  prepare(): Promise<void>;
  play(): Promise<void>;
  pause(): Promise<void>;
  seek(positionMs: number): void;
  release(): Promise<void>;
}

export interface Api26NativeVideoPlayerFactory {
  create(): Promise<Api26NativeVideoPlayer>;
}

/** 直接使用 API 26 Media Kit，不通过媒体源 Header API。 */
export class HarmonyApi26NativeVideoPlayer implements Api26NativeVideoPlayer {
  private readonly player: media.AVPlayer;

  constructor(player: media.AVPlayer) {
    this.player = player;
  }

  setSource(url: string): void {
    this.player.url = url;
  }

  setSurfaceId(surfaceId: string): void {
    this.player.surfaceId = surfaceId;
  }

  getDuration(): number {
    return this.player.duration;
  }

  onStateChange(listener: Api26VideoPlayerStateListener): void {
    this.player.on('stateChange', (state: media.AVPlayerState): void => {
      if (state === 'prepared' || state === 'completed') {
        listener(state);
      }
    });
  }

  onError(listener: Api26VideoPlayerErrorListener): void {
    this.player.on('error', (): void => {
      listener();
    });
  }

  prepare(): Promise<void> {
    return this.player.prepare();
  }

  play(): Promise<void> {
    return this.player.play();
  }

  pause(): Promise<void> {
    return this.player.pause();
  }

  seek(positionMs: number): void {
    this.player.seek(positionMs);
  }

  release(): Promise<void> {
    return this.player.release();
  }
}

export class HarmonyApi26NativeVideoPlayerFactory implements Api26NativeVideoPlayerFactory {
  create(): Promise<Api26NativeVideoPlayer> {
    return media.createAVPlayer().then((player: media.AVPlayer): Api26NativeVideoPlayer => {
      return new HarmonyApi26NativeVideoPlayer(player);
    });
  }
}

/**
 * 将 API 26 AVPlayer 绑定至由 XComponent 提供的 surface。
 *
 * 播放器每次 prepare 仅创建一个实例；release 会使尚未返回的 create 结果立即释放，
 * 避免页面离开后迟到的系统回调重新占用 surface。
 */
export class Api26VideoPlayerAdapter implements VideoPlayerAdapter {
  private readonly surfaceId: string;
  private readonly factory: Api26NativeVideoPlayerFactory;
  private nativePlayer: Api26NativeVideoPlayer | undefined = undefined;
  private callbacks: VideoPlayerCallbacks | undefined = undefined;
  private operation: number = 0;
  private released: boolean = false;

  constructor(surfaceId: string, factory: Api26NativeVideoPlayerFactory = new HarmonyApi26NativeVideoPlayerFactory()) {
    this.surfaceId = surfaceId;
    this.factory = factory;
  }

  prepare(source: VideoPlaybackSource, callbacks: VideoPlayerCallbacks): Promise<void> {
    if (!isApi26VideoSurfaceId(this.surfaceId)) {
      return Promise.reject(new Error('视频画面尚未准备完成'));
    }
    const currentOperation = this.nextOperation();
    this.callbacks = callbacks;
    return this.factory.create().then((player: Api26NativeVideoPlayer): Promise<void> => {
      if (!this.isCurrent(currentOperation)) {
        return player.release().then((): Promise<void> => {
          return Promise.reject(new Error('视频播放器已释放'));
        }, (_error: Error): Promise<void> => {
          return Promise.reject(new Error('视频播放器已释放'));
        });
      }
      this.nativePlayer = player;
      player.onStateChange((state: Api26VideoPlayerState): void => {
        this.onNativeState(currentOperation, state);
      });
      player.onError((): void => {
        this.onNativeError(currentOperation);
      });
      player.setSurfaceId(this.surfaceId);
      player.setSource(source.url);
      return player.prepare();
    }).catch((error: Error): Promise<void> => {
      if (this.isCurrent(currentOperation)) {
        this.nativePlayer = undefined;
        this.callbacks?.onError();
      }
      return Promise.reject(new Error(error.message));
    });
  }

  play(): Promise<void> {
    if (this.nativePlayer === undefined || this.released) {
      return Promise.reject(new Error('视频播放器尚未就绪'));
    }
    return this.nativePlayer.play();
  }

  pause(): Promise<void> {
    if (this.nativePlayer === undefined || this.released) {
      return Promise.resolve();
    }
    return this.nativePlayer.pause();
  }

  seek(positionMs: number): Promise<void> {
    if (this.nativePlayer === undefined || this.released) {
      return Promise.resolve();
    }
    try {
      this.nativePlayer.seek(positionMs);
      return Promise.resolve();
    } catch (_error) {
      return Promise.reject(new Error('视频进度调整失败'));
    }
  }

  release(): Promise<void> {
    this.nextOperation();
    this.released = true;
    this.callbacks = undefined;
    const player = this.nativePlayer;
    this.nativePlayer = undefined;
    if (player === undefined) {
      return Promise.resolve();
    }
    return player.release().then((): void => {
    }, (_error: Error): void => {
    });
  }

  private onNativeState(operation: number, state: Api26VideoPlayerState): void {
    if (!this.isCurrent(operation)) {
      return;
    }
    if (state === 'prepared') {
      const durationMs = this.nativePlayer?.getDuration() ?? 0;
      if (Number.isSafeInteger(durationMs) && durationMs > 0) {
        this.callbacks?.onReady(durationMs);
      } else {
        this.callbacks?.onError();
      }
      return;
    }
    this.callbacks?.onCompleted();
  }

  private onNativeError(operation: number): void {
    if (this.isCurrent(operation)) {
      this.callbacks?.onError();
    }
  }

  private nextOperation(): number {
    this.operation += 1;
    this.released = false;
    return this.operation;
  }

  private isCurrent(operation: number): boolean {
    return !this.released && operation === this.operation;
  }
}

/** XComponent 的 surface 标识由系统生成；仅拒绝空白和控制字符。 */
export function isApi26VideoSurfaceId(value: string): boolean {
  return value.length > 0 && value.length <= 4096 && !/[\u0000-\u001F\u007F]/.test(value);
}
