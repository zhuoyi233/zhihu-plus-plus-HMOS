import { describe, expect, it } from '@ohos/hypium';
import {
  BackgroundRoute,
  decideBackgroundRoute,
  ZhihuWorkload
} from '../main/ets/background/BackgroundWorkPolicy';

export default function backgroundWorkPolicyTest(): void {
  describe('backgroundWorkPolicyTest', () => {
    it('routesSupportedWorkloadsWithoutAllowingFeedCrawl', 0, () => {
      expect(decideBackgroundRoute(ZhihuWorkload.USER_REFRESH).route)
        .assertEqual(BackgroundRoute.FOREGROUND_ONLY);
      expect(decideBackgroundRoute(ZhihuWorkload.FINISH_IN_FLIGHT_REQUEST).route)
        .assertEqual(BackgroundRoute.TRANSIENT_FINISH);
      expect(decideBackgroundRoute(ZhihuWorkload.NON_URGENT_MAINTENANCE).route)
        .assertEqual(BackgroundRoute.DEFERRED_SYSTEM);
      expect(decideBackgroundRoute(ZhihuWorkload.AUDIO_PLAYBACK).route)
        .assertEqual(BackgroundRoute.CONTINUOUS_USER_VISIBLE);
      expect(decideBackgroundRoute(ZhihuWorkload.AUDIO_PLAYBACK).requiresVisibleNotification)
        .assertTrue();
      expect(decideBackgroundRoute(ZhihuWorkload.PERIODIC_FEED_CRAWL).route)
        .assertEqual(BackgroundRoute.NOT_SUPPORTED);
    });
  });
}
