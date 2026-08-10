export interface SchemaMigration {
  fromVersion: number;
  toVersion: number;
  statements: Array<string>;
}

export const CURRENT_SCHEMA_VERSION: number = 2;

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
  throw new Error(`Unsupported schema target version: ${targetVersion}`);
}
