import { describe, expect, it } from '@ohos/hypium';
import {
  ContentDestination,
  isP1DestinationName,
  P1DestinationName,
  SearchDestination,
  ShellDestination
} from '../main/ets/navigation/P1Destination';

export default function p1NavigationTest(): void {
  describe('p1NavigationTest', () => {
    it('recognizesEveryDeclaredDestinationName', 0, () => {
      const names: Array<P1DestinationName> = [
        P1DestinationName.HOME,
        P1DestinationName.QUESTION,
        P1DestinationName.ANSWER,
        P1DestinationName.ARTICLE,
        P1DestinationName.PIN,
        P1DestinationName.PEOPLE,
        P1DestinationName.COMMENT,
        P1DestinationName.SEARCH,
        P1DestinationName.COLLECTION,
        P1DestinationName.NOTIFICATION,
        P1DestinationName.SETTINGS,
        P1DestinationName.TECHNICAL_LAB
      ];

      expect(names.every((name: P1DestinationName) => isP1DestinationName(name))).assertTrue();
      expect(isP1DestinationName('ReaderProbe')).assertFalse();
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
      const settings: ShellDestination = { name: P1DestinationName.SETTINGS };
      const laboratory: ShellDestination = { name: P1DestinationName.TECHNICAL_LAB };

      expect(settings.name).assertEqual(P1DestinationName.SETTINGS);
      expect(laboratory.name).assertEqual(P1DestinationName.TECHNICAL_LAB);
    });
  });
}
