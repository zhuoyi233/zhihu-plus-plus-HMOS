import { relationalStore } from '@kit.ArkData';
import { AppDatabase } from './AppDatabase';

const KEYWORD_TABLE = 'blocked_keywords';
const USER_TABLE = 'blocked_users';
const TOPIC_TABLE = 'blocked_topics';
export const MAX_BLOCKING_RULES_PER_KIND: number = 1000;
export const MAX_BLOCKING_KEYWORD_LENGTH: number = 200;
export const MAX_BLOCKING_ID_LENGTH: number = 128;
export const MAX_BLOCKING_NAME_LENGTH: number = 200;
const MAX_BLOCKABLE_TEXT_LENGTH: number = 8192;
const CONTROL_CHARACTER_PATTERN: RegExp = /[\u0000-\u001F\u007F-\u009F]/;
const SAFE_IDENTIFIER_PATTERN: RegExp = /^[A-Za-z0-9_-]+$/;
const REGEX_BACK_REFERENCE_PATTERN: RegExp = /\\[1-9]/;
const REGEX_QUANTIFIED_GROUP_PATTERN: RegExp = /\)[*+?{]/;

export enum BlockingRuleKind {
  KEYWORD = 'keyword',
  USER = 'user',
  TOPIC = 'topic'
}

export interface BlockedKeywordRule {
  id: number;
  keyword: string;
  caseSensitive: boolean;
  isRegex: boolean;
  createdAt: number;
}

export interface BlockedUserRule {
  userId: string;
  userName: string;
  createdAt: number;
}

export interface BlockedTopicRule {
  topicId: string;
  topicName: string;
  createdAt: number;
}

export interface BlockingRuleSnapshot {
  keywords: Array<BlockedKeywordRule>;
  users: Array<BlockedUserRule>;
  topics: Array<BlockedTopicRule>;
}

export interface BlockingPreferences {
  keywordBlockingEnabled: boolean;
  userBlockingEnabled: boolean;
  topicBlockingEnabled: boolean;
  topicBlockingThreshold: number;
}

export interface BlockableContentSummary {
  title: string;
  excerpt: string;
  authorId?: string;
  topicIds: Array<string>;
}

export interface BlockingMatch {
  kind: BlockingRuleKind;
  ruleId: string;
  reason: string;
}

export interface BlockingRuleGateway {
  loadSnapshot(): Promise<BlockingRuleSnapshot>;
  addKeyword(keyword: string, caseSensitive: boolean, isRegex: boolean): Promise<void>;
  addUser(userId: string, userName: string): Promise<void>;
  addTopic(topicId: string, topicName: string): Promise<void>;
  deleteKeyword(id: number): Promise<void>;
  deleteUser(userId: string): Promise<void>;
  deleteTopic(topicId: string): Promise<void>;
  clear(kind: BlockingRuleKind): Promise<void>;
}

export interface BlockingPreferencesGateway {
  loadBlockingPreferences(): Promise<BlockingPreferences>;
  saveBlockingPreferences(value: BlockingPreferences): Promise<void>;
}

export interface ContentBlockingSession {
  match(content: BlockableContentSummary): BlockingMatch | undefined;
}

export interface ContentBlockingMatcher {
  createSession(): Promise<ContentBlockingSession>;
}

export function defaultBlockingPreferences(): BlockingPreferences {
  return {
    keywordBlockingEnabled: true,
    userBlockingEnabled: true,
    topicBlockingEnabled: true,
    topicBlockingThreshold: 1
  };
}

export function normalizeBlockingPreferences(value: BlockingPreferences): BlockingPreferences {
  const threshold = Number.isSafeInteger(value.topicBlockingThreshold) && value.topicBlockingThreshold > 0 &&
    value.topicBlockingThreshold <= 100 ? value.topicBlockingThreshold : 1;
  return {
    keywordBlockingEnabled: value.keywordBlockingEnabled,
    userBlockingEnabled: value.userBlockingEnabled,
    topicBlockingEnabled: value.topicBlockingEnabled,
    topicBlockingThreshold: threshold
  };
}

export function validateBlockingKeyword(keyword: string, isRegex: boolean): string {
  const normalized = keyword.trim();
  if (normalized.length === 0 || normalized.length > MAX_BLOCKING_KEYWORD_LENGTH ||
    CONTROL_CHARACTER_PATTERN.test(normalized)) {
    throw new Error('Blocking keyword must contain 1 to 200 safe characters');
  }
  if (isRegex && !isSafeBlockingRegex(normalized)) {
    throw new Error('Blocking regular expression is invalid or unsafe');
  }
  return normalized;
}

export function validateBlockingIdentifier(value: string): string {
  const normalized = value.trim();
  if (normalized.length === 0 || normalized.length > MAX_BLOCKING_ID_LENGTH ||
    !SAFE_IDENTIFIER_PATTERN.test(normalized)) {
    throw new Error('Blocking identifier must contain 1 to 128 safe characters');
  }
  return normalized;
}

export function validateBlockingName(value: string): string {
  const normalized = value.trim();
  if (normalized.length === 0 || normalized.length > MAX_BLOCKING_NAME_LENGTH ||
    CONTROL_CHARACTER_PATTERN.test(normalized)) {
    throw new Error('Blocking display name must contain 1 to 200 safe characters');
  }
  return normalized;
}

export function isSafeBlockingRegex(pattern: string): boolean {
  if (pattern.length === 0 || pattern.length > MAX_BLOCKING_KEYWORD_LENGTH || pattern.includes('(?') ||
    REGEX_BACK_REFERENCE_PATTERN.test(pattern) || REGEX_QUANTIFIED_GROUP_PATTERN.test(pattern) ||
    countRegexQuantifiers(pattern) > 1) {
    return false;
  }
  try {
    new RegExp(pattern);
    return true;
  } catch (_error) {
    return false;
  }
}

function countRegexQuantifiers(pattern: string): number {
  let count = 0;
  let escaped = false;
  let inCharacterClass = false;
  for (let index = 0; index < pattern.length; index += 1) {
    const character = pattern.charAt(index);
    if (escaped) {
      escaped = false;
    } else if (character === '\\') {
      escaped = true;
    } else if (character === '[') {
      inCharacterClass = true;
    } else if (character === ']') {
      inCharacterClass = false;
    } else if (!inCharacterClass && (character === '*' || character === '+' || character === '?' ||
      character === '{')) {
      count += 1;
    }
  }
  return count;
}

export function matchBlockingRules(content: BlockableContentSummary, snapshot: BlockingRuleSnapshot,
  preferences: BlockingPreferences): BlockingMatch | undefined {
  const normalizedPreferences = normalizeBlockingPreferences(preferences);
  if (normalizedPreferences.userBlockingEnabled && content.authorId !== undefined) {
    const authorId = content.authorId;
    const user = snapshot.users.find((candidate: BlockedUserRule): boolean => candidate.userId === authorId);
    if (user !== undefined) {
      return { kind: BlockingRuleKind.USER, ruleId: user.userId, reason: `屏蔽用户：${user.userName}` };
    }
  }

  if (normalizedPreferences.keywordBlockingEnabled) {
    const text = `${content.title}\n${content.excerpt}`.substring(0, MAX_BLOCKABLE_TEXT_LENGTH);
    const keyword = snapshot.keywords.find((candidate: BlockedKeywordRule): boolean =>
      matchesKeyword(text, candidate));
    if (keyword !== undefined) {
      return { kind: BlockingRuleKind.KEYWORD, ruleId: `${keyword.id}`, reason: '命中屏蔽关键词' };
    }
  }

  if (normalizedPreferences.topicBlockingEnabled) {
    const matchedTopicIds: Array<string> = [];
    snapshot.topics.forEach((topic: BlockedTopicRule): void => {
      if (content.topicIds.includes(topic.topicId) && !matchedTopicIds.includes(topic.topicId)) {
        matchedTopicIds.push(topic.topicId);
      }
    });
    if (matchedTopicIds.length >= normalizedPreferences.topicBlockingThreshold) {
      const topic = snapshot.topics.find((candidate: BlockedTopicRule): boolean =>
        candidate.topicId === matchedTopicIds[0]);
      return {
        kind: BlockingRuleKind.TOPIC,
        ruleId: matchedTopicIds[0],
        reason: `屏蔽话题：${topic?.topicName ?? '已屏蔽话题'}`
      };
    }
  }
  return undefined;
}

export class BlockingRuleMatcher implements ContentBlockingMatcher {
  private readonly rules: BlockingRuleGateway;
  private readonly preferences: BlockingPreferencesGateway;

  constructor(rules: BlockingRuleGateway, preferences: BlockingPreferencesGateway) {
    this.rules = rules;
    this.preferences = preferences;
  }

  async createSession(): Promise<ContentBlockingSession> {
    try {
      const snapshot = await this.rules.loadSnapshot();
      const preferences = await this.preferences.loadBlockingPreferences();
      return new BlockingRuleMatchSession(snapshot, preferences);
    } catch (_error) {
      throw new Error('Content blocking rules unavailable');
    }
  }
}

class BlockingRuleMatchSession implements ContentBlockingSession {
  private readonly snapshot: BlockingRuleSnapshot;
  private readonly preferences: BlockingPreferences;

  constructor(snapshot: BlockingRuleSnapshot, preferences: BlockingPreferences) {
    this.snapshot = copyBlockingRuleSnapshot(snapshot);
    this.preferences = normalizeBlockingPreferences(preferences);
  }

  match(content: BlockableContentSummary): BlockingMatch | undefined {
    return matchBlockingRules(content, this.snapshot, this.preferences);
  }
}

export class BlockingRuleStore implements BlockingRuleGateway {
  private readonly database: AppDatabase;
  private mutationQueue: Promise<void> = Promise.resolve();

  constructor(database: AppDatabase) {
    this.database = database;
  }

  async loadSnapshot(): Promise<BlockingRuleSnapshot> {
    await this.mutationQueue;
    return {
      keywords: await this.loadKeywords(),
      users: await this.loadUsers(),
      topics: await this.loadTopics()
    };
  }

  addKeyword(keyword: string, caseSensitive: boolean, isRegex: boolean): Promise<void> {
    const normalized = validateBlockingKeyword(keyword, isRegex);
    const createdAt = Date.now();
    return this.enqueueMutation(async (): Promise<void> => {
      const store = await this.database.open();
      const values: relationalStore.ValuesBucket = {
        keyword: normalized,
        case_sensitive: caseSensitive ? 1 : 0,
        is_regex: isRegex ? 1 : 0,
        created_at: createdAt
      };
      const rowId = await store.insert(KEYWORD_TABLE, values);
      if (rowId === -1) {
        throw new Error('Blocking keyword insert failed');
      }
      await store.executeSql('DELETE FROM blocked_keywords WHERE id NOT IN (' +
        'SELECT id FROM blocked_keywords ORDER BY created_at DESC, id DESC LIMIT 1000)');
    });
  }

  addUser(userId: string, userName: string): Promise<void> {
    const normalizedId = validateBlockingIdentifier(userId);
    const normalizedName = validateBlockingName(userName);
    const createdAt = Date.now();
    return this.enqueueMutation(async (): Promise<void> => {
      const store = await this.database.open();
      const values: relationalStore.ValuesBucket = {
        user_id: normalizedId,
        user_name: normalizedName,
        created_at: createdAt
      };
      const rowId = await store.insert(USER_TABLE, values, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      if (rowId === -1) {
        throw new Error('Blocked user insert failed');
      }
      await store.executeSql('DELETE FROM blocked_users WHERE user_id NOT IN (' +
        'SELECT user_id FROM blocked_users ORDER BY created_at DESC, user_id DESC LIMIT 1000)');
    });
  }

  addTopic(topicId: string, topicName: string): Promise<void> {
    const normalizedId = validateBlockingIdentifier(topicId);
    const normalizedName = validateBlockingName(topicName);
    const createdAt = Date.now();
    return this.enqueueMutation(async (): Promise<void> => {
      const store = await this.database.open();
      const values: relationalStore.ValuesBucket = {
        topic_id: normalizedId,
        topic_name: normalizedName,
        created_at: createdAt
      };
      const rowId = await store.insert(TOPIC_TABLE, values, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      if (rowId === -1) {
        throw new Error('Blocked topic insert failed');
      }
      await store.executeSql('DELETE FROM blocked_topics WHERE topic_id NOT IN (' +
        'SELECT topic_id FROM blocked_topics ORDER BY created_at DESC, topic_id DESC LIMIT 1000)');
    });
  }

  deleteKeyword(id: number): Promise<void> {
    if (!Number.isSafeInteger(id) || id <= 0) {
      return Promise.reject(new Error('Blocking keyword id is invalid'));
    }
    return this.enqueueMutation(async (): Promise<void> => {
      const store = await this.database.open();
      const predicates = new relationalStore.RdbPredicates(KEYWORD_TABLE).equalTo('id', id);
      await store.delete(predicates);
    });
  }

  deleteUser(userId: string): Promise<void> {
    const normalizedId = validateBlockingIdentifier(userId);
    return this.enqueueMutation(async (): Promise<void> => {
      const store = await this.database.open();
      const predicates = new relationalStore.RdbPredicates(USER_TABLE).equalTo('user_id', normalizedId);
      await store.delete(predicates);
    });
  }

  deleteTopic(topicId: string): Promise<void> {
    const normalizedId = validateBlockingIdentifier(topicId);
    return this.enqueueMutation(async (): Promise<void> => {
      const store = await this.database.open();
      const predicates = new relationalStore.RdbPredicates(TOPIC_TABLE).equalTo('topic_id', normalizedId);
      await store.delete(predicates);
    });
  }

  clear(kind: BlockingRuleKind): Promise<void> {
    return this.enqueueMutation(async (): Promise<void> => {
      const store = await this.database.open();
      const table = kind === BlockingRuleKind.KEYWORD ? KEYWORD_TABLE :
        kind === BlockingRuleKind.USER ? USER_TABLE : TOPIC_TABLE;
      await store.delete(new relationalStore.RdbPredicates(table));
    });
  }

  private enqueueMutation(operation: () => Promise<void>): Promise<void> {
    const result = this.mutationQueue.then(operation, operation);
    this.mutationQueue = result.then((): void => {}, (): void => {});
    return result;
  }

  private async loadKeywords(): Promise<Array<BlockedKeywordRule>> {
    const store = await this.database.open();
    const predicates = new relationalStore.RdbPredicates(KEYWORD_TABLE)
      .orderByDesc('created_at').orderByDesc('id').limitAs(MAX_BLOCKING_RULES_PER_KIND);
    const resultSet = await store.query(predicates, ['id', 'keyword', 'case_sensitive', 'is_regex', 'created_at']);
    const result: Array<BlockedKeywordRule> = [];
    try {
      if (resultSet.goToFirstRow()) {
        do {
          result.push({
            id: resultSet.getLong(resultSet.getColumnIndex('id')),
            keyword: resultSet.getString(resultSet.getColumnIndex('keyword')),
            caseSensitive: resultSet.getLong(resultSet.getColumnIndex('case_sensitive')) === 1,
            isRegex: resultSet.getLong(resultSet.getColumnIndex('is_regex')) === 1,
            createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at'))
          });
        } while (resultSet.goToNextRow());
      }
      return result;
    } finally {
      resultSet.close();
    }
  }

  private async loadUsers(): Promise<Array<BlockedUserRule>> {
    const store = await this.database.open();
    const predicates = new relationalStore.RdbPredicates(USER_TABLE)
      .orderByDesc('created_at').orderByDesc('user_id').limitAs(MAX_BLOCKING_RULES_PER_KIND);
    const resultSet = await store.query(predicates, ['user_id', 'user_name', 'created_at']);
    const result: Array<BlockedUserRule> = [];
    try {
      if (resultSet.goToFirstRow()) {
        do {
          result.push({
            userId: resultSet.getString(resultSet.getColumnIndex('user_id')),
            userName: resultSet.getString(resultSet.getColumnIndex('user_name')),
            createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at'))
          });
        } while (resultSet.goToNextRow());
      }
      return result;
    } finally {
      resultSet.close();
    }
  }

  private async loadTopics(): Promise<Array<BlockedTopicRule>> {
    const store = await this.database.open();
    const predicates = new relationalStore.RdbPredicates(TOPIC_TABLE)
      .orderByDesc('created_at').orderByDesc('topic_id').limitAs(MAX_BLOCKING_RULES_PER_KIND);
    const resultSet = await store.query(predicates, ['topic_id', 'topic_name', 'created_at']);
    const result: Array<BlockedTopicRule> = [];
    try {
      if (resultSet.goToFirstRow()) {
        do {
          result.push({
            topicId: resultSet.getString(resultSet.getColumnIndex('topic_id')),
            topicName: resultSet.getString(resultSet.getColumnIndex('topic_name')),
            createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at'))
          });
        } while (resultSet.goToNextRow());
      }
      return result;
    } finally {
      resultSet.close();
    }
  }
}

function matchesKeyword(text: string, rule: BlockedKeywordRule): boolean {
  if (rule.isRegex) {
    if (!isSafeBlockingRegex(rule.keyword)) {
      return false;
    }
    try {
      return new RegExp(rule.keyword, rule.caseSensitive ? '' : 'i').test(text);
    } catch (_error) {
      return false;
    }
  }
  return rule.caseSensitive ? text.includes(rule.keyword) : text.toLowerCase().includes(rule.keyword.toLowerCase());
}

function copyBlockingRuleSnapshot(snapshot: BlockingRuleSnapshot): BlockingRuleSnapshot {
  return {
    keywords: snapshot.keywords.map((rule: BlockedKeywordRule): BlockedKeywordRule => ({
      id: rule.id,
      keyword: rule.keyword,
      caseSensitive: rule.caseSensitive,
      isRegex: rule.isRegex,
      createdAt: rule.createdAt
    })),
    users: snapshot.users.map((rule: BlockedUserRule): BlockedUserRule => ({
      userId: rule.userId,
      userName: rule.userName,
      createdAt: rule.createdAt
    })),
    topics: snapshot.topics.map((rule: BlockedTopicRule): BlockedTopicRule => ({
      topicId: rule.topicId,
      topicName: rule.topicName,
      createdAt: rule.createdAt
    }))
  };
}
