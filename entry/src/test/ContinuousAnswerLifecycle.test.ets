import { describe, expect, it } from '@ohos/hypium';
import { VideoPlaybackRequest, VideoRepository } from 'data';
import {
  ContinuousAnswerTitleState, continuousAnswerRouteId, continuousAnswerTitle, updateContinuousAnswerTitle
} from '../main/ets/pages/ContinuousAnswerRouteState';
import { RepositoryVideoSourceResolver } from '../main/ets/pages/RepositoryVideoSourceResolver';
import { stageAnswerVideoPlayback, takeVideoPlaybackContext } from '../main/ets/pages/VideoPlaybackHandoff';

class RecordingVideoRepository implements VideoRepository {
  lastRequest?: VideoPlaybackRequest;
  resolvePlaybackUrl(request: VideoPlaybackRequest): Promise<string | undefined> {
    this.lastRequest = request;
    return Promise.resolve('https://vdn.vzuu.com/video.mp4');
  }
  cancel(): void {}
}

export default function continuousAnswerLifecycleTest(): void {
  describe('continuousAnswerLifecycleTest', () => {
    it('keepsParentTitleWhenNestedRouteIsRemoved', 0, () => {
      const parent = continuousAnswerRouteId('1', '11', 'default');
      const child = continuousAnswerRouteId('1', '12', 'default');
      let states: Array<ContinuousAnswerTitleState> = [];
      states = updateContinuousAnswerTitle(states, parent, '原问题');
      states = updateContinuousAnswerTitle(states, child, '子页问题');
      states = updateContinuousAnswerTitle(states, child);
      expect(continuousAnswerTitle(states, parent)).assertEqual('原问题');
      expect(continuousAnswerTitle(states, child)).assertEqual('');
    });

    it('lateHiddenTitleCannotReplaceTheActiveRouteTitle', 0, () => {
      const hidden = continuousAnswerRouteId('1', '11', 'default');
      const visible = continuousAnswerRouteId('2', '22', 'updated');
      let states: Array<ContinuousAnswerTitleState> = [];
      states = updateContinuousAnswerTitle(states, visible, '当前问题');
      states = updateContinuousAnswerTitle(states, hidden, '旧请求迟到');
      expect(continuousAnswerTitle(states, visible)).assertEqual('当前问题');
      expect(continuousAnswerTitle(states, hidden)).assertEqual('旧请求迟到');
      expect(visible === hidden).assertFalse();
      expect(continuousAnswerRouteId('1', '11', 'updated') === hidden).assertFalse();
    });

    it('passesTheClickedAnswerThroughTheVideoResolver', 0, async () => {
      stageAnswerVideoPlayback('222', '333');
      const context = takeVideoPlaybackContext('333');
      expect(context !== undefined).assertTrue();
      if (context === undefined) { return; }
      const repository = new RecordingVideoRepository();
      const source = await new RepositoryVideoSourceResolver(repository, context).resolve('333');
      expect(repository.lastRequest?.contentId).assertEqual('222');
      expect(repository.lastRequest?.contentType).assertEqual('answer');
      expect(repository.lastRequest?.videoId).assertEqual('333');
      expect(source?.url).assertEqual('https://vdn.vzuu.com/video.mp4');
      expect(takeVideoPlaybackContext('333')).assertUndefined();
    });

    it('doesNotReuseAnotherVideosPendingContext', 0, () => {
      stageAnswerVideoPlayback('222', '333');
      expect(takeVideoPlaybackContext('444')).assertUndefined();
      expect(takeVideoPlaybackContext('333')).assertUndefined();
    });
  });
}
