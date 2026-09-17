import { relationalStore } from '@kit.ArkData';
import { AppDatabase } from './AppDatabase';
import {
  defaultRecommendationFilterPreferences,
  QualityFilterMode,
  RecommendationFilterPreferences,
  RecommendationFilterPreferencesGateway
} from '../preferences/RecommendationFilterPreferences';

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
  TOPIC = 'topic',
  QUALITY = 'quality',
  SMART = 'smart',
  ADVERTISEMENT = 'advertisement',
  PAID = 'paid',
  REVERSE = 'reverse'
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
  contentId?: string;
  contentKind?: string;
  title: string;
  excerpt: string;
  content?: string;
  url?: string;
  authorId?: string;
  authorName?: string;
  questionAuthorId?: string;
  questionAuthorName?: string;
  authorFollowerCount?: number;
  authorIsFollowing?: boolean;
  topicIds: Array<string>;
  voteupCount?: number;
  answerCount?: number;
  followerCount?: number;
  isPaid?: boolean;
  viewCount?: number;
  opened?: boolean;
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
  qualityReason?(content: BlockableContentSummary): string | undefined;
  flush?(): Promise<void>;
}

export interface ContentBlockingMatcher {
  createSession(): Promise<ContentBlockingSession>;
}

export enum ContentBlockingStrategy {
  RULES_ONLY = 'rules_only',
  HOME_FULL = 'home_full'
}

export interface ContentFilterRuntimeSnapshot {
  viewCounts: Record<string, number>;
  openedKeys: Array<string>;
}

export interface ContentFilterOutcome {
  content: BlockableContentSummary;
  match?: BlockingMatch;
}

export interface ContentFilterStats {
  totalSeen: number;
  totalFiltered: number;
  filterRate: number;
  lastFilteredAt: number;
}

