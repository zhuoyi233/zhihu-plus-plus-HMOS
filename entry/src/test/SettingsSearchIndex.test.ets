import { describe, expect, it } from '@ohos/hypium';
import {
  matchSettingsSearchEntries,
  normalizeSearchQuery,
  SettingsEntryId,
  SettingsSearchEntry,
  SettingsSearchOptions,
  SettingsTargetKind,
  visibleSettingsSearchEntries
} from '../main/ets/pages/SettingsSearchIndex';

function anonymousOptions(developerModeEnabled: boolean): SettingsSearchOptions {
  return { authenticated: false, developerModeEnabled: developerModeEnabled };
}

function authenticatedOptions(developerModeEnabled: boolean): SettingsSearchOptions {
  return { authenticated: true, developerModeEnabled: developerModeEnabled };
}

function entryIds(entries: Array<SettingsSearchEntry>): Array<string> {
  return entries.map((entry: SettingsSearchEntry): string => entry.id);
}

export default function settingsSearchIndexTest(): void {
  describe('settingsSearchIndexTest', () => {
    it('respectsLoginVisibility', 0, () => {
      const anonymous: Array<string> = entryIds(visibleSettingsSearchEntries(anonymousOptions(false)));
      expect(anonymous.includes(SettingsEntryId.LOGIN)).assertTrue();
      expect(anonymous.includes(SettingsEntryId.IDENTITY)).assertFalse();

      const authenticated: Array<string> = entryIds(visibleSettingsSearchEntries(authenticatedOptions(false)));
      expect(authenticated.includes(SettingsEntryId.IDENTITY)).assertTrue();
      expect(authenticated.includes(SettingsEntryId.LOGIN)).assertFalse();
    });

    it('keepsDeveloperEntriesHiddenUntilEnabled', 0, () => {
      const hidden: Array<SettingsSearchEntry> = visibleSettingsSearchEntries(anonymousOptions(false));
      expect(matchSettingsSearchEntries(hidden, 'Cookie').length).assertEqual(0);

      const visible: Array<SettingsSearchEntry> = visibleSettingsSearchEntries(anonymousOptions(true));
      const results: Array<SettingsSearchEntry> = matchSettingsSearchEntries(visible, 'Cookie');
      // 细项“手动 Cookie”与开发者分类都命中；具体设置项排在分类之前。
      expect(results.length).assertEqual(2);
      expect(results[0].id).assertEqual('developer_cookie');
      expect(results[0].targetKind).assertEqual(SettingsTargetKind.SETTING_ITEM);
      expect(results[0].paneId).assertEqual('developer');
      expect(results[1].id).assertEqual(SettingsEntryId.DEVELOPER);
    });

    it('matchesKeywordsAndSubItemsWithPath', 0, () => {
      const entries: Array<SettingsSearchEntry> = visibleSettingsSearchEntries(authenticatedOptions(false));

      // “字号”命中具体设置项并优先于分类。
      const fontResults: Array<SettingsSearchEntry> = matchSettingsSearchEntries(entries, '字号');
      expect(fontResults.length > 0).assertTrue();
      expect(fontResults[0].id).assertEqual('appearance_font_size');
      expect(fontResults[0].anchorId).assertEqual('appearance_anchor_font_size');
      expect(fontResults.some((entry: SettingsSearchEntry): boolean => entry.id === SettingsEntryId.APPEARANCE))
        .assertTrue();

      const blockingHistory: Array<SettingsSearchEntry> = matchSettingsSearchEntries(entries, '屏蔽记录');
      expect(blockingHistory.length).assertEqual(1);
      expect(blockingHistory[0].id).assertEqual(SettingsEntryId.BLOCKED_HISTORY);
      expect(blockingHistory[0].path).assertEqual('推荐系统与内容过滤');

      const license: Array<SettingsSearchEntry> = matchSettingsSearchEntries(entries, 'AGPL');
      expect(license.some((entry: SettingsSearchEntry): boolean => entry.id === SettingsEntryId.ABOUT_LICENSE))
        .assertTrue();
      expect(license[0].anchorId).assertEqual('open_project_license');
    });

    it('findsBlockingRuleSubFeatures', 0, () => {
      const entries: Array<SettingsSearchEntry> = visibleSettingsSearchEntries(authenticatedOptions(false));

      const topicResults: Array<SettingsSearchEntry> = matchSettingsSearchEntries(entries, '话题');
      expect(topicResults.some((entry: SettingsSearchEntry): boolean => entry.id === SettingsEntryId.BLOCKING_RULES))
        .assertTrue();

      const regexResults: Array<SettingsSearchEntry> = matchSettingsSearchEntries(entries, '正则');
      expect(regexResults.some((entry: SettingsSearchEntry): boolean => entry.id === SettingsEntryId.BLOCKING_RULES))
        .assertTrue();

      const backupResults: Array<SettingsSearchEntry> = matchSettingsSearchEntries(entries, '导入');
      expect(backupResults.some((entry: SettingsSearchEntry): boolean => entry.id === SettingsEntryId.BLOCKING_RULES))
        .assertTrue();
    });

    it('ranksDetailItemsBeforeCategories', 0, () => {
      const entries: Array<SettingsSearchEntry> = visibleSettingsSearchEntries(authenticatedOptions(false));

      // 语速：细项标题完全匹配优先，分类仅关键词命中。
      const speed: Array<SettingsSearchEntry> = matchSettingsSearchEntries(entries, '语速');
      expect(speed.length > 0).assertTrue();
      expect(speed[0].id).assertEqual('reading_speed');
      expect(speed[0].highlightGroupId).assertEqual('reading_group_voice');

      // 行间距别名落到行高细项。
      const lineHeight: Array<SettingsSearchEntry> = matchSettingsSearchEntries(entries, '行间距');
      expect(lineHeight.length > 0).assertTrue();
      expect(lineHeight[0].id).assertEqual('appearance_line_height');

      // “正文排版”命中排版预设细项（此前清点遗漏）。
      const typography: Array<SettingsSearchEntry> = matchSettingsSearchEntries(entries, '正文排版');
      expect(typography.length > 0).assertTrue();
      expect(typography[0].id).assertEqual('appearance_typography_preset');
      expect(typography[0].anchorId).assertEqual('appearance_anchor_typography_preset');

      // “缩略图”命中信息流细项（此前清点遗漏）。
      const thumbnail: Array<SettingsSearchEntry> = matchSettingsSearchEntries(entries, '缩略图');
      expect(thumbnail.length > 0).assertTrue();
      expect(thumbnail[0].id).assertEqual('appearance_feed_thumbnail');
      expect(thumbnail[0].anchorId).assertEqual('appearance_feed_thumbnail');
      expect(thumbnail[0].highlightGroupId).assertEqual('appearance_group_feed');

      // 外观页其余代表细项：翻页距离、主题模式、双击动作、搜索历史。
      const pageTurn: Array<SettingsSearchEntry> = matchSettingsSearchEntries(entries, '翻页距离');
      expect(pageTurn[0].id).assertEqual('appearance_page_turn_percent');
      const themeMode: Array<SettingsSearchEntry> = matchSettingsSearchEntries(entries, '深色模式');
      expect(themeMode[0].id).assertEqual('appearance_theme_mode');
      const doubleTap: Array<SettingsSearchEntry> = matchSettingsSearchEntries(entries, '双击');
      expect(doubleTap[0].id).assertEqual('appearance_answer_double_tap');
      const searchHistory: Array<SettingsSearchEntry> = matchSettingsSearchEntries(entries, '搜索历史');
      expect(searchHistory[0].id).assertEqual('appearance_search_history');

      // 条件行声明前置回退：跳转按钮隐藏时定位其开关。
      const skipAutoHide: Array<SettingsSearchEntry> = matchSettingsSearchEntries(entries, '跳转按钮');
      expect(skipAutoHide[0].id).assertEqual('appearance_skip_answer_auto_hide');
      expect(skipAutoHide[0].fallbackAnchorId).assertEqual('appearance_skip_answer');

      // 主题色落点为主题颜色页的选色区域。
      const themeColor: Array<SettingsSearchEntry> = matchSettingsSearchEntries(entries, '主题色');
      expect(themeColor[0].id).assertEqual(SettingsEntryId.THEME_COLOR);
      expect(themeColor[0].anchorId).assertEqual('theme_color_anchor_presets');

      // 条件隐藏项声明前置开关回退。
      const threshold: Array<SettingsSearchEntry> = matchSettingsSearchEntries(entries, '主题屏蔽阈值');
      expect(threshold.length > 0).assertTrue();
      expect(threshold[0].id).assertEqual('filter_topic_threshold');
      expect(threshold[0].fallbackAnchorId).assertEqual('filter_anchor_topic_enabled');
    });

    it('matchesMultiTermQueriesAcrossFields', 0, () => {
      const entries: Array<SettingsSearchEntry> = visibleSettingsSearchEntries(authenticatedOptions(false));

      // 两个词分别命中标题与关键词。
      const speech: Array<SettingsSearchEntry> = matchSettingsSearchEntries(entries, '朗读 语速');
      expect(speech.some((entry: SettingsSearchEntry): boolean => entry.id === 'reading_speed')).assertTrue();

      // 任一词未命中即整体不命中。
      const none: Array<SettingsSearchEntry> = matchSettingsSearchEntries(entries, '语速 完全不存在的词');
      expect(none.length).assertEqual(0);

      // 大小写不敏感：GitHub 标题完全匹配排第一。
      const github: Array<SettingsSearchEntry> = matchSettingsSearchEntries(entries, 'github');
      expect(github.length > 0).assertTrue();
      expect(github[0].id).assertEqual(SettingsEntryId.ABOUT_GITHUB);
    });

    it('normalizesQueriesAndKeepsIdsUnique', 0, () => {
      expect(normalizeSearchQuery('  GitHub   语速 ')).assertEqual('github 语速');

      const entries: Array<SettingsSearchEntry> = visibleSettingsSearchEntries(authenticatedOptions(true));
      const results: Array<SettingsSearchEntry> = matchSettingsSearchEntries(entries, '主题');
      const ids: Set<string> = new Set<string>(entryIds(results));
      expect(ids.size).assertEqual(results.length);
    });

    it('returnsEmptyForBlankOrUnknownQueries', 0, () => {
      const entries: Array<SettingsSearchEntry> = visibleSettingsSearchEntries(authenticatedOptions(true));
      expect(matchSettingsSearchEntries(entries, '   ').length).assertEqual(0);
      expect(matchSettingsSearchEntries(entries, '').length).assertEqual(0);
      expect(matchSettingsSearchEntries(entries, '不存在的设置项').length).assertEqual(0);
    });

    it('keepsEveryInternalEntryWithValidPane', 0, () => {
      const entries: Array<SettingsSearchEntry> = visibleSettingsSearchEntries(authenticatedOptions(true));
      const paneIds: Set<string> = new Set<string>([
        'none', 'identity', 'appearance', 'theme_color', 'reading', 'filter',
        'blocking_rules', 'blocked_history', 'notification', 'system_update', 'about', 'developer'
      ]);
      const seenIds: Set<string> = new Set<string>();
      entries.forEach((entry: SettingsSearchEntry): void => {
        expect(seenIds.has(entry.id)).assertFalse();
        seenIds.add(entry.id);
        if (entry.targetKind !== SettingsTargetKind.EXTERNAL) {
          expect(paneIds.has(entry.paneId)).assertTrue();
          // 具体设置项必须同时具备锚点与提醒卡片。
          if (entry.targetKind === SettingsTargetKind.SETTING_ITEM) {
            expect(entry.anchorId.length > 0).assertTrue();
            expect(entry.highlightGroupId.length > 0).assertTrue();
          }
        }
      });
    });
  });
}
