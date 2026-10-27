import { describe, expect, it } from '@ohos/hypium';
import {
  AccountLayoutMode,
  ACCOUNT_MAX_CONTENT_WIDTH_VP,
  resolveAccountLayout,
  resolveSettingsLayout,
  SettingsLayoutMode,
  SETTINGS_DETAIL_MIN_WIDTH_VP,
  SETTINGS_MASTER_MIN_WIDTH_VP
} from '../main/ets/pages/AccountSettingsLayout';

export default function accountSettingsLayoutTest(): void {
  describe('accountSettingsLayoutTest', () => {
    it('switchesAccountColumnsAt720vp', 0, () => {
      expect(resolveAccountLayout(719, 1).mode).assertEqual(AccountLayoutMode.SINGLE_COLUMN);
      expect(resolveAccountLayout(720, 1).mode).assertEqual(AccountLayoutMode.TWO_COLUMN);
      expect(resolveAccountLayout(720, 1).columns).assertEqual(2);
      expect(resolveAccountLayout(0, 1).mode).assertEqual(AccountLayoutMode.SINGLE_COLUMN);
      expect(resolveAccountLayout(1138, 1).maxContentWidth).assertEqual(ACCOUNT_MAX_CONTENT_WIDTH_VP);
    });

    it('fallsBackToSingleColumnWhenFontScaleNeedsMoreWidth', 0, () => {
      // 720vp 扣除边距与列间距后每列约 336vp；字体 1.3 倍时最小列宽升到 416vp，应回落单列。
      expect(resolveAccountLayout(720, 1.3).mode).assertEqual(AccountLayoutMode.SINGLE_COLUMN);
      expect(resolveAccountLayout(1000, 1.3).mode).assertEqual(AccountLayoutMode.TWO_COLUMN);
      // 异常字体缩放被钳制，不会永久压成单列或无限抬高要求。
      expect(resolveAccountLayout(720, 0.5).mode).assertEqual(AccountLayoutMode.TWO_COLUMN);
    });

    it('switchesSettingsPaneAt900vp', 0, () => {
      const stacked = resolveSettingsLayout(899, 1);
      expect(stacked.mode).assertEqual(SettingsLayoutMode.STACKED);
      expect(stacked.masterWidth).assertEqual(0);

      const split = resolveSettingsLayout(900, 1);
      expect(split.mode).assertEqual(SettingsLayoutMode.SPLIT);
      expect(split.masterWidth >= SETTINGS_MASTER_MIN_WIDTH_VP).assertTrue();
      expect(split.detailWidth >= SETTINGS_DETAIL_MIN_WIDTH_VP).assertTrue();
      expect(split.masterWidth + split.detailWidth).assertEqual(852);
    });

    it('fallsBackToStackedSettingsWhenFontScaleNeedsMoreWidth', 0, () => {
      // 900vp 可用 852vp；字体 1.3 倍要求 (280+480)×1.3=988vp，应回落逐级导航。
      expect(resolveSettingsLayout(900, 1.3).mode).assertEqual(SettingsLayoutMode.STACKED);
      expect(resolveSettingsLayout(1200, 1.3).mode).assertEqual(SettingsLayoutMode.SPLIT);
      expect(resolveSettingsLayout(0, 1).mode).assertEqual(SettingsLayoutMode.STACKED);
    });
  });
}
