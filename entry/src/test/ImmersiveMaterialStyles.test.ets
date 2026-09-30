import { describe, expect, it } from '@ohos/hypium';
import { ImmersiveMaterialMode } from 'data';
import {
  decodeImmersiveMaterialSupport,
  immersiveMaterialEffectiveNotice,
  ImmersiveMaterialSupportState,
  immersiveMaterialModeIndex,
  immersiveMaterialModeLabel,
  resolveImmersiveMaterialLevel
} from '../main/ets/common/style/ImmersiveMaterialStyles';

/** 统一材质策略纯映射验证（docs/immersive-material-settings-plan.md §4 策略表）。
 * 真实 GPU 材质刷新与设备能力查询属设备回归，本文件只覆盖可独立验证的映射。 */
export default function immersiveMaterialStylesTest(): void {
  describe('immersiveMaterialStylesTest', () => {
    it('keepsAllModesWhenDeviceSupportsImmersive', 0, () => {
      expect(resolveImmersiveMaterialLevel(ImmersiveMaterialMode.ADAPTIVE, ImmersiveMaterialSupportState.SUPPORTED))
        .assertEqual(ImmersiveMaterialMode.ADAPTIVE);
      expect(resolveImmersiveMaterialLevel(ImmersiveMaterialMode.EXQUISITE, ImmersiveMaterialSupportState.SUPPORTED))
        .assertEqual(ImmersiveMaterialMode.EXQUISITE);
      expect(resolveImmersiveMaterialLevel(ImmersiveMaterialMode.GENTLE, ImmersiveMaterialSupportState.SUPPORTED))
        .assertEqual(ImmersiveMaterialMode.GENTLE);
      expect(resolveImmersiveMaterialLevel(ImmersiveMaterialMode.SMOOTH, ImmersiveMaterialSupportState.SUPPORTED))
        .assertEqual(ImmersiveMaterialMode.SMOOTH);
    });

    it('downgradesExquisiteAndGentleToSmoothWhenUnsupported', 0, () => {
      expect(resolveImmersiveMaterialLevel(ImmersiveMaterialMode.EXQUISITE, ImmersiveMaterialSupportState.UNSUPPORTED))
        .assertEqual(ImmersiveMaterialMode.SMOOTH);
      expect(resolveImmersiveMaterialLevel(ImmersiveMaterialMode.GENTLE, ImmersiveMaterialSupportState.UNSUPPORTED))
        .assertEqual(ImmersiveMaterialMode.SMOOTH);
      // 自适应与流畅不受设备能力影响：HDS 仍交由系统自适应 / 恒为流畅。
      expect(resolveImmersiveMaterialLevel(ImmersiveMaterialMode.ADAPTIVE, ImmersiveMaterialSupportState.UNSUPPORTED))
        .assertEqual(ImmersiveMaterialMode.ADAPTIVE);
      expect(resolveImmersiveMaterialLevel(ImmersiveMaterialMode.SMOOTH, ImmersiveMaterialSupportState.UNSUPPORTED))
        .assertEqual(ImmersiveMaterialMode.SMOOTH);
    });

    it('treatsCapabilityQueryFailureAsUnsupported', 0, () => {
      // 查询失败（UNKNOWN）按不支持处理：只影响本次生效策略，不改变用户保存的选择。
      expect(resolveImmersiveMaterialLevel(ImmersiveMaterialMode.EXQUISITE, ImmersiveMaterialSupportState.UNKNOWN))
        .assertEqual(ImmersiveMaterialMode.SMOOTH);
      expect(resolveImmersiveMaterialLevel(ImmersiveMaterialMode.GENTLE, ImmersiveMaterialSupportState.UNKNOWN))
        .assertEqual(ImmersiveMaterialMode.SMOOTH);
      expect(decodeImmersiveMaterialSupport(undefined)).assertEqual(ImmersiveMaterialSupportState.UNKNOWN);
      expect(decodeImmersiveMaterialSupport('broken')).assertEqual(ImmersiveMaterialSupportState.UNKNOWN);
      expect(decodeImmersiveMaterialSupport(ImmersiveMaterialSupportState.SUPPORTED))
        .assertEqual(ImmersiveMaterialSupportState.SUPPORTED);
      expect(decodeImmersiveMaterialSupport(ImmersiveMaterialSupportState.UNSUPPORTED))
        .assertEqual(ImmersiveMaterialSupportState.UNSUPPORTED);
    });

    it('annotatesDowngradedModesAndKeepsLabels', 0, () => {
      expect(immersiveMaterialEffectiveNotice(ImmersiveMaterialMode.EXQUISITE,
        ImmersiveMaterialSupportState.UNSUPPORTED).length > 0).assertTrue();
      expect(immersiveMaterialEffectiveNotice(ImmersiveMaterialMode.GENTLE,
        ImmersiveMaterialSupportState.UNKNOWN).length > 0).assertTrue();
      expect(immersiveMaterialEffectiveNotice(ImmersiveMaterialMode.EXQUISITE,
        ImmersiveMaterialSupportState.SUPPORTED)).assertEqual('');
      expect(immersiveMaterialEffectiveNotice(ImmersiveMaterialMode.ADAPTIVE,
        ImmersiveMaterialSupportState.UNSUPPORTED)).assertEqual('');
      // 段控顺序固定：自适应 / 精美 / 轻柔 / 流畅，下标与显示名一一对应。
      expect(immersiveMaterialModeIndex(ImmersiveMaterialMode.ADAPTIVE)).assertEqual(0);
      expect(immersiveMaterialModeIndex(ImmersiveMaterialMode.EXQUISITE)).assertEqual(1);
      expect(immersiveMaterialModeIndex(ImmersiveMaterialMode.GENTLE)).assertEqual(2);
      expect(immersiveMaterialModeIndex(ImmersiveMaterialMode.SMOOTH)).assertEqual(3);
      expect(immersiveMaterialModeLabel(ImmersiveMaterialMode.ADAPTIVE)).assertEqual('自适应');
      expect(immersiveMaterialModeLabel(ImmersiveMaterialMode.EXQUISITE)).assertEqual('精美');
      expect(immersiveMaterialModeLabel(ImmersiveMaterialMode.GENTLE)).assertEqual('轻柔');
      expect(immersiveMaterialModeLabel(ImmersiveMaterialMode.SMOOTH)).assertEqual('流畅');
    });
  });
}
