import { FeedTargetKind, PageCursor } from './DomainModels';

export interface SearchResultItem {
  readonly wrapperId: string;
  readonly kind: FeedTargetKind;
  readonly contentId: string;
  readonly title: string;
  readonly excerpt: string;
  readonly authorId?: string;
  readonly authorName?: string;
  readonly topicIds: Array<string>;
  readonly voteupCount: number;
  readonly commentCount: number;
}

/** 用户搜索结果：name 保留 `<em>` 原文，由 UI 层做高亮拆分。 */
export interface SearchPersonItem {
  readonly id: string;
  readonly name: string;
  readonly urlToken?: string;
  readonly avatarUrl?: string;
  readonly headline: string;
  readonly followerCount: number;
  readonly answerCount: number;
}

/** 话题搜索结果：name/excerpt 保留 `<em>` 原文，由 UI 层做高亮拆分。 */
export interface SearchTopicItem {
  readonly id: string;
  readonly name: string;
  readonly avatarUrl?: string;
  readonly excerpt: string;
  readonly visitCount: number;
  readonly discussCount: number;
  readonly isFollowing: boolean;
}

export enum SearchEntityKind {
  CONTENT = 'content',
  PERSON = 'person',
  TOPIC = 'topic'
}

/** 搜索结果统一实体：内容/用户/话题三态，kind 决定哪个字段有效。 */
export interface SearchEntity {
  readonly id: string;
  readonly kind: SearchEntityKind;
  readonly content?: SearchResultItem;
  readonly person?: SearchPersonItem;
  readonly topic?: SearchTopicItem;
}

export function searchEntityOfContent(item: SearchResultItem): SearchEntity {
  return { id: searchResultIdentity(item), kind: SearchEntityKind.CONTENT, content: item };
}

export function searchEntityOfPerson(item: SearchPersonItem): SearchEntity {
  return { id: `person:${item.id}`, kind: SearchEntityKind.PERSON, person: item };
}

export function searchEntityOfTopic(item: SearchTopicItem): SearchEntity {
  return { id: `topic:${item.id}`, kind: SearchEntityKind.TOPIC, topic: item };
}

export function searchEntityIdentity(entity: SearchEntity): string {
  return entity.id;
}

export interface SearchResultPage {
  readonly entities: Array<SearchEntity>;
  readonly cursor: PageCursor;
}

export function searchResultIdentity(item: SearchResultItem): string {
  return `${item.kind}:${item.contentId}`;
}

/** 热搜词条：query 为搜索词，hotShow 为热度展示文本（可空）。 */
export interface SearchHotItem {
  readonly query: string;
  readonly hotShow: string;
  readonly label: string;
}

/**
 * 搜索范围（对齐上游 SearchTab 与 vertical 筛选的组合）：
 * 回答/文章两个 tab 复用 t=general 接口，通过 vertical 参数让服务端过滤内容类型。
 */
export enum SearchTab {
  GENERAL = 'general',
  PEOPLE = 'people',
  ANSWER = 'answer',
  ARTICLE = 'article',
  TOPIC = 'topic'
}

export enum SearchSortOption {
  DEFAULT = 'default',
  LATEST = 'latest',
  MOST_VOTED = 'most_voted'
}

export enum SearchTimeRange {
  ALL = 'all',
  DAY = 'day',
  WEEK = 'week',
  MONTH = 'month',
  THREE_MONTHS = 'three_months',
  HALF_YEAR = 'half_year',
  YEAR = 'year'
}

/** 搜索请求筛选参数（对齐上游 SearchFilters 的 sort + timeRange；内容类型由 SearchTab 承载）。 */
export interface SearchFilters {
  readonly sort: SearchSortOption;
  readonly timeRange: SearchTimeRange;
}

export function defaultSearchFilters(): SearchFilters {
  return { sort: SearchSortOption.DEFAULT, timeRange: SearchTimeRange.ALL };
}

export function areDefaultSearchFilters(filters: SearchFilters): boolean {
  return filters.sort === SearchSortOption.DEFAULT && filters.timeRange === SearchTimeRange.ALL;
}
