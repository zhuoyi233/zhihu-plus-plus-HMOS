import {
  jsonArray,
  jsonBoolean,
  jsonIntegerLiteral,
  jsonObject,
  jsonString,
  JsonArrayValue,
  JsonObjectValue,
  JsonValue,
  parseStrictJson
} from 'core';
import {
  BlockedKeywordRule,
  BlockedTopicRule,
  BlockedUserRule,
  BlockingRuleGateway,
  BlockingRuleSnapshot,
  validateBlockingIdentifier,
  validateBlockingKeyword,
  validateBlockingName
} from './BlockingRuleStore';

/**
 * 屏蔽词备份（参考上游 shared BlocklistBackup v2，仅保留鸿蒙端支持的关键词/用户/话题三类）。
 * 导出为 JSON 文本，导入时忽略不支持的字段（如 NLP 关键词）。
 */
export const BLOCKLIST_BACKUP_VERSION: number = 2;
export const MAX_BLOCKLIST_BACKUP_TEXT_LENGTH: number = 1024 * 1024;
export const MAX_BLOCKLIST_BACKUP_ENTRIES_PER_KIND: number = 1000;

export interface BlockedKeywordBackupEntry {
  keyword: string;
  caseSensitive: boolean;
  isRegex: boolean;
}

export interface BlockedUserBackupEntry {
  userId: string;
  userName: string;
}

export interface BlockedTopicBackupEntry {
  topicId: string;
  topicName: string;
}

export interface BlocklistBackupPayload {
  version: number;
  exportTime: number;
  keywords: Array<BlockedKeywordBackupEntry>;
  users: Array<BlockedUserBackupEntry>;
  topics: Array<BlockedTopicBackupEntry>;
}

export interface BlocklistBackupImportSummary {
  keywords: number;
  users: number;
  topics: number;
  skipped: number;
}

export function encodeBlocklistBackup(snapshot: BlockingRuleSnapshot): string {
  const payload: BlocklistBackupPayload = {
    version: BLOCKLIST_BACKUP_VERSION,
    exportTime: Date.now(),
    keywords: snapshot.keywords.map((rule: BlockedKeywordRule): BlockedKeywordBackupEntry => ({
      keyword: rule.keyword,
      caseSensitive: rule.caseSensitive,
      isRegex: rule.isRegex
    })),
    users: snapshot.users.map((rule: BlockedUserRule): BlockedUserBackupEntry => ({
      userId: rule.userId,
      userName: rule.userName
    })),
    topics: snapshot.topics.map((rule: BlockedTopicRule): BlockedTopicBackupEntry => ({
      topicId: rule.topicId,
      topicName: rule.topicName
    }))
  };
  return JSON.stringify(payload);
}

export function decodeBlocklistBackup(text: string): BlocklistBackupPayload {
  if (text.length === 0 || text.length > MAX_BLOCKLIST_BACKUP_TEXT_LENGTH) {
    throw new Error('Blocklist backup text length is invalid');
  }
  let root: JsonValue;
  try {
    root = parseStrictJson(text);
  } catch (_error) {
    throw new Error('Blocklist backup is not valid JSON');
  }
  const object = jsonObject(root);
  if (object === undefined) {
    throw new Error('Blocklist backup must be a JSON object');
  }
  const version = readBackupVersion(object);
  const exportTime = readBackupExportTime(object);
  return {
    version: version,
    exportTime: exportTime,
    keywords: readBackupKeywords(object),
    users: readBackupUsers(object),
    topics: readBackupTopics(object)
  };
}

export function importBlocklistBackup(text: string, rules: BlockingRuleGateway): Promise<BlocklistBackupImportSummary> {
  const payload = decodeBlocklistBackup(text);
  return importBlocklistBackupPayload(payload, rules);
}

