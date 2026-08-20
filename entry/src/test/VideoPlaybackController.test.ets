import { describe, expect, it } from '@ohos/hypium';
import {
  VideoPlaybackController,
  VideoPlaybackPageViewState,
  VideoPlaybackSource,
  VideoPlayerAdapter,
  VideoPlayerCallbacks,
  VideoSourceResolver
} from '../main/ets/pages/VideoPlaybackController';
import { VideoPlaybackPhase } from '../main/ets/pages/VideoPlaybackState';

class FakeSourceResolver implements VideoSourceResolver {
  private readonly source: VideoPlaybackSource | undefined;

  constructor(source: VideoPlaybackSource | undefined) {
    this.source = source;
  }

  resolve(_contentId: string): Promise<VideoPlaybackSource | undefined> {
    return Promise.resolve(this.source);
  }
}

class FakeVideoPlayer implements VideoPlayerAdapter {
  callbacks: VideoPlayerCallbacks | undefined = undefined;
  prepareCalls: number = 0;
  playCalls: number = 0;
  pauseCalls: number = 0;
  seekCalls: number = 0;
  releaseCalls: number = 0;

  prepare(_source: VideoPlaybackSource, callbacks: VideoPlayerCallbacks): Promise<void> {
    this.prepareCalls += 1;
    this.callbacks = callbacks;
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

  seek(_positionMs: number): Promise<void> {
    this.seekCalls += 1;
    return Promise.resolve();
  }

  release(): Promise<void> {
    this.releaseCalls += 1;
    return Promise.resolve();
  }
}

export default function videoPlaybackControllerTest(): void {
  describe('videoPlaybackControllerTest', () => {
    it('rejectsMissingPlaybackSourceWithoutCallingPlayer', 0, (done: Function) => {
      const player = new FakeVideoPlayer();
      let latest: VideoPlaybackPageViewState | undefined = undefined;
      const controller = new VideoPlaybackController(new FakeSourceResolver(undefined), player,
        (state: VideoPlaybackPageViewState): void => {
          latest = state;
        });

      controller.activate('123');
      Promise.resolve().then((): void => {
        expect(player.prepareCalls).assertEqual(0);
        expect(latest?.playback.phase).assertEqual(VideoPlaybackPhase.ERROR);
        expect(latest?.message).assertEqual('该视频暂时没有可用的受信任播放源');
        done();
      });
    });

    it('dropsLateReadyCallbackAfterRelease', 0, (done: Function) => {
      const player = new FakeVideoPlayer();
      let latest: VideoPlaybackPageViewState | undefined = undefined;
      const source: VideoPlaybackSource = { contentId: '123', url: 'https://video.zhimg.com/asset.mp4' };
      const controller = new VideoPlaybackController(new FakeSourceResolver(source), player,
        (state: VideoPlaybackPageViewState): void => {
          latest = state;
        });

      controller.activate('123');
      Promise.resolve().then((): void => {
        controller.deactivate();
        player.callbacks?.onReady(1000);
        expect(player.prepareCalls).assertEqual(1);
        expect(player.releaseCalls).assertEqual(1);
        expect(latest?.playback.phase).assertEqual(VideoPlaybackPhase.RELEASED);
        done();
      });
    });

    it('routesReadyPlayPauseAndSeekThroughInjectedPlayer', 0, (done: Function) => {
      const player = new FakeVideoPlayer();
      let latest: VideoPlaybackPageViewState | undefined = undefined;
      const source: VideoPlaybackSource = { contentId: '456', url: 'https://video.zhimg.com/asset.mp4' };
      const controller = new VideoPlaybackController(new FakeSourceResolver(source), player,
        (state: VideoPlaybackPageViewState): void => {
          latest = state;
        });

      controller.activate('456');
      Promise.resolve().then((): void => {
        player.callbacks?.onReady(1000);
        controller.play();
      }).then((): void => {
        controller.seek(500);
      }).then((): void => {
        controller.pause();
      }).then((): void => {
        expect(player.playCalls).assertEqual(1);
        expect(player.seekCalls).assertEqual(1);
        expect(player.pauseCalls).assertEqual(1);
        expect(latest?.playback.phase).assertEqual(VideoPlaybackPhase.PAUSED);
        expect(latest?.playback.positionMs).assertEqual(500);
        done();
      });
    });
  });
}
