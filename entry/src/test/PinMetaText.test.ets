import { describe, expect, it } from '@ohos/hypium';
import { pinMetaText } from '../main/ets/pages/PinMetaText';

export default function pinMetaTextTest(): void {
  describe('pinMetaTextTest', () => {
    it('usesEditedLabelWithMinutePrecisionAndIpLocation', 0, () => {
      const created = 1792130416;
      const updated = 1792131106;
      const text = pinMetaText(created, updated, '北京');
      expect(text.startsWith('编辑于 ')).assertTrue();
      expect(text.endsWith(' ・ IP 属地北京')).assertTrue();
      // 时间戳形如 2026-10-16 14:11（精确到分钟）。
      const stamp = text.substring('编辑于 '.length, text.length - ' ・ IP 属地北京'.length);
      expect(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/.test(stamp)).assertTrue();
    });

    it('usesPublishedLabelWhenNeverUpdated', 0, () => {
      const created = 1792130416;
      const text = pinMetaText(created, created, '');
      expect(text.startsWith('发布于 ')).assertTrue();
      expect(text.includes('IP 属地')).assertFalse();
    });

    it('omitsIpWhenUpstreamDoesNotProvideIt', 0, () => {
      const text = pinMetaText(1792130416, 1792131106, '   ');
      expect(text.includes('IP 属地')).assertFalse();
      expect(text.startsWith('编辑于 ')).assertTrue();
    });

    it('keepsIpOnlyWhenTimestampsAreMissing', 0, () => {
      expect(pinMetaText(0, 0, '')).assertEqual('');
      expect(pinMetaText(0, 0, '上海')).assertEqual('IP 属地上海');
      expect(pinMetaText(Number.NaN, 0, '')).assertEqual('');
    });
  });
}
