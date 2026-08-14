import { relationalStore } from '@kit.ArkData';
import { AppDatabase } from './AppDatabase';
import { BlockingRuleKind } from './BlockingRuleStore';

const TABLE_NAME = 'blocked_feed_history';
export const MAX_BLOCKED_FEED_RECORDS: number = 500;
export const MAX_BLOCKED_RECORD_RULE_LENGTH: number = 200;
export const MAX_BLOCKED_RECORD_NAME_LENGTH: number = 200;
export const MAX_BLOCKED_RECORD_TITLE_LENGTH: number = 500;
export const MAX_BLOCKED_RECORD_KIND_LENGTH: number = 32;
export const MAX_BLOCKED_RECORD_CONTENT_ID_LENGTH: number = 200;
const CONTROL_CHARACTER_PATTERN: RegExp = /[\u0000-\u001F\u007F-\u009F]/;

export interface BlockedFeedRecord {
  id: number;
  kind: BlockingRuleKind;
  ruleId: string;
  ruleName: string;
  contentTitle: string;
  contentKind: string;
  contentId: string;
  blockedAt: number;
}

export interface BlockedFeedRecordInput {
  kind: BlockingRuleKind;
  ruleId: string;
  ruleName: string;
  contentTitle: string;
  contentKind: string;
  contentId: string;
  blockedAt: number;
}

export interface BlockedFeedHistoryGateway {
  queryRecent(limit?: number): Promise<Array<BlockedFeedRecord>>;
  insert(record: BlockedFeedRecordInput): Promise<void>;
  delete(id: number): Promise<void>;
  clear(): Promise<void>;
}

export class BlockedFeedHistoryStore implements BlockedFeedHistoryGateway {
  private readonly database: AppDatabase;
  private mutationQueue: Promise<void> = Promise.resolve();

  constructor(database: AppDatabase) {
    this.database = database;
  }

  async queryRecent(limit: number = MAX_BLOCKED_FEED_RECORDS): Promise<Array<BlockedFeedRecord>> {
    if (!Number.isSafeInteger(limit) || limit <= 0 || limit > MAX_BLOCKED_FEED_RECORDS) {
      throw new Error('Blocked feed history limit must be between 1 and 500');
    }
    await this.mutationQueue;
    const store = await this.database.open();
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME)
      .orderByDesc('blocked_at').orderByDesc('id').limitAs(limit);
    const resultSet = await store.query(predicates,
      ['id', 'kind', 'rule_id', 'rule_name', 'content_title', 'content_kind', 'content_id', 'blocked_at']);
    const result: Array<BlockedFeedRecord> = [];
    try {
      if (resultSet.goToFirstRow()) {
        do {
          result.push({
            id: resultSet.getLong(resultSet.getColumnIndex('id')),
            kind: resultSet.getString(resultSet.getColumnIndex('kind')) as BlockingRuleKind,
            ruleId: resultSet.getString(resultSet.getColumnIndex('rule_id')),
            ruleName: resultSet.getString(resultSet.getColumnIndex('rule_name')),
            contentTitle: resultSet.getString(resultSet.getColumnIndex('content_title')),
            contentKind: resultSet.getString(resultSet.getColumnIndex('content_kind')),
            contentId: resultSet.getString(resultSet.getColumnIndex('content_id')),
            blockedAt: resultSet.getLong(resultSet.getColumnIndex('blocked_at'))
          });
        } while (resultSet.goToNextRow());
      }
      return result;
    } finally {
      resultSet.close();
    }
  }

  insert(record: BlockedFeedRecordInput): Promise<void> {
    const normalized = validateBlockedFeedRecordInput(record);
    return this.enqueueMutation(async (): Promise<void> => {
      const store = await this.database.open();
      const values: relationalStore.ValuesBucket = {
        kind: normalized.kind,
        rule_id: normalized.ruleId,
        rule_name: normalized.ruleName,
        content_title: normalized.contentTitle,
        content_kind: normalized.contentKind,
        content_id: normalized.contentId,
        blocked_at: normalized.blockedAt
      };
      const rowId = await store.insert(TABLE_NAME, values);
      if (rowId === -1) {
        throw new Error('Blocked feed history insert failed');
      }
      await store.executeSql('DELETE FROM blocked_feed_history WHERE id NOT IN (' +
        'SELECT id FROM blocked_feed_history ORDER BY blocked_at DESC, id DESC LIMIT 500)');
    });
  }

  delete(id: number): Promise<void> {
    if (!Number.isSafeInteger(id) || id <= 0) {
      return Promise.reject(new Error('Blocked feed history id is invalid'));
    }
    return this.enqueueMutation(async (): Promise<void> => {
      const store = await this.database.open();
      const predicates = new relationalStore.RdbPredicates(TABLE_NAME).equalTo('id', id);
      await store.delete(predicates);
    });
  }

  clear(): Promise<void> {
    return this.enqueueMutation(async (): Promise<void> => {
      const store = await this.database.open();
      await store.delete(new relationalStore.RdbPredicates(TABLE_NAME));
    });
  }

  private enqueueMutation(operation: () => Promise<void>): Promise<void> {
    const result = this.mutationQueue.then(operation, operation);
    this.mutationQueue = result.then((): void => {}, (): void => {});
    return result;
  }
}

export function validateBlockedFeedRecordInput(record: BlockedFeedRecordInput): BlockedFeedRecordInput {
  const kind = normalizeBlockingRuleKind(record.kind);
  const ruleId = validateRecordField(record.ruleId, MAX_BLOCKED_RECORD_RULE_LENGTH, 'Blocking rule identifier');
  const ruleName = validateRecordField(record.ruleName, MAX_BLOCKED_RECORD_NAME_LENGTH, 'Blocking rule name');
  const contentTitle = validateRecordField(record.contentTitle, MAX_BLOCKED_RECORD_TITLE_LENGTH, 'Blocked content title');
  const contentKind = validateRecordField(record.contentKind, MAX_BLOCKED_RECORD_KIND_LENGTH, 'Blocked content kind');
  const contentId = validateRecordField(record.contentId, MAX_BLOCKED_RECORD_CONTENT_ID_LENGTH, 'Blocked content id');
  if (!Number.isSafeInteger(record.blockedAt) || record.blockedAt < 0 ||
    record.blockedAt > 8640000000000000) {
    throw new Error('Blocked timestamp must be a non-negative safe integer');
  }
  return {
    kind: kind,
    ruleId: ruleId,
    ruleName: ruleName,
    contentTitle: contentTitle,
    contentKind: contentKind,
    contentId: contentId,
    blockedAt: record.blockedAt
  };
}

function normalizeBlockingRuleKind(value: BlockingRuleKind): BlockingRuleKind {
  if (value === BlockingRuleKind.KEYWORD || value === BlockingRuleKind.USER ||
    value === BlockingRuleKind.TOPIC) {
    return value;
  }
  throw new Error('Blocking rule kind is invalid');
}

function validateRecordField(value: string, maxLength: number, label: string): string {
  const normalized = value.trim();
  if (normalized.length === 0 || normalized.length > maxLength ||
    CONTROL_CHARACTER_PATTERN.test(normalized)) {
    throw new Error(`${label} must contain 1 to ${maxLength} safe characters`);
  }
  return normalized;
}
