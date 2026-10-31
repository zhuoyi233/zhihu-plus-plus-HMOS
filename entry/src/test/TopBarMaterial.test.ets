import { describe, expect, it } from '@ohos/hypium';
import {
  resolveTopBarMaterialPath,
  TopBarMaterialInputs,
  TopBarMaterialPath,
  TOP_BAR_ACTION_SPACING_VP,
  TOP_BAR_BUTTON_DIAMETER_VP,
  TOP_BAR_HDS_BACK_RESERVE_VP,
  TOP_BAR_HORIZONTAL_PADDING_VP,
  topBarActionsWidthVp,
  topBarFeedStartOffsetVp,
  topBarStartOffsetVp
} from '../main/ets/common/style/TopBarMaterial';
import {
  removeTopBarActionStateFrom,
  sameTopBarActionState,
  TopBarActionState,
  topBarActionAvailable,
  topBarActionEnabled,
  topBarActionText,
  topBarActionTitle,
  upsertTopBarActionState
} from '../main/ets/common/style/TopBarActionState';

/**
 * 顶栏共享策略的纯映射验证（docs/top-bars-immersive-material-plan.md §3.1、§3.3、§3.7、§4.1）。
 * 真实材质渲染、按钮轮廓、动画与点击热区属设备回归，本文件只覆盖可独立验证的判定分支。
 */
export default function topBarMaterialTest(): void {
  describe('topBarMaterialTest', () => {
    const withMaterial: TopBarMaterialInputs = { systemMaterialCreated: true };
    const withoutMaterial: TopBarMaterialInputs = { systemMaterialCreated: false };

    it('usesSystemMaterialOnlyWhenObjectExists', 0, () => {
      // 两档接入：只由系统材质对象是否存在决定，不再叠加 HDS 能力判断。
      expect(resolveTopBarMaterialPath(withMaterial)).assertEqual(TopBarMaterialPath.SYSTEM_MATERIAL);
      expect(resolveTopBarMaterialPath(withoutMaterial)).assertEqual(TopBarMaterialPath.FALLBACK_BLUR);
    });

    it('keepsMainSettingsGeometryConstants', 0, () => {
      // main 设置页样板：40vp 圆形动作、10vp 间距、右侧 12vp、80vp 返回预留。
      expect(TOP_BAR_BUTTON_DIAMETER_VP).assertEqual(40);
      expect(TOP_BAR_ACTION_SPACING_VP).assertEqual(10);
      expect(TOP_BAR_HORIZONTAL_PADDING_VP).assertEqual(12);
      expect(TOP_BAR_HDS_BACK_RESERVE_VP).assertEqual(80);
    });

    it('spacesMultipleActionsByMainSettingsRule', 0, () => {
      // §3.7：N 个动作占 40×N＋10×(N−1)，零动作只留一个 40vp 空位。
      expect(topBarActionsWidthVp(0)).assertEqual(40);
      expect(topBarActionsWidthVp(1)).assertEqual(40);
      expect(topBarActionsWidthVp(2)).assertEqual(90);
      expect(topBarActionsWidthVp(3)).assertEqual(140);
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

    it('resolvesRegisteredTopBarStateById', 0, () => {
      const registered: TopBarActionState = {
        id: 'unit_test_top_bar',
        available: true,
        title: '单元测试',
        text: '发布',
        enabled: false
      };
      let states: TopBarActionState[] = upsertTopBarActionState([], registered);
      expect(topBarActionAvailable(states, registered.id)).assertTrue();
      expect(topBarActionTitle(states, registered.id)).assertEqual('单元测试');
      expect(topBarActionText(states, registered.id)).assertEqual('发布');
      expect(topBarActionEnabled(states, registered.id)).assertFalse();
      // 未注册的 id 一律按不可用处理，宿主不会画出残留动作。
      expect(topBarActionAvailable(states, 'missing_id')).assertFalse();
      expect(topBarActionTitle(states, 'missing_id')).assertEqual('');
      states = removeTopBarActionStateFrom(states, registered.id);
      expect(states.length).assertEqual(0);
      expect(topBarActionAvailable(states, registered.id)).assertFalse();
    });

    it('replacesSameIdWithoutTouchingOtherPages', 0, () => {
      const first: TopBarActionState = { id: 'a', available: true, title: 'A', text: '', enabled: true };
      const other: TopBarActionState = { id: 'b', available: true, title: 'B', text: '', enabled: true };
      const updated: TopBarActionState = { id: 'a', available: true, title: 'A2', text: '发布', enabled: false };
      let states: TopBarActionState[] = upsertTopBarActionState([first, other], updated);
      expect(states.length).assertEqual(2);
      expect(topBarActionTitle(states, 'a')).assertEqual('A2');
      expect(topBarActionText(states, 'a')).assertEqual('发布');
      expect(topBarActionTitle(states, 'b')).assertEqual('B');
      states = removeTopBarActionStateFrom(states, 'a');
      expect(states.length).assertEqual(1);
      expect(topBarActionTitle(states, 'b')).assertEqual('B');
    });

    it('skipsRedundantStateWrites', 0, () => {
      const state: TopBarActionState = { id: 'c', available: true, title: 'C', text: '', enabled: true };
      expect(sameTopBarActionState(undefined, state)).assertFalse();
      expect(sameTopBarActionState(state, state)).assertTrue();
      // 只有 enabled 变化也必须视为不同，发布按钮的禁用态要能即时生效。
      const enabledChanged: TopBarActionState = { id: 'c', available: true, title: 'C', text: '', enabled: false };
      expect(sameTopBarActionState(state, enabledChanged)).assertFalse();
    });
  });
}
