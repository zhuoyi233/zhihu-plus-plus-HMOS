import { describe, expect, it } from '@ohos/hypium';
import { CURRENT_SCHEMA_VERSION, schemaMigrationTo } from 'data';

export default function rdbSchemaTest(): void {
  describe('rdbSchemaTest', () => {
    it('definesContiguousSchemaVersions', 0, () => {
      const first = schemaMigrationTo(1);
      const second = schemaMigrationTo(2);
      const third = schemaMigrationTo(3);
      const fourth = schemaMigrationTo(4);
      const fifth = schemaMigrationTo(5);
      const sixth = schemaMigrationTo(6);

      expect(CURRENT_SCHEMA_VERSION).assertEqual(6);
      expect(first.fromVersion).assertEqual(0);
      expect(first.toVersion).assertEqual(second.fromVersion);
      expect(second.toVersion).assertEqual(third.fromVersion);
      expect(third.toVersion).assertEqual(fourth.fromVersion);
      expect(fourth.toVersion).assertEqual(fifth.fromVersion);
      expect(fifth.toVersion).assertEqual(sixth.fromVersion);
      expect(sixth.toVersion).assertEqual(CURRENT_SCHEMA_VERSION);
    });

    it('addsThreeLocalBlockingRuleTablesWithoutSensitiveContentColumns', 0, () => {
      const migration = schemaMigrationTo(3);
      const sql = migration.statements.join(' ');

      expect(migration.statements.length).assertEqual(6);
      expect(sql.includes('blocked_keywords')).assertTrue();
      expect(sql.includes('blocked_users')).assertTrue();
      expect(sql.includes('blocked_topics')).assertTrue();
      expect(sql.includes('content_html')).assertFalse();
      expect(sql.includes('cookie')).assertFalse();
    });

    it('keepsDataWhileAddingContentType', 0, () => {
      const migration = schemaMigrationTo(2);

      expect(migration.statements.length).assertEqual(2);
      expect(migration.statements[0].includes('ALTER TABLE opened_content')).assertTrue();
      expect(migration.statements[0].includes("DEFAULT 'unknown'")).assertTrue();
      expect(migration.statements[1].includes('CREATE INDEX')).assertTrue();
    });

    it('addsBlockedFeedHistoryTableWithoutSensitiveContentColumns', 0, () => {
      const migration = schemaMigrationTo(4);
      const sql = migration.statements.join(' ');

      expect(migration.statements.length).assertEqual(2);
      expect(sql.includes('blocked_feed_history')).assertTrue();
      expect(sql.includes('rule_id')).assertTrue();
      expect(sql.includes('rule_name')).assertTrue();
      expect(sql.includes('content_html')).assertFalse();
      expect(sql.includes('cookie')).assertFalse();
    });

    it('addsDraftMetadataWithoutPlaintextOrCredentialColumns', 0, () => {
      const migration = schemaMigrationTo(5);
      const sql = migration.statements.join(' ');

      expect(migration.statements.length).assertEqual(2);
      expect(sql.includes('content_drafts')).assertTrue();
      expect(sql.includes('account_key')).assertTrue();
      expect(sql.includes('image_refs')).assertTrue();
      expect(sql.includes('topic_refs')).assertTrue();
      expect(sql.includes('content_html')).assertFalse();
      expect(sql.includes('cookie')).assertFalse();
      expect(sql.includes('upload_token')).assertFalse();
    });

    it('addsHistoryTitleColumnWithoutSensitiveContent', 0, () => {
      const migration = schemaMigrationTo(6);
      const sql = migration.statements.join(' ');

      expect(migration.statements.length).assertEqual(1);
      expect(sql.includes('ALTER TABLE opened_content')).assertTrue();
      expect(sql.includes('title')).assertTrue();
      expect(sql.includes('cookie')).assertFalse();
      expect(sql.includes('content_html')).assertFalse();
    });

    it('rejectsUnknownSchemaVersion', 0, () => {
      let rejected = false;
      try {
        schemaMigrationTo(7);
      } catch (_error) {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });
  });
}
