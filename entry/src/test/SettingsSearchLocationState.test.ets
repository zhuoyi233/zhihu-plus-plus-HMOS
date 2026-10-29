import { describe, expect, it } from '@ohos/hypium';
import {
  computeScrollPlan,
  highlightPlan,
  isRequestCurrent,
  scrollDurationMs,
  withAlpha
} from '../main/ets/pages/SettingsSearchLocationState';
import { SettingsPaneId, SettingsSearchLocationRequest } from '../main/ets/pages/SettingsSearchTarget';

function sampleRequest(requestId: number, anchorId: string): SettingsSearchLocationRequest {
  return {
    sessionId: 1,
    requestId: requestId,
    entryId: 'appearance_line_height',
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: anchorId,
    highlightGroupId: 'appearance_group_reading',
    fallbackAnchorId: ''
  } as SettingsSearchLocationRequest;
}

export default function settingsSearchLocationStateTest(): void {
  describe('settingsSearchLocationStateTest', () => {
    it('clampsScrollTargetToValidRange', 0, () => {
      // 锚点内容坐标 1200，希望视口位置 106：目标 1094。
      const plan = computeScrollPlan(1200, 0, 800, 3000, 106);
      expect(plan.targetOffset).assertEqual(1094);
      expect(plan.distance).assertEqual(1094);
      expect(plan.skip).assertFalse();

      // 底部钳制：内容 3000 - 视口 800 = 最大 2200。
      const clamped = computeScrollPlan(4000, 100, 800, 3000, 106);
      expect(clamped.targetOffset).assertEqual(2200);

      // 顶部钳制：锚点在视口上方时不产生负偏移。
      const top = computeScrollPlan(50, 400, 800, 3000, 106);
      expect(top.targetOffset).assertEqual(0);
      expect(top.skip).assertFalse();
    });

    it('skipsZeroDistanceScroll', 0, () => {
      const same = computeScrollPlan(1106, 1000, 800, 3000, 106);
      expect(same.targetOffset).assertEqual(1000);
      expect(same.distance).assertEqual(0);
      expect(same.skip).assertTrue();

      // 视口/内容尺寸非法时退化为不滚动。
      const degenerate = computeScrollPlan(1200, 0, 0, 0, 106);
      expect(degenerate.skip).assertTrue();
    });

    it('keepsScrollDurationInRange', 0, () => {
      expect(scrollDurationMs(0)).assertEqual(0);
      // 常规距离 280–400ms 内插，超长距离封顶 500ms。
      const medium: number = scrollDurationMs(300);
      expect(medium >= 280 && medium <= 400).assertTrue();
      expect(scrollDurationMs(1600) <= 400).assertTrue();
      expect(scrollDurationMs(5000)).assertEqual(500);
    });

    it('playsExactlyTwoHighlightCycles', 0, () => {
      const plan = highlightPlan();
      expect(plan.length).assertEqual(4);
      // 亮 160 → 灭 200 →（静止 100）→ 亮 160 → 灭 200。
      expect(plan[0].level).assertEqual(1);
      expect(plan[0].durationMs).assertEqual(160);
      expect(plan[1].level).assertEqual(0);
      expect(plan[1].durationMs).assertEqual(200);
      expect(plan[1].gapAfterMs).assertEqual(100);
      expect(plan[2].level).assertEqual(1);
      expect(plan[2].durationMs).assertEqual(160);
      expect(plan[3].level).assertEqual(0);
      expect(plan[3].durationMs).assertEqual(200);
      const total: number = plan[0].durationMs + plan[1].durationMs + plan[1].gapAfterMs +
        plan[2].durationMs + plan[3].durationMs;
      expect(total).assertEqual(820);
    });

    it('appendsAlphaChannelOnlyToValidHex', 0, () => {
      expect(withAlpha('#0084FF', '26')).assertEqual('#260084FF');
      expect(withAlpha('#FF0084FF', 'CC')).assertEqual('#CC0084FF');
      // 非法格式原样返回，避免拼接出错误颜色。
      expect(withAlpha('rgb(0,0,0)', '26')).assertEqual('rgb(0,0,0)');
      expect(withAlpha('', '26')).assertEqual('');
    });

    it('rejectsRequestsSupersededOrCancelled', 0, () => {
      AppStorage.setOrCreate('settingsSearchLocationRequest', sampleRequest(100, 'anchor_a'));
      // 最新请求即当前请求。
      expect(isRequestCurrent(sampleRequest(100, 'anchor_a'))).assertTrue();
      // 被更新的请求覆盖后立即失效。
      AppStorage.setOrCreate('settingsSearchLocationRequest', sampleRequest(101, 'anchor_b'));
      expect(isRequestCurrent(sampleRequest(100, 'anchor_a'))).assertFalse();
      expect(isRequestCurrent(sampleRequest(101, 'anchor_b'))).assertTrue();
    });
  });
}
