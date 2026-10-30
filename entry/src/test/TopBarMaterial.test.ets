import { describe, expect, it } from '@ohos/hypium';
import {
  resolveTopBarMaterialPath,
  TopBarMaterialInputs,
  TopBarMaterialPath,
  topBarFeedStartOffsetVp,
  topBarStartOffsetVp
} from '../main/ets/common/style/TopBarMaterial';

/**
 * 顶栏共享策略的纯映射验证（docs/top-bars-immersive-material-plan.md §3.3、§4.1）。
 * 真实材质渲染、按钮轮廓与降级观感属设备回归，本文件只覆盖可独立验证的判定分支。
 */
export default function topBarMaterialTest(): void {
  describe('topBarMaterialTest', () => {
    const systemMaterial: TopBarMaterialInputs = {
      hdsImmersiveSupported: true,
      systemMaterialCreated: true
    };
    const legacyCanvas: TopBarMaterialInputs = {
      hdsImmersiveSupported: true,
      systemMaterialCreated: false
    };
    const noMaterial: TopBarMaterialInputs = {
      hdsImmersiveSupported: false,
      systemMaterialCreated: false
    };
    // 材质对象创建失败也不能绕过能力判断。
    const unsupportedWithMaterial: TopBarMaterialInputs = {
      hdsImmersiveSupported: false,
      systemMaterialCreated: true
    };

    it('picksSystemMaterialOnlyWhenBothConditionsHold', 0, () => {
      expect(resolveTopBarMaterialPath(systemMaterial)).assertEqual(TopBarMaterialPath.SYSTEM_MATERIAL);
      expect(resolveTopBarMaterialPath(legacyCanvas)).assertEqual(TopBarMaterialPath.HDS_CANVAS);
    });

    it('fallsBackToBlurWhenDeviceLacksImmersiveCapability', 0, () => {
      // 查询失败或不支持都走模糊兜底，不能留下半截材质路径。
      expect(resolveTopBarMaterialPath(noMaterial)).assertEqual(TopBarMaterialPath.FALLBACK_BLUR);
      expect(resolveTopBarMaterialPath(unsupportedWithMaterial)).assertEqual(TopBarMaterialPath.FALLBACK_BLUR);
    });

    it('keepsStartOffsetAtLeast94UntilStatusBarGrows', 0, () => {
      expect(topBarStartOffsetVp(0)).assertEqual(94);
      expect(topBarStartOffsetVp(24)).assertEqual(94);
      expect(topBarStartOffsetVp(48)).assertEqual(104);
    });

    it('liftsFeedStartByOverlapWithoutGoingAboveBarArea', 0, () => {
      expect(topBarFeedStartOffsetVp(0, 10)).assertEqual(84);
      expect(topBarFeedStartOffsetVp(48, 10)).assertEqual(94);
      // 状态栏极高时，上浮量不能把内容顶回顶栏区域之上。
      expect(topBarFeedStartOffsetVp(0, 200)).assertEqual(56);
    });
  });
}
