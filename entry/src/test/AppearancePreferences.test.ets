import { describe, expect, it } from '@ohos/hypium';
import {
  decodeFabOpacity,
  decodeFeedCardStyle,
  defaultExperiencePreferences,
  FeedCardStyle,
  normalizeAppearancePreferences,
  normalizeBottomBarItems,
  normalizeExperiencePreferences,
  ShareActionMode
} from 'data';

export default function appearancePreferencesTest(): void {
  describe('appearancePreferencesTest', () => {
    it('normalizesFloatingButtonOpacity', 0, () => {
      expect(decodeFabOpacity('80')).assertEqual(100);
      expect(decodeFabOpacity(2)).assertEqual(10);
      expect(decodeFabOpacity(57)).assertEqual(55);
      expect(decodeFabOpacity(103)).assertEqual(100);
    });

    it('acceptsOnlyKnownFeedCardStyles', 0, () => {
      expect(decodeFeedCardStyle(FeedCardStyle.CARD)).assertEqual(FeedCardStyle.CARD);
      expect(decodeFeedCardStyle(FeedCardStyle.DIVIDER)).assertEqual(FeedCardStyle.DIVIDER);
      expect(decodeFeedCardStyle('material')).assertEqual(FeedCardStyle.DIVIDER);
    });

    it('keepsFeedVisibilityPreferencesAndNormalizesValues', 0, () => {
      const value = normalizeAppearancePreferences({
        fabOpacity: 83,
        showFeedThumbnail: false,
        showRefreshFab: true,
        feedCardStyle: FeedCardStyle.CARD
      });
      expect(value.fabOpacity).assertEqual(85);
      expect(value.showFeedThumbnail).assertFalse();
      expect(value.showRefreshFab).assertTrue();
      expect(value.feedCardStyle).assertEqual(FeedCardStyle.CARD);
    });

    it('normalizesBottomNavigationSelectionAndOrder', 0, () => {
      expect(normalizeBottomBarItems('Hot,Hot,Unknown,Settings')).assertEqual('Hot,Home,Settings');
      expect(normalizeBottomBarItems('Home,Following,Hot,Daily,ReadHistory,Collections,Settings'))
        .assertEqual('Home,Following,Hot,Daily,Settings');
      expect(normalizeBottomBarItems('Collections,Daily,Settings')).assertEqual('Collections,Daily,Settings');
    });

    it('keepsExperiencePreferencesInsideUpstreamRanges', 0, () => {
      const raw = defaultExperiencePreferences();
      raw.bottomBarItems = 'ReadHistory,Collections,Settings';
      raw.startDestination = 'Home';
      raw.answerSwitchSensitivity = 9;
      raw.pageTurnPercent = 77;
      raw.shareActionMode = ShareActionMode.COPY;
      const value = normalizeExperiencePreferences(raw);
      expect(value.bottomBarItems).assertEqual('ReadHistory,Collections,Settings');
      expect(value.startDestination).assertEqual('ReadHistory');
      expect(value.answerSwitchSensitivity).assertEqual(3);
      expect(value.pageTurnPercent).assertEqual(75);
      expect(value.shareActionMode).assertEqual(ShareActionMode.COPY);
    });
  });
}
