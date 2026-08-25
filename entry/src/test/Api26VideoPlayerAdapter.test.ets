import { describe, expect, it } from '@ohos/hypium';
import {
  Api26NativeVideoPlayer,
  Api26NativeVideoPlayerFactory,
  Api26VideoPlayerAdapter,
  Api26VideoPlayerErrorListener,
  Api26VideoPlayerState,
  Api26VideoPlayerStateListener,
  isApi26VideoSurfaceId
} from '../main/ets/pages/Api26VideoPlayerAdapter';
import { VideoPlaybackSource, VideoPlayerCallbacks } from '../main/ets/pages/VideoPlaybackController';

class FakeApi26NativeVideoPlayer implements Api26NativeVideoPlayer {
  source: string = '';
  surfaceId: string = '';
  duration: number = 1200;
  prepareCalls: number = 0;
  releaseCalls: number = 0;
  playCalls: number = 0;
  pauseCalls: number = 0;
  seekCalls: number = 0;
  private stateListener: Api26VideoPlayerStateListener | undefined = undefined;
  private errorListener: Api26VideoPlayerErrorListener | undefined = undefined;

  setSource(url: string): void {
    this.source = url;
  }

  setSurfaceId(surfaceId: string): void {
    this.surfaceId = surfaceId;
  }

  getDuration(): number {
    return this.duration;
  }

  onStateChange(listener: Api26VideoPlayerStateListener): void {
    this.stateListener = listener;
  }

  onError(listener: Api26VideoPlayerErrorListener): void {
    this.errorListener = listener;
  }

  prepare(): Promise<void> {
    this.prepareCalls += 1;
    return Promise.resolve();
  }

  play(): Promise<void> {
    this.playCalls += 1;
    return Promise.resolve();
  }

  pause(): Promise<void> {
    this.pauseCalls += 1;
    return Promise.resolve();
  }

  seek(_positionMs: number): void {
    this.seekCalls += 1;
  }

  release(): Promise<void> {
    this.releaseCalls += 1;
    return Promise.resolve();
  }

  emitState(state: Api26VideoPlayerState): void {
    this.stateListener?.(state);
  }

  emitError(): void {
    this.errorListener?.();
  }
}

class FakeApi26NativeVideoPlayerFactory implements Api26NativeVideoPlayerFactory {
  readonly player: FakeApi26NativeVideoPlayer = new FakeApi26NativeVideoPlayer();
  createCalls: number = 0;

  create(): Promise<Api26NativeVideoPlayer> {
    this.createCalls += 1;
    return Promise.resolve(this.player);
  }
}

function fixtureSource(): VideoPlaybackSource {
  return { contentId: 'fixture-1', url: 'https://video.zhimg.com/fixture.mp4' };
}

function createCallbacks(ready: Array<number>, completed: Array<boolean>, errors: Array<boolean>): VideoPlayerCallbacks {
  return {
    onReady: (durationMs: number): void => {
      ready.push(durationMs);
    },
    onCompleted: (): void => {
      completed.push(true);
    },
    onError: (): void => {
      errors.push(true);
    }
  };
}

export default function api26VideoPlayerAdapterTest(): void {
  describe('api26VideoPlayerAdapterTest', () => {
    it('bindsTrustedFixtureToSurfaceWithoutHeaders', 0, (done: Function) => {
      const factory = new FakeApi26NativeVideoPlayerFactory();
      const adapter = new Api26VideoPlayerAdapter('fixture-surface-26', factory);
      const ready: Array<number> = [];
      const completed: Array<boolean> = [];
      const errors: Array<boolean> = [];

      adapter.prepare(fixtureSource(), createCallbacks(ready, completed, errors)).then((): void => {
        expect(factory.createCalls).assertEqual(1);
        expect(factory.player.surfaceId).assertEqual('fixture-surface-26');
        expect(factory.player.source).assertEqual('https://video.zhimg.com/fixture.mp4');
        expect(factory.player.prepareCalls).assertEqual(1);
        factory.player.emitState('prepared');
        factory.player.emitState('completed');
        expect(ready[0]).assertEqual(1200);
        expect(completed.length).assertEqual(1);
        expect(errors.length).assertEqual(0);
        done();
      });
    });

    it('dropsNativeCallbacksAfterRelease', 0, (done: Function) => {
      const factory = new FakeApi26NativeVideoPlayerFactory();
      const adapter = new Api26VideoPlayerAdapter('fixture-surface-26', factory);
      const ready: Array<number> = [];
      const completed: Array<boolean> = [];
      const errors: Array<boolean> = [];

      adapter.prepare(fixtureSource(), createCallbacks(ready, completed, errors)).then((): Promise<void> => {
        return adapter.release();
      }).then((): void => {
        factory.player.emitState('prepared');
        factory.player.emitError();
        expect(factory.player.releaseCalls).assertEqual(1);
        expect(ready.length).assertEqual(0);
        expect(completed.length).assertEqual(0);
        expect(errors.length).assertEqual(0);
        done();
      });
    });

    it('rejectsMissingSurfaceBeforeCreatingNativePlayer', 0, (done: Function) => {
      const factory = new FakeApi26NativeVideoPlayerFactory();
      const adapter = new Api26VideoPlayerAdapter('', factory);
      const ready: Array<number> = [];
      const completed: Array<boolean> = [];
      const errors: Array<boolean> = [];

      adapter.prepare(fixtureSource(), createCallbacks(ready, completed, errors)).catch((_error: Error): void => {
        expect(factory.createCalls).assertEqual(0);
        expect(isApi26VideoSurfaceId('fixture-surface-26')).assertTrue();
        expect(isApi26VideoSurfaceId('bad\nvalue')).assertFalse();
        done();
      });
    });
  });
}
