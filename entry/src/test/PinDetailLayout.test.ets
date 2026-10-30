import { describe, expect, it } from '@ohos/hypium';
import {
  pinBottomBarSideInsetVp,
  pinBottomContentInsetVp,
  pinCompactBottomActions,
  pinTopContentInsetVp
} from '../main/ets/pages/PinDetailLayout';

export default function pinDetailLayoutTest(): void {
  describe('pinDetailLayoutTest', () => {
    it('keepsMinimumTopInsetWhenStatusBarIsMissingOrAbnormal', 0, () => {
      expect(pinTopContentInsetVp(0)).assertEqual(94);
      expect(pinTopContentInsetVp(-12)).assertEqual(94);
      expect(pinTopContentInsetVp(Number.NaN)).assertEqual(94);
      expect(pinTopContentInsetVp(Number.POSITIVE_INFINITY)).assertEqual(94);
    });

    it('addsStatusBarHeightOnTopOfTitleBarContentHeight', 0, () => {
      // 24 + 56 = 80 低于 94 下限；47 + 56 = 103 起才由状态栏决定。
      expect(pinTopContentInsetVp(24)).assertEqual(94);
      expect(pinTopContentInsetVp(47)).assertEqual(103);
      expect(pinTopContentInsetVp(120)).assertEqual(176);
    });

    it('keepsBottomInsetAboveMeasuredActionBarWithoutDoubleSafeArea', 0, () => {
      // 未测得底栏高度时沿用共享兜底，避免首帧正文尾部被胶囊压住。
      expect(pinBottomContentInsetVp(0)).assertEqual(100);
      expect(pinBottomContentInsetVp(Number.NaN)).assertEqual(100);
      // 64 + 16 = 80 正好触底；82 是"48 内容 + 34 手势区"这一档的真实高度。
      expect(pinBottomContentInsetVp(64)).assertEqual(80);
      expect(pinBottomContentInsetVp(82)).assertEqual(98);
    });

    it('alignsBottomBarSideInsetWithReadingColumn', 0, () => {
      expect(pinBottomBarSideInsetVp(320)).assertEqual(16);
      expect(pinBottomBarSideInsetVp(360)).assertEqual(20);
      // 宽度未知（首帧 0）时退到常规留边，不产生 0 边距的满宽胶囊。
      expect(pinBottomBarSideInsetVp(0)).assertEqual(20);
      expect(pinBottomBarSideInsetVp(Number.NaN)).assertEqual(20);
      // 宽窗按 720vp 阅读列居中：(1200 - 720) / 2。
      expect(pinBottomBarSideInsetVp(1200)).assertEqual(240);
    });

    it('collapsesVisibleCountsOnNarrowWindowOrLargeFontOnly', 0, () => {
      expect(pinCompactBottomActions(320, 1)).assertTrue();
      expect(pinCompactBottomActions(339, 1)).assertTrue();
      expect(pinCompactBottomActions(340, 1)).assertFalse();
      expect(pinCompactBottomActions(440, 1)).assertFalse();
      expect(pinCompactBottomActions(440, 1.3)).assertTrue();
      expect(pinCompactBottomActions(1200, 1)).assertFalse();
      expect(pinCompactBottomActions(0, Number.NaN)).assertFalse();
    });
  });
}
