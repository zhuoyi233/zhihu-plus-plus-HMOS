import { describe, expect, it } from '@ohos/hypium';
import { CURRENT_SCHEMA_VERSION, schemaMigrationTo } from '../main/ets/data/RdbSchema';

export default function rdbSchemaTest(): void {
  describe('rdbSchemaTest', () => {
    it('definesContiguousSchemaVersions', 0, () => {
      const first = schemaMigrationTo(1);
      const second = schemaMigrationTo(2);

      expect(CURRENT_SCHEMA_VERSION).assertEqual(2);
      expect(first.fromVersion).assertEqual(0);
      expect(first.toVersion).assertEqual(second.fromVersion);
      expect(second.toVersion).assertEqual(CURRENT_SCHEMA_VERSION);
    });

    it('keepsDataWhileAddingContentType', 0, () => {
      const migration = schemaMigrationTo(2);

      expect(migration.statements.length).assertEqual(2);
      expect(migration.statements[0].includes('ALTER TABLE opened_content')).assertTrue();
      expect(migration.statements[0].includes("DEFAULT 'unknown'")).assertTrue();
      expect(migration.statements[1].includes('CREATE INDEX')).assertTrue();
    });

    it('rejectsUnknownSchemaVersion', 0, () => {
      let rejected = false;
      try {
        schemaMigrationTo(3);
      } catch (_error) {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });
  });
}
