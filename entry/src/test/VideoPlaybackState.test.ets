import { describe, expect, it } from '@ohos/hypium';
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
  VideoPlaybackPhase
} from '../main/ets/pages/VideoPlaybackState';

export default function videoPlaybackStateTest(): void {
  describe('videoPlaybackStateTest', () => {
    it('transitionsPlaybackAndBoundsProgress', 0, () => {
      const preparing = beginVideoPreparing(initialVideoPlaybackState());
      const ready = markVideoReady(preparing, preparing.generation, 1000);
      const playing = markVideoPlaying(ready, ready.generation);
      const progressed = updateVideoPosition(playing, playing.generation, 500);
      const paused = pauseVideo(progressed);
      const resumed = markVideoPlaying(paused, paused.generation);
      const completed = completeVideo(resumed, resumed.generation);

      expect(ready.phase).assertEqual(VideoPlaybackPhase.READY);
      expect(progressed.positionMs).assertEqual(500);
      expect(updateVideoPosition(playing, playing.generation, 1001).positionMs).assertEqual(0);
      expect(completed.phase).assertEqual(VideoPlaybackPhase.COMPLETED);
      expect(completed.positionMs).assertEqual(1000);
    });

    it('dropsStaleCallbacksAndMakesReleaseTerminal', 0, () => {
      const first = beginVideoPreparing(initialVideoPlaybackState());
      const second = beginVideoPreparing(first);
      const staleReady = markVideoReady(second, first.generation, 1000);
      const released = releaseVideo(second);
      const staleFailure = failVideo(released, second.generation);

      expect(staleReady.phase).assertEqual(VideoPlaybackPhase.PREPARING);
      expect(released.phase).assertEqual(VideoPlaybackPhase.RELEASED);
      expect(staleFailure.phase).assertEqual(VideoPlaybackPhase.RELEASED);
      expect(releaseVideo(released).generation).assertEqual(released.generation + 1);
    });
  });
}
