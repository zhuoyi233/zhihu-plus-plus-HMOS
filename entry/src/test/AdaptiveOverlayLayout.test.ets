import { describe, expect, it } from '@ohos/hypium';
import { adaptiveOverlayWidth, isWideOverlayContainer } from '../main/ets/common/style/AdaptiveOverlayLayout';

export default function adaptiveOverlayLayoutTest(): void {
  describe('adaptiveOverlayLayoutTest', () => {
    it('switchesAtThe600VpContainerBreakpoint', 0, () => {
      expect(isWideOverlayContainer(599)).assertFalse();
      expect(isWideOverlayContainer(600)).assertTrue();
    });

    it('keepsWideTaskPanelsWithinTheirMaximumWidth', 0, () => {
      expect(adaptiveOverlayWidth(1138, 480)).assertEqual(480);
      expect(adaptiveOverlayWidth(1138, 640)).assertEqual(640);
    });

    it('keepsNarrowPanelsInsideTheAvailableWidthAndGutters', 0, () => {
      expect(adaptiveOverlayWidth(350, 480)).assertEqual(302);
      expect(adaptiveOverlayWidth(40, 480)).assertEqual(0);
    });
  });
}
