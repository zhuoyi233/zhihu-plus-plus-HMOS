import { describe, expect, it } from '@ohos/hypium';
import {
  allAnswerDoubleTapActions,
  answerDoubleTapActionLabel,
  answerDoubleTapActionPreferenceValue,
  AnswerDoubleTapAction,
  AppThemeMode,
  appPreferencesFailureMessage,
  DatabaseOpenPlan,
  decodeAnswerDoubleTapAction,
  decodeAppThemeMode,
  pendingSchemaVersions,
  planDatabaseOpen
} from 'data';

export default function p1PersistenceTest(): void {
  describe('p1PersistenceTest', () => {
    it('defaultsUnknownThemeValuesToSystem', 0, () => {
      expect(decodeAppThemeMode(AppThemeMode.SYSTEM)).assertEqual(AppThemeMode.SYSTEM);
      expect(decodeAppThemeMode('dark')).assertEqual(AppThemeMode.SYSTEM);
      expect(decodeAppThemeMode(99)).assertEqual(AppThemeMode.SYSTEM);
    });

    it('decodesPersistedThemeValues', 0, () => {
      expect(decodeAppThemeMode(AppThemeMode.LIGHT)).assertEqual(AppThemeMode.LIGHT);
      expect(decodeAppThemeMode(AppThemeMode.DARK)).assertEqual(AppThemeMode.DARK);
    });

    it('decodesAnswerDoubleTapActionPreferenceValues', 0, () => {
      expect(decodeAnswerDoubleTapAction('none')).assertEqual(AnswerDoubleTapAction.NONE);
      expect(decodeAnswerDoubleTapAction('ask')).assertEqual(AnswerDoubleTapAction.ASK);
      expect(decodeAnswerDoubleTapAction('voteUp')).assertEqual(AnswerDoubleTapAction.VOTE_UP);
      expect(decodeAnswerDoubleTapAction('openComments')).assertEqual(AnswerDoubleTapAction.OPEN_COMMENTS);
      expect(decodeAnswerDoubleTapAction('toggleImmersive')).assertEqual(AnswerDoubleTapAction.TOGGLE_IMMERSIVE);
      // 缺失/未知值一律回退 Ask（对齐上游 fromPreference）。
      expect(decodeAnswerDoubleTapAction('')).assertEqual(AnswerDoubleTapAction.ASK);
      expect(decodeAnswerDoubleTapAction('unknown')).assertEqual(AnswerDoubleTapAction.ASK);
      expect(decodeAnswerDoubleTapAction(123)).assertEqual(AnswerDoubleTapAction.ASK);
    });

    it('roundTripsAnswerDoubleTapActionPreferenceValues', 0, () => {
      const actions = allAnswerDoubleTapActions();
      expect(actions.length).assertEqual(5);
      actions.forEach((action: AnswerDoubleTapAction): void => {
        expect(decodeAnswerDoubleTapAction(answerDoubleTapActionPreferenceValue(action))).assertEqual(action);
      });
      expect(answerDoubleTapActionLabel(AnswerDoubleTapAction.ASK)).assertEqual('询问并记住');
      expect(answerDoubleTapActionLabel(AnswerDoubleTapAction.VOTE_UP)).assertEqual('点赞');
    });

    it('plansOnlyContiguousPendingMigrations', 0, () => {
      expect(pendingSchemaVersions(0).join(',')).assertEqual('1,2,3,4,5,6');
      expect(pendingSchemaVersions(1).join(',')).assertEqual('2,3,4,5,6');
      expect(pendingSchemaVersions(2).join(',')).assertEqual('3,4,5,6');
      expect(pendingSchemaVersions(3).join(',')).assertEqual('4,5,6');
      expect(pendingSchemaVersions(4).join(',')).assertEqual('5,6');
      expect(pendingSchemaVersions(5).join(',')).assertEqual('6');
      expect(pendingSchemaVersions(6).length).assertEqual(0);
    });

    it('rejectsInvalidDatabaseVersions', 0, () => {
      expect(() => pendingSchemaVersions(-1)).assertThrowError('Unsupported schema version: -1');
      expect(() => pendingSchemaVersions(7)).assertThrowError('Unsupported schema version: 7');
      expect(() => pendingSchemaVersions(1.5)).assertThrowError('Unsupported schema version: 1.5');
    });

    it('prioritizesClosingBeforeOpeningOrReturningAStore', 0, () => {
      expect(planDatabaseOpen({ hasStore: true, hasOpening: false, hasClosing: true }))
        .assertEqual(DatabaseOpenPlan.WAIT_FOR_CLOSE);
      expect(planDatabaseOpen({ hasStore: false, hasOpening: true, hasClosing: false }))
        .assertEqual(DatabaseOpenPlan.WAIT_FOR_OPEN);
      expect(planDatabaseOpen({ hasStore: true, hasOpening: false, hasClosing: false }))
        .assertEqual(DatabaseOpenPlan.RETURN_STORE);
      expect(planDatabaseOpen({ hasStore: false, hasOpening: false, hasClosing: false }))
        .assertEqual(DatabaseOpenPlan.START_OPEN);
    });

    it('normalizesNonBusinessAndMissingPreferenceErrors', 0, () => {
      expect(appPreferencesFailureMessage('Theme load', new Error('broken')))
        .assertEqual('Theme load failed: broken');
      expect(appPreferencesFailureMessage('Theme load', null)).assertEqual('Theme load failed');
      expect(appPreferencesFailureMessage('Theme load', undefined)).assertEqual('Theme load failed');
    });
  });
}
