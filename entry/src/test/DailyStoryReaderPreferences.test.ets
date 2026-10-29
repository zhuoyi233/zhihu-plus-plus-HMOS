import { describe, expect, it } from '@ohos/hypium';
import {
  DailyStoryReaderMode,
  DEFAULT_DAILY_STORY_READER_MODE,
  dailyStoryReaderModeDescription,
  dailyStoryReaderModeLabel,
  decodeDailyStoryReaderMode,
  isNativeDailyStoryEnabled
} from 'data';

/** 日报阅读开关：默认走原生日报页；显式选择旧路径时恢复「解析原文后直跳」。 */
export default function dailyStoryReaderPreferencesTest(): void {
  describe('dailyStoryReaderPreferencesTest', () => {
    it('defaultsToNativeDailyStoryPage', 0, () => {
      expect(DEFAULT_DAILY_STORY_READER_MODE).assertEqual(DailyStoryReaderMode.NATIVE);
      expect(isNativeDailyStoryEnabled(undefined)).assertTrue();
      expect(isNativeDailyStoryEnabled('')).assertTrue();
      expect(isNativeDailyStoryEnabled('native')).assertTrue();
      expect(isNativeDailyStoryEnabled(DailyStoryReaderMode.NATIVE)).assertTrue();
      expect(isNativeDailyStoryEnabled(DailyStoryReaderMode.LEGACY)).assertFalse();
    });

    it('fallsBackToNativeForUnknownValues', 0, () => {
      expect(decodeDailyStoryReaderMode(undefined)).assertEqual(DailyStoryReaderMode.NATIVE);
      expect(decodeDailyStoryReaderMode('')).assertEqual(DailyStoryReaderMode.NATIVE);
      expect(decodeDailyStoryReaderMode('Native')).assertEqual(DailyStoryReaderMode.NATIVE);
      expect(decodeDailyStoryReaderMode('garbage')).assertEqual(DailyStoryReaderMode.NATIVE);
      expect(decodeDailyStoryReaderMode('legacy')).assertEqual(DailyStoryReaderMode.LEGACY);
    });

    it('exposesDistinctLabelsAndDescriptions', 0, () => {
      expect(dailyStoryReaderModeLabel(DailyStoryReaderMode.NATIVE)).assertEqual('原生阅读');
      expect(dailyStoryReaderModeLabel(DailyStoryReaderMode.LEGACY)).assertEqual('跟随原文链接');
      expect(dailyStoryReaderModeDescription(DailyStoryReaderMode.NATIVE).length > 0).assertTrue();
      expect(dailyStoryReaderModeDescription(DailyStoryReaderMode.LEGACY).length > 0).assertTrue();
      expect(dailyStoryReaderModeDescription(DailyStoryReaderMode.NATIVE) ===
        dailyStoryReaderModeDescription(DailyStoryReaderMode.LEGACY)).assertFalse();
    });
  });
}
