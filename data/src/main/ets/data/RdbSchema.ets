export interface SchemaMigration {
  fromVersion: number;
  toVersion: number;
  statements: Array<string>;
}

export const CURRENT_SCHEMA_VERSION: number = 4;

export function schemaMigrationTo(targetVersion: number): SchemaMigration {
  if (targetVersion === 1) {
    return {
      fromVersion: 0,
      toVersion: 1,
      statements: [
        'CREATE TABLE IF NOT EXISTS opened_content (' +
          'content_key TEXT PRIMARY KEY, opened_at INTEGER NOT NULL)'
      ]
    };
  }
  if (targetVersion === 2) {
    return {
      fromVersion: 1,
      toVersion: 2,
      statements: [
        "ALTER TABLE opened_content ADD COLUMN content_type TEXT NOT NULL DEFAULT 'unknown'",
        'CREATE INDEX IF NOT EXISTS index_opened_content_opened_at ON opened_content(opened_at)'
      ]
    };
  }
  if (targetVersion === 3) {
    return {
      fromVersion: 2,
      toVersion: 3,
      statements: [
        'CREATE TABLE IF NOT EXISTS blocked_keywords (' +
          'id INTEGER PRIMARY KEY AUTOINCREMENT, keyword TEXT NOT NULL, ' +
          'case_sensitive INTEGER NOT NULL, is_regex INTEGER NOT NULL, created_at INTEGER NOT NULL)',
        'CREATE INDEX IF NOT EXISTS index_blocked_keywords_created_at ON blocked_keywords(created_at)',
        'CREATE TABLE IF NOT EXISTS blocked_users (' +
          'user_id TEXT PRIMARY KEY, user_name TEXT NOT NULL, created_at INTEGER NOT NULL)',
        'CREATE INDEX IF NOT EXISTS index_blocked_users_created_at ON blocked_users(created_at)',
        'CREATE TABLE IF NOT EXISTS blocked_topics (' +
          'topic_id TEXT PRIMARY KEY, topic_name TEXT NOT NULL, created_at INTEGER NOT NULL)',
        'CREATE INDEX IF NOT EXISTS index_blocked_topics_created_at ON blocked_topics(created_at)'
      ]
    };
  }
  if (targetVersion === 4) {
    return {
      fromVersion: 3,
      toVersion: 4,
      statements: [
        'CREATE TABLE IF NOT EXISTS blocked_feed_history (' +
          'id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, rule_id TEXT NOT NULL, ' +
          'rule_name TEXT NOT NULL, content_title TEXT NOT NULL, content_kind TEXT NOT NULL, ' +
          'content_id TEXT NOT NULL, blocked_at INTEGER NOT NULL)',
        'CREATE INDEX IF NOT EXISTS index_blocked_feed_history_blocked_at ' +
          'ON blocked_feed_history(blocked_at)'
      ]
    };
  }
  throw new Error(`Unsupported schema target version: ${targetVersion}`);
}