export interface ContentFilterRuntimeGateway {
  loadSnapshot(): Promise<ContentFilterRuntimeSnapshot>;
  recordOutcomes(outcomes: Array<ContentFilterOutcome>): Promise<void>;
  loadStats(): Promise<ContentFilterStats>;
  cleanupOldData(cutoff: number): Promise<void>;
  clearAllData(): Promise<void>;
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
    const user = snapshot.users.find((candidate: BlockedUserRule): boolean => candidate.userId === content.authorId);
    if (user !== undefined) {
      return { kind: BlockingRuleKind.USER, ruleId: user.userId, reason: `屏蔽用户：${user.userName}` };
    }
  }
  if (normalizedPreferences.userBlockingEnabled && content.questionAuthorId !== undefined) {
    const user = snapshot.users.find((candidate: BlockedUserRule): boolean =>
      candidate.userId === content.questionAuthorId);
    if (user !== undefined) {
      return { kind: BlockingRuleKind.USER, ruleId: user.userId, reason: `屏蔽提问者：${user.userName}` };
    }
  }

  if (normalizedPreferences.keywordBlockingEnabled) {
    const text = boundedBlockableText(content);
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

function boundedBlockableText(content: BlockableContentSummary): string {
  const fields: Array<string> = [content.title, content.excerpt, content.content ?? ''];
  let result = '';
  for (let index = 0; index < fields.length; index += 1) {
    const separatorLength = result.length > 0 ? 1 : 0;
    const remaining = MAX_BLOCKABLE_TEXT_LENGTH - result.length - separatorLength;
    if (remaining <= 0) break;
    const field = fields[index].substring(0, remaining);
    result = result.length === 0 ? field : `${result}\n${field}`;
  }
  return result;
}

export function qualityFilterReason(content: BlockableContentSummary,
  preferences: RecommendationFilterPreferences): string | undefined {
  if (preferences.qualityFilterMode === QualityFilterMode.OFF || content.authorIsFollowing === true) {
    return undefined;
  }
  if (content.contentKind === 'answer' && content.authorIsFollowing === false &&
    content.voteupCount !== undefined && content.voteupCount < preferences.answerVoteupThreshold) {
    return `回答赞同数低于 ${preferences.answerVoteupThreshold}`;
  }
  if (content.contentKind === 'article' && content.authorIsFollowing === false &&
    ((content.voteupCount !== undefined && content.voteupCount < preferences.articleVoteupThreshold) ||
      (content.authorFollowerCount !== undefined &&
        content.authorFollowerCount < preferences.articleFollowersThreshold))) {
    return '文章赞同数或作者粉丝数低于阈值';
  }
  if (content.contentKind === 'video' && content.authorIsFollowing === false &&
    content.voteupCount !== undefined && content.voteupCount < preferences.videoVoteThreshold &&
    content.authorFollowerCount !== undefined && content.authorFollowerCount < preferences.videoFollowersThreshold) {
    return '视频赞同数或作者粉丝数低于阈值';
  }
  if (content.contentKind === 'question' && content.answerCount !== undefined &&
    content.answerCount < preferences.questionAnswerThreshold && content.followerCount !== undefined &&
    content.followerCount < preferences.questionFollowersThreshold) {
    return '问题回答数或关注数低于阈值';
  }
  return undefined;
}

export function promotionalFilterReason(content: BlockableContentSummary,
  preferences: RecommendationFilterPreferences): BlockingMatch | undefined {
  if (preferences.blockPaidContent && content.isPaid === true) {
    return { kind: BlockingRuleKind.PAID, ruleId: 'paid', reason: '知乎盐选付费内容' };
  }
  const text = `${content.url ?? ''}\n${content.content ?? ''}\n${content.excerpt}`;
  if (preferences.blockZhihuAdPlatform && text.includes('xg.zhihu.com')) {
    return { kind: BlockingRuleKind.ADVERTISEMENT, ruleId: 'xg.zhihu.com', reason: '知乎广告平台内容' };
  }
  if (preferences.blockZhihuSchool && (text.includes('d.zhihu.com') || text.includes('data-edu-card-id'))) {
    return { kind: BlockingRuleKind.ADVERTISEMENT, ruleId: 'zhihu-school', reason: '知乎学堂内容' };
  }
  if (preferences.blockWeChatOfficialAccount && text.includes('mp.weixin.qq.com')) {
    return { kind: BlockingRuleKind.ADVERTISEMENT, ruleId: 'mp.weixin.qq.com', reason: '微信公众号文章' };
  }
  return undefined;
}

export function matchRecommendationFilters(content: BlockableContentSummary,
  preferences: RecommendationFilterPreferences): BlockingMatch | undefined {
  const promotional = promotionalFilterReason(content, preferences);
  if (preferences.reverseBlock) {
    return promotionalFilterReason(content, defaultRecommendationFilterPreferences()) === undefined
      ? { kind: BlockingRuleKind.REVERSE, ruleId: 'reverse', reason: '反向屏蔽：非广告或付费内容' }
      : undefined;
  }
  if (!preferences.filterFollowedUserContent && content.authorIsFollowing === true) {
    return undefined;
  }
  if (promotional !== undefined) {
    return promotional;
  }
  const qualityReason = qualityFilterReason(content, preferences);
  if (qualityReason !== undefined && preferences.qualityFilterMode === QualityFilterMode.HIDE) {
    return { kind: BlockingRuleKind.QUALITY, ruleId: content.contentKind ?? 'content', reason: qualityReason };
  }
  if (preferences.enableContentFilter && content.opened !== true && (content.viewCount ?? 0) >= 2) {
    return { kind: BlockingRuleKind.SMART, ruleId: content.contentId ?? 'content', reason: '已展示超过2次且未点击' };
  }
  return undefined;
}

export class BlockingRuleMatcher implements ContentBlockingMatcher {
  private readonly rules: BlockingRuleGateway;
  private readonly preferences: BlockingPreferencesGateway;
  private readonly strategy: ContentBlockingStrategy;
  private readonly recommendationPreferences?: RecommendationFilterPreferencesGateway;
  private readonly runtime?: ContentFilterRuntimeGateway;

  constructor(rules: BlockingRuleGateway, preferences: BlockingPreferencesGateway, strategy: ContentBlockingStrategy,
    recommendationPreferences?: RecommendationFilterPreferencesGateway, runtime?: ContentFilterRuntimeGateway) {
    this.rules = rules;
    this.preferences = preferences;
    this.strategy = strategy;
    this.recommendationPreferences = recommendationPreferences;
    this.runtime = runtime;
  }

  async createSession(): Promise<ContentBlockingSession> {
    try {
      const snapshot = await this.rules.loadSnapshot();
      const preferences = await this.preferences.loadBlockingPreferences();
      if (this.strategy === ContentBlockingStrategy.RULES_ONLY) {
        return new BlockingRuleMatchSession(this.strategy, snapshot, preferences);
      }
      if (this.recommendationPreferences === undefined || this.runtime === undefined) {
        throw new Error('Home content blocking dependencies unavailable');
      }
      const recommendation = await this.recommendationPreferences.loadRecommendationFilterPreferences();
      const runtimeSnapshot = await this.runtime.loadSnapshot();
      return new BlockingRuleMatchSession(this.strategy, snapshot, preferences, recommendation, runtimeSnapshot,
        this.runtime);
    } catch (_error) {
      throw new Error('Content blocking rules unavailable');
    }
  }
}

class BlockingRuleMatchSession implements ContentBlockingSession {
  private readonly strategy: ContentBlockingStrategy;
  private readonly snapshot: BlockingRuleSnapshot;
  private readonly preferences: BlockingPreferences;
  private readonly recommendation?: RecommendationFilterPreferences;
  private readonly runtimeSnapshot?: ContentFilterRuntimeSnapshot;
  private readonly runtime?: ContentFilterRuntimeGateway;
  private readonly outcomes: Array<ContentFilterOutcome> = [];
  private flushed: boolean = false;

  constructor(strategy: ContentBlockingStrategy, snapshot: BlockingRuleSnapshot, preferences: BlockingPreferences,
    recommendation?: RecommendationFilterPreferences, runtimeSnapshot?: ContentFilterRuntimeSnapshot,
    runtime?: ContentFilterRuntimeGateway) {
    this.strategy = strategy;
    this.snapshot = copyBlockingRuleSnapshot(snapshot);
    this.preferences = normalizeBlockingPreferences(preferences);
    this.recommendation = recommendation;
    this.runtimeSnapshot = runtimeSnapshot;
    this.runtime = runtime;
  }

  match(content: BlockableContentSummary): BlockingMatch | undefined {
    if (this.strategy === ContentBlockingStrategy.RULES_ONLY) {
      return matchBlockingRules(content, this.snapshot, this.preferences);
    }
    const enriched = this.withRuntimeState(content);
    const recommendation = this.recommendation;
    if (recommendation === undefined) return matchBlockingRules(enriched, this.snapshot, this.preferences);
    const recommendationMatch = matchRecommendationFilters(enriched, recommendation);
    let result: BlockingMatch | undefined;
    if (recommendationMatch !== undefined || recommendation.reverseBlock ||
      (!recommendation.filterFollowedUserContent && enriched.authorIsFollowing === true)) {
      result = recommendationMatch;
    } else {
      result = matchBlockingRules(enriched, this.snapshot, this.preferences);
    }
    this.outcomes.push(result === undefined ? { content: enriched } : { content: enriched, match: result });
    return result;
  }

  qualityReason(content: BlockableContentSummary): string | undefined {
    return this.recommendation === undefined ? undefined : qualityFilterReason(content, this.recommendation);
  }

  flush(): Promise<void> {
    if (this.runtime === undefined || this.flushed) return Promise.resolve();
    this.flushed = true;
    return this.runtime.recordOutcomes(this.outcomes.slice());
  }

  private withRuntimeState(content: BlockableContentSummary): BlockableContentSummary {
    const key = contentIdentityKey(content);
    if (key.length === 0 || this.runtimeSnapshot === undefined) return content;
    const copy: BlockableContentSummary = {
      contentId: content.contentId,
      contentKind: content.contentKind,
      title: content.title,
      excerpt: content.excerpt,
      content: content.content,
      url: content.url,
      authorId: content.authorId,
      authorName: content.authorName,
      questionAuthorId: content.questionAuthorId,
      questionAuthorName: content.questionAuthorName,
      authorFollowerCount: content.authorFollowerCount,
      authorIsFollowing: content.authorIsFollowing,
      topicIds: content.topicIds.slice(),
      voteupCount: content.voteupCount,
      answerCount: content.answerCount,
      followerCount: content.followerCount,
      isPaid: content.isPaid,
      viewCount: this.runtimeSnapshot.viewCounts[key] ?? 0,
      opened: this.runtimeSnapshot.openedKeys.includes(key)
    };
    return copy;
  }
}

export function contentIdentityKey(content: BlockableContentSummary): string {
  return content.contentKind === undefined || content.contentId === undefined ? '' :
    `${content.contentKind}:${content.contentId}`;
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
