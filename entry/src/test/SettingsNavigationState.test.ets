import { describe, expect, it } from '@ohos/hypium';
import {
  hasInternalBack,
  isPaneAvailable,
  isPaneHighlighted,
  paneAfterDeveloperModeDisabled,
  paneAncestors,
  paneForEntry,
  paneParent,
  panePath,
  paneTitle,
  SettingsPaneId
} from '../main/ets/pages/SettingsNavigationState';
import { SettingsEntryId } from '../main/ets/pages/SettingsSearchIndex';

export default function settingsNavigationStateTest(): void {
  describe('settingsNavigationStateTest', () => {
    it('mapsChildPanesToTheirCategoryRoot', 0, () => {
      expect(paneParent(SettingsPaneId.BLOCKING_RULES)).assertEqual(SettingsPaneId.FILTER);
      expect(paneParent(SettingsPaneId.BLOCKED_HISTORY)).assertEqual(SettingsPaneId.FILTER);
      expect(paneParent(SettingsPaneId.THEME_COLOR)).assertEqual(SettingsPaneId.APPEARANCE);
      expect(paneParent(SettingsPaneId.FILTER)).assertEqual(SettingsPaneId.NONE);
      expect(paneParent(SettingsPaneId.DEVELOPER)).assertEqual(SettingsPaneId.NONE);
      expect(paneParent(SettingsPaneId.NONE)).assertEqual(SettingsPaneId.NONE);
    });

    it('keepsCategoryHighlightedForChildPanes', 0, () => {
      expect(isPaneHighlighted(SettingsPaneId.BLOCKING_RULES, SettingsPaneId.FILTER)).assertTrue();
      expect(isPaneHighlighted(SettingsPaneId.BLOCKED_HISTORY, SettingsPaneId.FILTER)).assertTrue();
      expect(isPaneHighlighted(SettingsPaneId.BLOCKING_RULES, SettingsPaneId.APPEARANCE)).assertFalse();
      expect(isPaneHighlighted(SettingsPaneId.NONE, SettingsPaneId.FILTER)).assertFalse();
      const ancestors: Array<SettingsPaneId> = paneAncestors(SettingsPaneId.BLOCKING_RULES);
      expect(ancestors.length).assertEqual(1);
      expect(ancestors[0]).assertEqual(SettingsPaneId.FILTER);
      expect(paneAncestors(SettingsPaneId.FILTER).length).assertEqual(0);
    });

    it('buildsPanePathFromCategoryRoot', 0, () => {
      const path: Array<SettingsPaneId> = panePath(SettingsPaneId.BLOCKED_HISTORY);
      expect(path.length).assertEqual(2);
      expect(path[0]).assertEqual(SettingsPaneId.FILTER);
      expect(path[1]).assertEqual(SettingsPaneId.BLOCKED_HISTORY);
      expect(panePath(SettingsPaneId.DEVELOPER).length).assertEqual(1);
      expect(panePath(SettingsPaneId.DEVELOPER)[0]).assertEqual(SettingsPaneId.DEVELOPER);
    });

    it('resolvesSearchEntriesToInternalPanes', 0, () => {
      expect(paneForEntry(SettingsEntryId.BLOCKING_RULES)).assertEqual(SettingsPaneId.BLOCKING_RULES);
      expect(paneForEntry(SettingsEntryId.BLOCKED_HISTORY)).assertEqual(SettingsPaneId.BLOCKED_HISTORY);
      expect(paneForEntry(SettingsEntryId.DEVELOPER)).assertEqual(SettingsPaneId.DEVELOPER);
      expect(paneForEntry(SettingsEntryId.FILTER)).assertEqual(SettingsPaneId.FILTER);
      // 登录留在根路由，不作为设置内部 pane。
      expect(paneForEntry(SettingsEntryId.LOGIN)).assertEqual(SettingsPaneId.NONE);
    });

    it('resolvesBackBehaviorByLayout', 0, () => {
      // 窄栏：任何详情都先回目录。
      expect(hasInternalBack(SettingsPaneId.FILTER, false)).assertTrue();
      expect(hasInternalBack(SettingsPaneId.NONE, false)).assertFalse();
      // 双栏：分类根页返回即退出设置，只有子页在右栏内返回。
      expect(hasInternalBack(SettingsPaneId.FILTER, true)).assertFalse();
      expect(hasInternalBack(SettingsPaneId.BLOCKING_RULES, true)).assertTrue();
      expect(hasInternalBack(SettingsPaneId.BLOCKED_HISTORY, true)).assertTrue();
      expect(hasInternalBack(SettingsPaneId.DEVELOPER, true)).assertFalse();
    });

    it('gatesDeveloperPaneByMode', 0, () => {
      expect(isPaneAvailable(SettingsPaneId.DEVELOPER, false)).assertFalse();
      expect(isPaneAvailable(SettingsPaneId.DEVELOPER, true)).assertTrue();
      expect(isPaneAvailable(SettingsPaneId.BLOCKING_RULES, false)).assertTrue();
      // 关闭模式后回目录，不停留在已隐藏的开发者页。
      expect(paneAfterDeveloperModeDisabled(SettingsPaneId.DEVELOPER)).assertEqual(SettingsPaneId.NONE);
      expect(paneAfterDeveloperModeDisabled(SettingsPaneId.FILTER)).assertEqual(SettingsPaneId.FILTER);
    });

    it('providesSingleTitlesForHost', 0, () => {
      expect(paneTitle(SettingsPaneId.BLOCKING_RULES)).assertEqual('内容屏蔽');
      expect(paneTitle(SettingsPaneId.BLOCKED_HISTORY)).assertEqual('屏蔽记录');
      expect(paneTitle(SettingsPaneId.DEVELOPER)).assertEqual('开发者选项');
      expect(paneTitle(SettingsPaneId.NONE)).assertEqual('设置');
    });
  });
}
