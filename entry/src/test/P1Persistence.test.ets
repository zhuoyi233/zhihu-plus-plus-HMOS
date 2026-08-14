import { describe, expect, it } from '@ohos/hypium';
import {
  AppThemeMode,
  appPreferencesFailureMessage,
  DatabaseOpenPlan,
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

    it('plansOnlyContiguousPendingMigrations', 0, () => {
      expect(pendingSchemaVersions(0).join(',')).assertEqual('1,2,3,4');
      expect(pendingSchemaVersions(1).join(',')).assertEqual('2,3,4');
      expect(pendingSchemaVersions(2).join(',')).assertEqual('3,4');
      expect(pendingSchemaVersions(3).join(',')).assertEqual('4');
      expect(pendingSchemaVersions(4).length).assertEqual(0);
    });

    it('rejectsInvalidDatabaseVersions', 0, () => {
      expect(() => pendingSchemaVersions(-1)).assertThrowError('Unsupported schema version: -1');
      expect(() => pendingSchemaVersions(5)).assertThrowError('Unsupported schema version: 5');
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
