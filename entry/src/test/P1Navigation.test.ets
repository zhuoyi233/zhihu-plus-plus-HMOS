import { describe, expect, it } from '@ohos/hypium';
import {
  ContentDestination,
  decodeP1Destination,
  DeepLinkType,
  InfrastructureDestination,
  isP1DestinationName,
  P1DestinationName,
  SearchDestination,
  shouldPushP1Destination,
  toP1Destination
} from 'core';

interface TestDestinationParam {
  name: string;
  id?: string;
  contentId?: string;
  commentId?: string;
  query?: string;
  unexpected?: string;
}

export default function p1NavigationTest(): void {
  describe('p1NavigationTest', () => {
    it('recognizesEveryDeclaredDestinationName', 0, () => {
      const names: Array<P1DestinationName> = [
        P1DestinationName.HOME,
        P1DestinationName.QUESTION,
        P1DestinationName.ANSWER,
        P1DestinationName.ARTICLE,
        P1DestinationName.VIDEO,
        P1DestinationName.PIN,
        P1DestinationName.PEOPLE,
        P1DestinationName.COMMENT,
        P1DestinationName.SEARCH,
        P1DestinationName.COLLECTION,
        P1DestinationName.NOTIFICATION,
        P1DestinationName.SETTINGS,
        P1DestinationName.TECHNICAL_LAB,
        P1DestinationName.READER_PROBE,
        P1DestinationName.IMAGE_PROBE,
        P1DestinationName.DATABASE_PROBE,
        P1DestinationName.DEEP_LINK_PROBE,
        P1DestinationName.QR_SCAN_PROBE,
        P1DestinationName.BACKGROUND_TASK_PROBE,
        P1DestinationName.DOMAIN_FIXTURE_PROBE
      ];

      expect(names.every((name: P1DestinationName) => isP1DestinationName(name))).assertTrue();
      expect(isP1DestinationName('UnknownProbe')).assertFalse();
      expect(isP1DestinationName('')).assertFalse();
    });

    it('keepsContentIdsAndSearchQueriesAsStrings', 0, () => {
      const answer: ContentDestination = {
        name: P1DestinationName.ANSWER,
        id: '2040633177593619876'
      };
      const search: SearchDestination = {
        name: P1DestinationName.SEARCH,
        query: 'HarmonyOS ArkTS'
      };

      expect(answer.id).assertEqual('2040633177593619876');
      expect(search.query).assertEqual('HarmonyOS ArkTS');
    });

    it('modelsInfrastructurePagesWithoutBooleanPageFlags', 0, () => {
      const settings: InfrastructureDestination = { name: P1DestinationName.SETTINGS };
      const laboratory: InfrastructureDestination = { name: P1DestinationName.TECHNICAL_LAB };

      expect(settings.name).assertEqual(P1DestinationName.SETTINGS);
      expect(laboratory.name).assertEqual(P1DestinationName.TECHNICAL_LAB);
    });

    it('decodesOnlyMatchingRuntimeDestinations', 0, () => {
      const answerParam: TestDestinationParam = {
        name: P1DestinationName.ANSWER,
        id: '2040633177593619876'
      };
      const probeParam: TestDestinationParam = {
        name: P1DestinationName.READER_PROBE
      };
      const mismatchedParam: TestDestinationParam = {
        name: P1DestinationName.ARTICLE,
        id: '1'
      };
      const emptyIdParam: TestDestinationParam = {
        name: P1DestinationName.ANSWER,
        id: '   '
      };
      const unexpectedIdParam: TestDestinationParam = {
        name: P1DestinationName.READER_PROBE,
        id: 'unexpected'
      };
      const fixtureParam: TestDestinationParam = {
        name: P1DestinationName.DOMAIN_FIXTURE_PROBE
      };
      const unexpectedSearchParam: TestDestinationParam = {
        name: P1DestinationName.SEARCH,
        query: 'ArkTS',
        unexpected: 'value'
      };
      const emptyCommentIdParam: TestDestinationParam = {
        name: P1DestinationName.COMMENT,
        contentId: 'answer-1',
        commentId: ''
      };
      const answer = decodeP1Destination(P1DestinationName.ANSWER, answerParam);
      const probe = decodeP1Destination(P1DestinationName.READER_PROBE, probeParam);

      expect(answer?.name).assertEqual(P1DestinationName.ANSWER);
      expect((answer as ContentDestination).id).assertEqual('2040633177593619876');
      expect(probe?.name).assertEqual(P1DestinationName.READER_PROBE);
      expect(decodeP1Destination(P1DestinationName.ANSWER, mismatchedParam)).assertUndefined();
      expect(decodeP1Destination(P1DestinationName.ANSWER, emptyIdParam)).assertUndefined();
      expect(decodeP1Destination(P1DestinationName.READER_PROBE, unexpectedIdParam)).assertUndefined();
      expect(decodeP1Destination(P1DestinationName.DOMAIN_FIXTURE_PROBE, fixtureParam)?.name)
        .assertEqual(P1DestinationName.DOMAIN_FIXTURE_PROBE);
      expect(decodeP1Destination(P1DestinationName.SEARCH, unexpectedSearchParam)).assertUndefined();
      expect(decodeP1Destination(P1DestinationName.COMMENT, emptyCommentIdParam)).assertUndefined();
    });

    it('mapsResolvedLinksToTypedStartupDestinations', 0, () => {
      const video = toP1Destination({ type: DeepLinkType.VIDEO, id: '123', query: '' });
      const search = toP1Destination({ type: DeepLinkType.SEARCH, id: '', query: 'ArkTS' });
      const home = toP1Destination({ type: DeepLinkType.MAIN_TABS, id: '', query: '' });

      expect(video.name).assertEqual(P1DestinationName.VIDEO);
      expect((video as ContentDestination).id).assertEqual('123');
      expect(search.name).assertEqual(P1DestinationName.SEARCH);
      expect((search as SearchDestination).query).assertEqual('ArkTS');
      expect(home.name).assertEqual(P1DestinationName.HOME);
    });

    it('pushesColdStartDestinationWhenPathStackIsNotInitialized', 0, () => {
      const destination: ContentDestination = {
        name: P1DestinationName.ANSWER,
        id: '12345'
      };
      const duplicate: ContentDestination = {
        name: P1DestinationName.ANSWER,
        id: '12345'
      };

      expect(shouldPushP1Destination(undefined, destination)).assertTrue();
      expect(shouldPushP1Destination(duplicate, destination)).assertFalse();
    });
  });
}
