import { describe, expect, it } from '@ohos/hypium';
import {
  ContentDestination,
  decodeAppDestination,
  DeepLinkType,
  InfrastructureDestination,
  isAppDestinationName,
  MAX_SEARCH_QUERY_LENGTH,
  AppDestinationName,
  appDestinationIdentity,
  SearchDestination,
  StatelessDestination,
  shouldReloadAfterAuthentication,
  shouldPushAppDestination,
  toAppDestination,
  WhatsNewDestination
} from 'core';
import {
  isTopLevelTabIndex,
  TopLevelTab,
  topLevelTabForDestination,
  topLevelTabLabel
} from '../main/ets/pages/TopLevelTabs';

interface TestDestinationParam {
  name: string;
  id?: string;
  contentId?: string;
  contentType?: string;
  commentId?: string;
  query?: string;
  questionId?: string;
  answerId?: string;
  draftId?: string;
  version?: string;
  unexpected?: string;
}

export default function appNavigationTest(): void {
  describe('appNavigationTest', () => {
    it('recognizesEveryDeclaredDestinationName', 0, () => {
      const names: Array<AppDestinationName> = [
        AppDestinationName.HOME,
        AppDestinationName.FOLLOWING,
        AppDestinationName.HOT,
        AppDestinationName.DAILY,
        AppDestinationName.DAILY_STORY,
        AppDestinationName.QUESTION,
        AppDestinationName.ANSWER,
        AppDestinationName.ARTICLE,
        AppDestinationName.VIDEO,
        AppDestinationName.PIN,
        AppDestinationName.PEOPLE,
        AppDestinationName.COMMENT,
        AppDestinationName.SEARCH,
        AppDestinationName.COLLECTION,
        AppDestinationName.COLLECTIONS,
        AppDestinationName.NOTIFICATION,
        AppDestinationName.NOTIFICATION_ENTRY,
        AppDestinationName.PRIVATE_MESSAGE,
        AppDestinationName.LOGIN,
        AppDestinationName.SETTINGS,
        AppDestinationName.APPEARANCE_SETTINGS,
        AppDestinationName.IDENTITY_MANAGEMENT,
        AppDestinationName.READING_SETTINGS,
        AppDestinationName.SYSTEM_UPDATE_SETTINGS,
        AppDestinationName.RECOMMENDATION_FILTER_SETTINGS,
        AppDestinationName.BLOCKING_RULES,
        AppDestinationName.BLOCKED_FEED_HISTORY,
        AppDestinationName.READ_HISTORY,
        AppDestinationName.LOCAL_HISTORY,
        AppDestinationName.TECHNICAL_LAB,
        AppDestinationName.READER_PROBE,
        AppDestinationName.IMAGE_PROBE,
        AppDestinationName.DATABASE_PROBE,
        AppDestinationName.DEEP_LINK_PROBE,
        AppDestinationName.QR_SCAN_PROBE,
        AppDestinationName.QR_DESKTOP_LOGIN_SCAN,
        AppDestinationName.BACKGROUND_TASK_PROBE,
        AppDestinationName.DOMAIN_FIXTURE_PROBE,
        AppDestinationName.WRITE_ANSWER,
        AppDestinationName.WRITE_PIN,
        AppDestinationName.PIN_DRAFTS
      ];

      expect(names.every((name: AppDestinationName) => isAppDestinationName(name))).assertTrue();
      expect(isAppDestinationName('UnknownProbe')).assertFalse();
      expect(isAppDestinationName('')).assertFalse();
    });

    it('keepsContentIdsAndSearchQueriesAsStrings', 0, () => {
      const answer: ContentDestination = {
        name: AppDestinationName.ANSWER,
        id: '2040633177593619876'
      };
      const search: SearchDestination = {
        name: AppDestinationName.SEARCH,
        query: 'HarmonyOS ArkTS'
      };

      expect(answer.id).assertEqual('2040633177593619876');
      expect(search.query).assertEqual('HarmonyOS ArkTS');
    });

    it('modelsInfrastructurePagesWithoutBooleanPageFlags', 0, () => {
      const settings: InfrastructureDestination = { name: AppDestinationName.SETTINGS };
      const laboratory: InfrastructureDestination = { name: AppDestinationName.TECHNICAL_LAB };
      const login: InfrastructureDestination = { name: AppDestinationName.LOGIN };

      expect(settings.name).assertEqual(AppDestinationName.SETTINGS);
      expect(laboratory.name).assertEqual(AppDestinationName.TECHNICAL_LAB);
      expect(login.name).assertEqual(AppDestinationName.LOGIN);
    });

    it('decodesWhatsNewDestinationWithOptionalTargetVersion', 0, () => {
      const currentVersionParam: TestDestinationParam = { name: AppDestinationName.WHATS_NEW };
      const previewParam: TestDestinationParam = {
        name: AppDestinationName.WHATS_NEW,
        version: '0.5.5'
      };
      const badVersionParam: TestDestinationParam = {
        name: AppDestinationName.WHATS_NEW,
        version: 'abc;drop'
      };
      const unexpectedFieldParam: TestDestinationParam = {
        name: AppDestinationName.WHATS_NEW,
        unexpected: 'x'
      };

      const current = decodeAppDestination(AppDestinationName.WHATS_NEW, currentVersionParam);
      expect(current?.name).assertEqual(AppDestinationName.WHATS_NEW);
      expect((current as WhatsNewDestination)?.version).assertEqual(undefined);

      const preview = decodeAppDestination(AppDestinationName.WHATS_NEW, previewParam) as WhatsNewDestination;
      expect(preview.version).assertEqual('0.5.5');
      expect(appDestinationIdentity({ name: AppDestinationName.WHATS_NEW }))
        .assertEqual(appDestinationIdentity({ name: AppDestinationName.WHATS_NEW }));
      expect(appDestinationIdentity({ name: AppDestinationName.WHATS_NEW }) !==
        appDestinationIdentity({ name: AppDestinationName.WHATS_NEW, version: '0.5.5' })).assertTrue();

      expect(decodeAppDestination(AppDestinationName.WHATS_NEW, badVersionParam)).assertUndefined();
      expect(decodeAppDestination(AppDestinationName.WHATS_NEW, unexpectedFieldParam)).assertUndefined();
      // 更新预览页不属于底部页签，走导航栈推入。
      expect(topLevelTabForDestination({ name: AppDestinationName.WHATS_NEW })).assertUndefined();
    });

    it('mapsTopLevelDestinationsToStableBottomTabs', 0, () => {
      expect(topLevelTabForDestination({ name: AppDestinationName.HOME })).assertEqual(TopLevelTab.HOME);
      expect(topLevelTabForDestination({ name: AppDestinationName.FOLLOWING }))
        .assertEqual(TopLevelTab.FOLLOWING);
      expect(topLevelTabForDestination({ name: AppDestinationName.HOT })).assertEqual(TopLevelTab.HOT);
      expect(topLevelTabForDestination({ name: AppDestinationName.DAILY })).assertEqual(TopLevelTab.DAILY);
      expect(topLevelTabForDestination({ name: AppDestinationName.READ_HISTORY }))
        .assertEqual(TopLevelTab.HISTORY);
      expect(topLevelTabForDestination({ name: AppDestinationName.COLLECTIONS, id: 'me' }))
        .assertEqual(TopLevelTab.COLLECTIONS);
      expect(topLevelTabForDestination({ name: AppDestinationName.SETTINGS }))
        .assertEqual(TopLevelTab.ACCOUNT);
      expect(topLevelTabForDestination({ name: AppDestinationName.LOGIN })).assertUndefined();
      expect(topLevelTabLabel(TopLevelTab.ACCOUNT)).assertEqual('我的');
      expect(isTopLevelTabIndex(TopLevelTab.HOME)).assertTrue();
      expect(isTopLevelTabIndex(TopLevelTab.ACCOUNT)).assertTrue();
      expect(isTopLevelTabIndex(-1)).assertFalse();
      expect(isTopLevelTabIndex(TopLevelTab.COLLECTIONS)).assertTrue();
      expect(isTopLevelTabIndex(7)).assertFalse();
      expect(isTopLevelTabIndex(1.5)).assertFalse();
    });

    it('decodesOnlyMatchingRuntimeDestinations', 0, () => {
      const answerParam: TestDestinationParam = {
        name: AppDestinationName.ANSWER,
        id: '2040633177593619876'
      };
      const probeParam: TestDestinationParam = {
        name: AppDestinationName.READER_PROBE
      };
      const mismatchedParam: TestDestinationParam = {
        name: AppDestinationName.ARTICLE,
        id: '1'
      };
      const emptyIdParam: TestDestinationParam = {
        name: AppDestinationName.ANSWER,
        id: '   '
      };
      const unexpectedIdParam: TestDestinationParam = {
        name: AppDestinationName.READER_PROBE,
        id: 'unexpected'
      };
      const fixtureParam: TestDestinationParam = {
        name: AppDestinationName.DOMAIN_FIXTURE_PROBE
      };
      const loginParam: TestDestinationParam = {
        name: AppDestinationName.LOGIN
      };
      const appearanceParam: TestDestinationParam = {
        name: AppDestinationName.APPEARANCE_SETTINGS
      };
      const recommendationFilterParam: TestDestinationParam = {
        name: AppDestinationName.RECOMMENDATION_FILTER_SETTINGS
      };
      const desktopLoginScanParam: TestDestinationParam = {
        name: AppDestinationName.QR_DESKTOP_LOGIN_SCAN
      };
      const writeAnswerParam: TestDestinationParam = {
        name: AppDestinationName.WRITE_ANSWER,
        questionId: '123',
        answerId: '456'
      };
      const writePinParam: TestDestinationParam = {
        name: AppDestinationName.WRITE_PIN,
        draftId: '01234567-89ab-4cde-8fab-0123456789ab'
      };
      const pinDraftsParam: TestDestinationParam = {
        name: AppDestinationName.PIN_DRAFTS
      };
      const dailyStoryParam: TestDestinationParam = {
        name: AppDestinationName.DAILY_STORY,
        id: '987654321'
      };
      const maxDailyStoryParam: TestDestinationParam = {
        name: AppDestinationName.DAILY_STORY,
        id: '9'.repeat(30)
      };
      const malformedDailyStoryParam: TestDestinationParam = {
        name: AppDestinationName.DAILY_STORY,
        id: '01'
      };
      const unexpectedSearchParam: TestDestinationParam = {
        name: AppDestinationName.SEARCH,
        query: 'ArkTS',
        unexpected: 'value'
      };
      const emptyCommentIdParam: TestDestinationParam = {
        name: AppDestinationName.COMMENT,
        contentType: 'answer',
        contentId: 'answer-1',
        commentId: ''
      };
      const commentParam: TestDestinationParam = {
        name: AppDestinationName.COMMENT,
        contentType: 'article',
        contentId: '123'
      };
      const answer = decodeAppDestination(AppDestinationName.ANSWER, answerParam);
      const probe = decodeAppDestination(AppDestinationName.READER_PROBE, probeParam);
      const login = decodeAppDestination(AppDestinationName.LOGIN, loginParam);
      const appearance = decodeAppDestination(AppDestinationName.APPEARANCE_SETTINGS, appearanceParam);
      const recommendationFilter = decodeAppDestination(AppDestinationName.RECOMMENDATION_FILTER_SETTINGS,
        recommendationFilterParam);
      const desktopLoginScan = decodeAppDestination(AppDestinationName.QR_DESKTOP_LOGIN_SCAN, desktopLoginScanParam);
      const writeAnswer = decodeAppDestination(AppDestinationName.WRITE_ANSWER, writeAnswerParam);
      const writePin = decodeAppDestination(AppDestinationName.WRITE_PIN, writePinParam);
      const pinDrafts = decodeAppDestination(AppDestinationName.PIN_DRAFTS, pinDraftsParam);
      const dailyStory = decodeAppDestination(AppDestinationName.DAILY_STORY, dailyStoryParam);
      const comment = decodeAppDestination(AppDestinationName.COMMENT, commentParam);
      const search: SearchDestination = { name: AppDestinationName.SEARCH, query: 'ArkTS' };
      const following: StatelessDestination = { name: AppDestinationName.FOLLOWING };
      const hot: StatelessDestination = { name: AppDestinationName.HOT };
      const pin: ContentDestination = { name: AppDestinationName.PIN, id: '1' };
      const people: ContentDestination = { name: AppDestinationName.PEOPLE, id: 'member-token' };

      expect(answer?.name).assertEqual(AppDestinationName.ANSWER);
      if (answer?.name === AppDestinationName.ANSWER) {
        expect(answer.id).assertEqual('2040633177593619876');
        expect(shouldReloadAfterAuthentication(answer)).assertTrue();
      }
      expect(probe?.name).assertEqual(AppDestinationName.READER_PROBE);
      if (dailyStory?.name === AppDestinationName.DAILY_STORY) {
        expect(dailyStory.id).assertEqual('987654321');
      }
      expect(shouldReloadAfterAuthentication(search)).assertTrue();
      expect(shouldReloadAfterAuthentication(following)).assertTrue();
      expect(shouldReloadAfterAuthentication(hot)).assertTrue();
      expect(shouldReloadAfterAuthentication(pin)).assertTrue();
      expect(shouldReloadAfterAuthentication(people)).assertTrue();
      if (login?.name === AppDestinationName.LOGIN) {
        expect(shouldReloadAfterAuthentication(login)).assertFalse();
      }
      expect(decodeAppDestination(AppDestinationName.ANSWER, mismatchedParam)).assertUndefined();
      expect(decodeAppDestination(AppDestinationName.ANSWER, emptyIdParam)).assertUndefined();
      expect(decodeAppDestination(AppDestinationName.READER_PROBE, unexpectedIdParam)).assertUndefined();
      expect(decodeAppDestination(AppDestinationName.DOMAIN_FIXTURE_PROBE, fixtureParam)?.name)
        .assertEqual(AppDestinationName.DOMAIN_FIXTURE_PROBE);
      expect(login?.name).assertEqual(AppDestinationName.LOGIN);
      expect(appearance?.name).assertEqual(AppDestinationName.APPEARANCE_SETTINGS);
      expect(recommendationFilter?.name).assertEqual(AppDestinationName.RECOMMENDATION_FILTER_SETTINGS);
      expect(desktopLoginScan?.name).assertEqual(AppDestinationName.QR_DESKTOP_LOGIN_SCAN);
      if (writeAnswer?.name === AppDestinationName.WRITE_ANSWER) {
        expect(writeAnswer.questionId).assertEqual('123');
        expect(writeAnswer.answerId).assertEqual('456');
        expect(shouldReloadAfterAuthentication(writeAnswer)).assertTrue();
      }
      if (writePin?.name === AppDestinationName.WRITE_PIN) {
        expect(writePin.draftId).assertEqual('01234567-89ab-4cde-8fab-0123456789ab');
        expect(shouldReloadAfterAuthentication(writePin)).assertTrue();
      }
      expect(pinDrafts?.name).assertEqual(AppDestinationName.PIN_DRAFTS);
      if (pinDrafts?.name === AppDestinationName.PIN_DRAFTS) {
        expect(shouldReloadAfterAuthentication(pinDrafts)).assertTrue();
      }
      expect(decodeAppDestination(AppDestinationName.SEARCH, unexpectedSearchParam)).assertUndefined();
      expect(decodeAppDestination(AppDestinationName.COMMENT, emptyCommentIdParam)).assertUndefined();
      expect(comment?.name).assertEqual(AppDestinationName.COMMENT);
      if (comment?.name === AppDestinationName.COMMENT) {
        expect(comment.contentType).assertEqual('article');
        expect(comment.contentId).assertEqual('123');
      }
    });

    it('rejectsUnsafeSearchAndDetailRuntimeParameters', 0, () => {
      const maxQuery: TestDestinationParam = {
        name: AppDestinationName.SEARCH,
        query: 'q'.repeat(MAX_SEARCH_QUERY_LENGTH)
      };
      const longQuery: TestDestinationParam = {
        name: AppDestinationName.SEARCH,
        query: 'q'.repeat(MAX_SEARCH_QUERY_LENGTH + 1)
      };
      const controlQuery: TestDestinationParam = {
        name: AppDestinationName.SEARCH,
        query: 'line\nbreak'
      };
      const maxId = '9'.repeat(30);
      const maxDailyStoryParam: TestDestinationParam = {
        name: AppDestinationName.DAILY_STORY,
        id: '9'.repeat(30)
      };
      const malformedDailyStoryParam: TestDestinationParam = {
        name: AppDestinationName.DAILY_STORY,
        id: '01'
      };
      const maxPinParam: TestDestinationParam = { name: AppDestinationName.PIN, id: '9'.repeat(30) };
      const malformedPinParam: TestDestinationParam = { name: AppDestinationName.PIN, id: '01' };
      const oversizedPinParam: TestDestinationParam = { name: AppDestinationName.PIN, id: '1'.repeat(31) };
      const peopleParam: TestDestinationParam = { name: AppDestinationName.PEOPLE, id: 'member_token-1' };
      const malformedPeopleParam: TestDestinationParam = { name: AppDestinationName.PEOPLE, id: '../member' };
      const oversizedPeopleParam: TestDestinationParam = { name: AppDestinationName.PEOPLE, id: 'a'.repeat(201) };
      const collectionsParam: TestDestinationParam = { name: AppDestinationName.COLLECTIONS, id: 'member_token-1' };
      const malformedCollectionsParam: TestDestinationParam = { name: AppDestinationName.COLLECTIONS, id: '../member' };
      const oversizedCollectionsParam: TestDestinationParam = { name: AppDestinationName.COLLECTIONS, id: 'a'.repeat(201) };
      const decodedMaxQuery = decodeAppDestination(AppDestinationName.SEARCH, maxQuery);
      expect(decodedMaxQuery?.name).assertEqual(AppDestinationName.SEARCH);
      if (decodedMaxQuery?.name === AppDestinationName.SEARCH) {
        expect(decodedMaxQuery.query).assertEqual(maxQuery.query);
      }
      expect(decodeAppDestination(AppDestinationName.SEARCH, longQuery)).assertUndefined();
      expect(decodeAppDestination(AppDestinationName.SEARCH, controlQuery)).assertUndefined();
      [AppDestinationName.QUESTION, AppDestinationName.ANSWER, AppDestinationName.ARTICLE]
        .forEach((name: AppDestinationName): void => {
          const maxIdParam: TestDestinationParam = { name: name, id: maxId };
          const oversizedIdParam: TestDestinationParam = { name: name, id: '1'.repeat(31) };
          const malformedIdParam: TestDestinationParam = { name: name, id: 'not-decimal' };
          expect(decodeAppDestination(name, maxIdParam)?.name).assertEqual(name);
          expect(decodeAppDestination(name, oversizedIdParam)).assertUndefined();
          expect(decodeAppDestination(name, malformedIdParam)).assertUndefined();
        });
      expect(decodeAppDestination(AppDestinationName.PIN, maxPinParam)?.name).assertEqual(AppDestinationName.PIN);
      expect(decodeAppDestination(AppDestinationName.PIN, malformedPinParam)).assertUndefined();
      expect(decodeAppDestination(AppDestinationName.PIN, oversizedPinParam)).assertUndefined();
      expect(decodeAppDestination(AppDestinationName.DAILY_STORY, maxDailyStoryParam)?.name)
        .assertEqual(AppDestinationName.DAILY_STORY);
      expect(decodeAppDestination(AppDestinationName.DAILY_STORY, malformedDailyStoryParam)).assertUndefined();
      expect(decodeAppDestination(AppDestinationName.PEOPLE, peopleParam)?.name).assertEqual(AppDestinationName.PEOPLE);
      expect(decodeAppDestination(AppDestinationName.PEOPLE, malformedPeopleParam)).assertUndefined();
      expect(decodeAppDestination(AppDestinationName.PEOPLE, oversizedPeopleParam)).assertUndefined();
      expect(decodeAppDestination(AppDestinationName.COLLECTIONS, collectionsParam)?.name)
        .assertEqual(AppDestinationName.COLLECTIONS);
      expect(decodeAppDestination(AppDestinationName.COLLECTIONS, malformedCollectionsParam)).assertUndefined();
      expect(decodeAppDestination(AppDestinationName.COLLECTIONS, oversizedCollectionsParam)).assertUndefined();
      [AppDestinationName.FOLLOWING, AppDestinationName.HOT, AppDestinationName.DAILY,
        AppDestinationName.BLOCKING_RULES, AppDestinationName.BLOCKED_FEED_HISTORY,
        AppDestinationName.READ_HISTORY, AppDestinationName.LOCAL_HISTORY, AppDestinationName.PIN_DRAFTS]
        .forEach((name: AppDestinationName): void => {
          const validParam: TestDestinationParam = { name: name };
          const invalidParam: TestDestinationParam = { name: name, id: 'unexpected' };
          expect(decodeAppDestination(name, validParam)?.name).assertEqual(name);
          expect(decodeAppDestination(name, invalidParam)).assertUndefined();
        });
    });

    it('mapsResolvedLinksToTypedStartupDestinations', 0, () => {
      const video = toAppDestination({ type: DeepLinkType.VIDEO, id: '123', query: '' });
      const search = toAppDestination({ type: DeepLinkType.SEARCH, id: '', query: 'ArkTS' });
      const home = toAppDestination({ type: DeepLinkType.MAIN_TABS, id: '', query: '' });

      expect(video.name).assertEqual(AppDestinationName.VIDEO);
      if (video.name === AppDestinationName.VIDEO) {
        expect(video.id).assertEqual('123');
      }
      expect(search.name).assertEqual(AppDestinationName.SEARCH);
      if (search.name === AppDestinationName.SEARCH) {
        expect(search.query).assertEqual('ArkTS');
      }
      expect(home.name).assertEqual(AppDestinationName.HOME);
    });

    it('pushesColdStartDestinationWhenPathStackIsNotInitialized', 0, () => {
      const destination: ContentDestination = {
        name: AppDestinationName.ANSWER,
        id: '12345'
      };
      const duplicate: ContentDestination = {
        name: AppDestinationName.ANSWER,
        id: '12345'
      };

      expect(shouldPushAppDestination(undefined, destination)).assertTrue();
      expect(shouldPushAppDestination(duplicate, destination)).assertFalse();
    });
  });
}
