import { describe, expect, it } from '@ohos/hypium';
import {
  matchSettingsSearchEntries,
  SettingsEntryId,
  SettingsSearchEntry,
  SettingsSearchOptions,
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
      expect(results.length).assertEqual(1);
      expect(results[0].id).assertEqual(SettingsEntryId.DEVELOPER);
    });

    it('matchesKeywordsAndSubItemsWithPath', 0, () => {
      const entries: Array<SettingsSearchEntry> = visibleSettingsSearchEntries(authenticatedOptions(false));

      const fontResults: Array<SettingsSearchEntry> = matchSettingsSearchEntries(entries, '字号');
      expect(fontResults.length > 0).assertTrue();
      expect(fontResults.some((entry: SettingsSearchEntry): boolean => entry.id === SettingsEntryId.APPEARANCE))
        .assertTrue();

      const blockingHistory: Array<SettingsSearchEntry> = matchSettingsSearchEntries(entries, '屏蔽记录');
      expect(blockingHistory.length).assertEqual(1);
      expect(blockingHistory[0].id).assertEqual(SettingsEntryId.BLOCKED_HISTORY);
      expect(blockingHistory[0].path).assertEqual('推荐系统与内容过滤');

      const license: Array<SettingsSearchEntry> = matchSettingsSearchEntries(entries, 'AGPL');
      expect(license.some((entry: SettingsSearchEntry): boolean => entry.id === SettingsEntryId.ABOUT_LICENSE))
        .assertTrue();
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

    it('returnsEmptyForBlankOrUnknownQueries', 0, () => {
      const entries: Array<SettingsSearchEntry> = visibleSettingsSearchEntries(authenticatedOptions(true));
      expect(matchSettingsSearchEntries(entries, '   ').length).assertEqual(0);
      expect(matchSettingsSearchEntries(entries, '').length).assertEqual(0);
      expect(matchSettingsSearchEntries(entries, '不存在的设置项').length).assertEqual(0);
      // 查询大小写不敏感。
      const githubResults: Array<SettingsSearchEntry> = matchSettingsSearchEntries(entries, 'github');
      expect(githubResults.some((entry: SettingsSearchEntry): boolean => entry.id === SettingsEntryId.ABOUT_GITHUB))
        .assertTrue();
    });
  });
}