export async function importBlocklistBackupPayload(payload: BlocklistBackupPayload,
  rules: BlockingRuleGateway): Promise<BlocklistBackupImportSummary> {
  const seenKeywords: Set<string> = new Set<string>();
  const pending: Array<Promise<void>> = [];
  let keywords = 0;
  let users = 0;
  let topics = 0;
  let skipped = 0;

  payload.keywords.forEach((entry: BlockedKeywordBackupEntry): void => {
    const key = `${entry.keyword}\u0000${entry.caseSensitive}\u0000${entry.isRegex}`;
    if (seenKeywords.has(key)) {
      return;
    }
    seenKeywords.add(key);
    try {
      const normalized = validateBlockingKeyword(entry.keyword, entry.isRegex);
      pending.push(rules.addKeyword(normalized, entry.caseSensitive, entry.isRegex));
      keywords += 1;
    } catch (_error) {
      skipped += 1;
    }
  });

  payload.users.forEach((entry: BlockedUserBackupEntry): void => {
    try {
      const userId = validateBlockingIdentifier(entry.userId);
      const userName = validateBlockingName(entry.userName);
      pending.push(rules.addUser(userId, userName));
      users += 1;
    } catch (_error) {
      skipped += 1;
    }
  });

  payload.topics.forEach((entry: BlockedTopicBackupEntry): void => {
    try {
      const topicId = validateBlockingIdentifier(entry.topicId);
      const topicName = validateBlockingName(entry.topicName);
      pending.push(rules.addTopic(topicId, topicName));
      topics += 1;
    } catch (_error) {
      skipped += 1;
    }
  });

  await Promise.all(pending);
  return { keywords: keywords, users: users, topics: topics, skipped: skipped };
}

function readBackupVersion(object: JsonObjectValue): number {
  const value = jsonIntegerLiteral(object.get('version'));
  if (value === undefined) {
    return BLOCKLIST_BACKUP_VERSION;
  }
  const parsed = Number(value);
  if (parsed < 1 || parsed > BLOCKLIST_BACKUP_VERSION) {
    throw new Error('Blocklist backup version is unsupported');
  }
  return parsed;
}

function readBackupExportTime(object: JsonObjectValue): number {
  const value = jsonIntegerLiteral(object.get('exportTime'));
  if (value === undefined) {
    return 0;
  }
  return Number(value);
}

function readBackupKeywords(object: JsonObjectValue): Array<BlockedKeywordBackupEntry> {
  return readBackupEntries(object, 'keywords', (entry: JsonObjectValue): BlockedKeywordBackupEntry => {
    const keyword = jsonString(entry.get('keyword'));
    if (keyword === undefined) {
      throw new Error('Blocklist backup keyword entry is invalid');
    }
    return {
      keyword: keyword,
      caseSensitive: jsonBoolean(entry.get('caseSensitive')) ?? false,
      isRegex: jsonBoolean(entry.get('isRegex')) ?? false
    };
  });
}

function readBackupUsers(object: JsonObjectValue): Array<BlockedUserBackupEntry> {
  return readBackupEntries(object, 'users', (entry: JsonObjectValue): BlockedUserBackupEntry => {
    const userId = jsonString(entry.get('userId'));
    const userName = jsonString(entry.get('userName'));
    if (userId === undefined || userName === undefined) {
      throw new Error('Blocklist backup user entry is invalid');
    }
    return { userId: userId, userName: userName };
  });
}

function readBackupTopics(object: JsonObjectValue): Array<BlockedTopicBackupEntry> {
  return readBackupEntries(object, 'topics', (entry: JsonObjectValue): BlockedTopicBackupEntry => {
    const topicId = jsonString(entry.get('topicId'));
    const topicName = jsonString(entry.get('topicName'));
    if (topicId === undefined || topicName === undefined) {
      throw new Error('Blocklist backup topic entry is invalid');
    }
    return { topicId: topicId, topicName: topicName };
  });
}

function readBackupEntries<T>(object: JsonObjectValue, field: string, decode: (entry: JsonObjectValue) => T):
  Array<T> {
  const value = object.get(field);
  if (value === undefined) {
    return [];
  }
  if (!(value instanceof JsonArrayValue) || value.items.length > MAX_BLOCKLIST_BACKUP_ENTRIES_PER_KIND) {
    throw new Error(`Blocklist backup ${field} is invalid`);
  }
  const result: Array<T> = [];
  value.items.forEach((item: JsonValue): void => {
    const entry = jsonObject(item);
    if (entry === undefined) {
      throw new Error(`Blocklist backup ${field} entry is invalid`);
    }
    result.push(decode(entry));
  });
  return result;
}
