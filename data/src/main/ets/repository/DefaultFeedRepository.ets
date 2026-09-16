import { feedItemIdentity, FeedItem, FeedPage, PageCursor } from '../domain/DomainModels';
import { BlockableContentSummary, ContentBlockingMatcher, ContentBlockingSession } from '../data/BlockingRuleStore';
import { decodeFeedPage } from '../domain/ZhihuDomainDecoder';
import { decodeMobileHomeFeedPage, isMobileHomeFeedCursorUrl } from '../domain/MobileHomeFeedDecoder';
import { HttpFailure, HttpFailureKind } from '../network/HttpFailure';
import { ZhihuHttpClient, ZhihuHttpResponse } from '../network/ZhihuHttpClient';
import { ZhihuMobileHttpClient } from '../network/ZhihuMobileClient';
import { SessionCookieProvider } from '../network/ZhihuHttpClient';
import {
  defaultRecommendationFilterPreferences,
  HomeFeedStartupCacheGateway,
  RecommendationFilterPreferences,
  RecommendationFilterPreferencesGateway,
  RecommendationMode
} from '../preferences/RecommendationFilterPreferences';
import { FeedRepository } from './FeedRepository';

export const HOME_FEED_INCLUDE =
  'data[*].content,excerpt,headline,target.voteup_count,target.vote_count,target.comment_count,' +
    'target.answer_count,target.follower_count,target.author.badge_v2,target.author.is_following,' +
    'target.author.follower_count,target.bound_topic_ids,target.question.bound_topic_ids';
const HOME_FEED_INCLUDE_QUERY = `include=${encodeURIComponent(HOME_FEED_INCLUDE).replace(/\*/g, '%2A')}`;
export const HOME_FEED_URL =
  `https://www.zhihu.com/api/v3/feed/topstory/recommend?desktop=true&page_number=1&limit=10&action=down&` +
    HOME_FEED_INCLUDE_QUERY;
export const MOBILE_HOME_FEED_URL = 'https://api.zhihu.com/topstory/recommend';

export enum FeedRepositoryFailureKind {
  INVALID_CURSOR = 'invalid_cursor',
  REPEATED_CURSOR = 'repeated_cursor',
  CANCELLED = 'cancelled'
}

export class FeedRepositoryFailure extends Error {
  readonly kind: FeedRepositoryFailureKind;

  constructor(kind: FeedRepositoryFailureKind) {
    let message = '首页 Feed 请求已取消';
    if (kind === FeedRepositoryFailureKind.INVALID_CURSOR) {
      message = '首页 Feed 返回了不受信任的分页地址';
    } else if (kind === FeedRepositoryFailureKind.REPEATED_CURSOR) {
      message = '首页 Feed 分页游标已被请求';
    }
    super(message);
    this.name = 'FeedRepositoryFailure';
    this.kind = kind;
  }
}

export function isHomeFeedCursorUrl(url: string): boolean {
  if (/[\u0000-\u0020\u007F-\uFFFF]/.test(url)) {
    return false;
  }
  return /^https:\/\/www\.zhihu\.com\/api\/v3\/feed\/topstory\/recommend(?:\?[^#]*)?$/.test(url);
}

export function buildHomeFeedRequestUrl(cursor?: string): string {
  if (cursor === undefined) {
    return HOME_FEED_URL;
  }
  if (!isHomeFeedCursorUrl(cursor)) {
    throw new FeedRepositoryFailure(FeedRepositoryFailureKind.INVALID_CURSOR);
  }
  const queryStart = cursor.indexOf('?');
  const baseUrl = queryStart < 0 ? cursor : cursor.substring(0, queryStart);
  const sourceQuery = queryStart < 0 ? '' : cursor.substring(queryStart + 1);
  const queryParts = sourceQuery.length === 0 ? [] : sourceQuery.split('&');
  const preservedParts: Array<string> = [];
  queryParts.forEach((part: string): void => {
    if (part.length === 0) {
      return;
    }
    const separator = part.indexOf('=');
    const encodedName = separator < 0 ? part : part.substring(0, separator);
    const encodedValue = separator < 0 ? '' : part.substring(separator + 1);
    let name: string;
    let value: string;
    try {
      name = decodeURIComponent(encodedName.replace(/\+/g, '%20'));
      value = decodeURIComponent(encodedValue.replace(/\+/g, '%20'));
    } catch (_error) {
      throw new FeedRepositoryFailure(FeedRepositoryFailureKind.INVALID_CURSOR);
    }
    if (name.length === 0) {
      throw new FeedRepositoryFailure(FeedRepositoryFailureKind.INVALID_CURSOR);
    }
    if (name !== 'include') {
      preservedParts.push(`${encodeURIComponent(name)}=${encodeURIComponent(value)}`);
    }
  });
  preservedParts.push(HOME_FEED_INCLUDE_QUERY);
  return `${baseUrl}?${preservedParts.join('&')}`;
}

export function canonicalHomeFeedCursorKey(cursor?: string): string {
  const requestUrl = buildHomeFeedRequestUrl(cursor);
  const queryStart = requestUrl.indexOf('?');
  const baseUrl = requestUrl.substring(0, queryStart);
  const parts = requestUrl.substring(queryStart + 1).split('&');
  parts.sort();
  return `${baseUrl}?${parts.join('&')}`;
}

function terminalCursor(cursor: PageCursor): PageCursor {
  return {
    isEnd: true,
    isStart: cursor.isStart,
    previous: cursor.previous,
    page: cursor.page,
    total: cursor.total
  };
}

export class DefaultFeedRepository implements FeedRepository {
  private readonly httpClient: ZhihuHttpClient;
  private readonly blockingMatcher?: ContentBlockingMatcher;
  private readonly recommendationPreferences?: RecommendationFilterPreferencesGateway;
  private readonly startupCache?: HomeFeedStartupCacheGateway;
  private readonly mobileHttpClient?: ZhihuMobileHttpClient;
  private readonly sessionProvider?: SessionCookieProvider;
  private requestedCursors: Set<string> = new Set<string>();
  private deliveredItemIdentities: Set<string> = new Set<string>();
  private generation: number = 0;
  private startupLoadPending: boolean = true;
  private mixedWebCursor?: string;
  private mixedMobileCursor?: string;

  constructor(httpClient: ZhihuHttpClient = new ZhihuHttpClient(), blockingMatcher?: ContentBlockingMatcher,
    recommendationPreferences?: RecommendationFilterPreferencesGateway, startupCache?: HomeFeedStartupCacheGateway,
    mobileHttpClient?: ZhihuMobileHttpClient, sessionProvider?: SessionCookieProvider) {
    this.httpClient = httpClient;
    this.blockingMatcher = blockingMatcher;
    this.recommendationPreferences = recommendationPreferences;
    this.startupCache = startupCache;
    this.mobileHttpClient = mobileHttpClient;
    this.sessionProvider = sessionProvider;
  }

  cancel(): void {
    this.generation += 1;
    this.httpClient.cancel();
    this.mobileHttpClient?.cancel();
  }

  async loadHomePage(cursor?: string): Promise<FeedPage> {
    const requestGeneration = this.generation;
    const preferences = this.recommendationPreferences === undefined
      ? legacyRecommendationPreferences()
      : await this.recommendationPreferences.loadRecommendationFilterPreferences();
    if (requestGeneration !== this.generation) {
      throw new FeedRepositoryFailure(FeedRepositoryFailureKind.CANCELLED);
    }
    if (cursor !== undefined && !this.isCursorForMode(cursor, preferences.recommendationMode)) {
      throw new FeedRepositoryFailure(FeedRepositoryFailureKind.INVALID_CURSOR);
    }
    this.requireConfiguredLogin(preferences);
    const cursorKey = this.cursorKey(cursor, preferences.recommendationMode);
    if (cursor !== undefined && this.requestedCursors.has(cursorKey)) {
      throw new FeedRepositoryFailure(FeedRepositoryFailureKind.REPEATED_CURSOR);
    }
    let decodedPage: FeedPage | undefined;
    if (cursor === undefined && this.startupLoadPending && !preferences.autoRefreshHomeOnStartup) {
      decodedPage = await this.loadCachedPage(preferences.recommendationMode);
    }
    this.startupLoadPending = false;
    if (decodedPage === undefined) {
      decodedPage = await this.loadSourcePage(cursor, preferences);
    }
    if (requestGeneration !== this.generation) {
      throw new FeedRepositoryFailure(FeedRepositoryFailureKind.CANCELLED);
    }
    let visibleItems = decodedPage.items;
    if (this.blockingMatcher !== undefined) {
      const blockingSession: ContentBlockingSession = await this.blockingMatcher.createSession();
      visibleItems = decodedPage.items.filter((item: FeedItem): boolean => {
        const summary = blockableFeedSummary(item);
        const reason = blockingSession.qualityReason?.(summary);
        if (reason !== undefined) {
          item.target.qualityFilterReason = reason;
        }
        return blockingSession.match(summary) === undefined;
      });
      await blockingSession.flush?.();
    }
    if (requestGeneration !== this.generation) {
      throw new FeedRepositoryFailure(FeedRepositoryFailureKind.CANCELLED);
    }
    const next = decodedPage.cursor.next;
    const nextKey = next === undefined ? undefined : this.cursorKey(next, preferences.recommendationMode);
    const nextRequestedCursors = cursor === undefined ? new Set<string>() : cloneStringSet(this.requestedCursors);
    const nextDeliveredIdentities = cursor === undefined
      ? new Set<string>()
      : cloneStringSet(this.deliveredItemIdentities);
    nextRequestedCursors.add(cursorKey);
    const items: Array<FeedItem> = visibleItems.filter((item: FeedItem): boolean => {
      const identity = feedItemIdentity(item);
      if (nextDeliveredIdentities.has(identity)) {
        return false;
      }
      nextDeliveredIdentities.add(identity);
      return true;
    });
    const cursorLoops = (next === undefined && !decodedPage.cursor.isEnd) || nextKey === cursorKey ||
      (nextKey !== undefined && nextRequestedCursors.has(nextKey));
    this.requestedCursors = nextRequestedCursors;
    this.deliveredItemIdentities = nextDeliveredIdentities;
    return {
      items: items,
      cursor: cursorLoops ? terminalCursor(decodedPage.cursor) : decodedPage.cursor
    };
  }

  private requireConfiguredLogin(preferences: RecommendationFilterPreferences): void {
    if (this.recommendationPreferences === undefined || !preferences.loginForRecommendation) return;
    const cookies = this.sessionProvider?.getCookies() ?? [];
    if (!cookies.some((cookie): boolean => cookie.name === 'd_c0' && cookie.value.length > 0)) {
      throw new HttpFailure(HttpFailureKind.AUTHENTICATION);
    }
  }

  private isCursorForMode(cursor: string, mode: RecommendationMode): boolean {
    if (mode === RecommendationMode.WEB) return isHomeFeedCursorUrl(cursor);
    if (mode === RecommendationMode.ANDROID) return isMobileHomeFeedCursorUrl(cursor);
    if (mode === RecommendationMode.MIXED) {
      return isHomeFeedCursorUrl(cursor) || isMobileHomeFeedCursorUrl(cursor);
    }
    return false;
  }

  private cursorKey(cursor: string | undefined, mode: RecommendationMode): string {
    if (cursor === undefined) return `initial:${mode}`;
    if (mode === RecommendationMode.WEB || isHomeFeedCursorUrl(cursor)) {
      return canonicalHomeFeedCursorKey(cursor);
    }
    if (!isMobileHomeFeedCursorUrl(cursor)) {
      throw new FeedRepositoryFailure(FeedRepositoryFailureKind.INVALID_CURSOR);
    }
    return cursor;
  }

  private async loadSourcePage(cursor: string | undefined,
    preferences: RecommendationFilterPreferences): Promise<FeedPage> {
    if (cursor === undefined) {
      this.mixedWebCursor = undefined;
      this.mixedMobileCursor = undefined;
    }
    if (preferences.recommendationMode === RecommendationMode.LOCAL) {
      const cached = await this.loadCachedPage(RecommendationMode.LOCAL);
      if (cached !== undefined && cached.items.length > 0) return this.rankLocalPage(cached);
      const seed = await this.fetchWebPage(undefined, preferences.loginForRecommendation);
      return this.rankLocalPage(seed);
    }
    if (preferences.recommendationMode === RecommendationMode.ANDROID) {
      return this.fetchMobilePage(cursor, preferences.loginForRecommendation);
    }
    if (preferences.recommendationMode === RecommendationMode.MIXED) {
      return this.fetchMixedPage(cursor, preferences.loginForRecommendation);
    }
    return this.fetchWebPage(cursor, preferences.loginForRecommendation);
  }

  private async fetchWebPage(cursor: string | undefined, useSession: boolean): Promise<FeedPage> {
    const response: ZhihuHttpResponse = await this.httpClient.execute({
      url: buildHomeFeedRequestUrl(cursor),
      accept: 'application/json',
      useSession: useSession,
      signWithZse: useSession
    });
    const page = decodeFeedPage(response.body);
    await this.saveCachedResponse(RecommendationMode.WEB, response.body);
    return page;
  }

  private async fetchMobilePage(cursor: string | undefined, useSession: boolean): Promise<FeedPage> {
    const url = cursor ?? MOBILE_HOME_FEED_URL;
    let response: ZhihuHttpResponse;
    if (this.mobileHttpClient !== undefined) {
      response = await this.mobileHttpClient.execute({ url: url, accept: 'application/json', useSession: useSession });
    } else {
      response = await this.httpClient.execute({ url: url, accept: 'application/json', useSession: useSession });
    }
    const page = decodeMobileHomeFeedPage(response.body);
    await this.saveCachedResponse(RecommendationMode.ANDROID, response.body);
    return page;
  }

  private async fetchMixedPage(cursor: string | undefined, useSession: boolean): Promise<FeedPage> {
    const webCursor = cursor === undefined ? undefined : this.mixedWebCursor;
    const mobileCursor = cursor === undefined ? undefined : this.mixedMobileCursor;
    const pages = await Promise.all([
      webCursor === undefined && cursor !== undefined
        ? Promise.resolve(undefined)
        : this.fetchWebPage(webCursor, useSession),
      mobileCursor === undefined && cursor !== undefined
        ? Promise.resolve(undefined)
        : this.fetchMobilePage(mobileCursor, useSession)
    ]);
    const web = pages[0];
    const mobile = pages[1];
    this.mixedWebCursor = web?.cursor.next;
    this.mixedMobileCursor = mobile?.cursor.next;
    const items = mergeFeedSourceItems(web?.items ?? [], mobile?.items ?? []);
    const next = this.mixedWebCursor ?? this.mixedMobileCursor;
    return {
      items: items,
      cursor: {
        isEnd: next === undefined,
        isStart: cursor === undefined,
        next: next,
        page: Math.max(web?.cursor.page ?? 0, mobile?.cursor.page ?? 0),
        total: (web?.cursor.total ?? 0) + (mobile?.cursor.total ?? 0)
      }
    };
  }

  private async loadCachedPage(mode: RecommendationMode): Promise<FeedPage | undefined> {
    if (this.startupCache === undefined) return undefined;
    try {
      if (mode === RecommendationMode.WEB) {
        return terminalPage(decodeFeedPage(await this.requiredCachedResponse(RecommendationMode.WEB)));
      }
      if (mode === RecommendationMode.ANDROID) {
        return terminalPage(decodeMobileHomeFeedPage(await this.requiredCachedResponse(RecommendationMode.ANDROID)));
      }
      const webRaw = await this.startupCache.loadHomeFeedStartupResponse(RecommendationMode.WEB);
      const mobileRaw = await this.startupCache.loadHomeFeedStartupResponse(RecommendationMode.ANDROID);
      const web = webRaw === undefined ? [] : decodeFeedPage(webRaw).items;
      const mobile = mobileRaw === undefined ? [] : decodeMobileHomeFeedPage(mobileRaw).items;
      if (web.length === 0 && mobile.length === 0) return undefined;
      const page: FeedPage = {
        items: mergeFeedSourceItems(web, mobile),
        cursor: { isEnd: true, isStart: true, page: 0, total: web.length + mobile.length }
      };
      return mode === RecommendationMode.LOCAL ? this.rankLocalPage(page) : page;
    } catch (_error) {
      return undefined;
    }
  }

  private async requiredCachedResponse(mode: RecommendationMode): Promise<string> {
    const value = await this.startupCache?.loadHomeFeedStartupResponse(mode);
    if (value === undefined) throw new Error('首页推荐启动快照不存在');
    return value;
  }

  private async saveCachedResponse(mode: RecommendationMode, response: string): Promise<void> {
    try {
      await this.startupCache?.saveHomeFeedStartupResponse(mode, response);
    } catch (_error) {
    }
  }

  private rankLocalPage(page: FeedPage): FeedPage {
    const items = page.items.slice();
    items.sort((left: FeedItem, right: FeedItem): number => localRecommendationScore(right) -
      localRecommendationScore(left));
    return terminalPage({ items: items, cursor: page.cursor });
  }
}

function legacyRecommendationPreferences(): RecommendationFilterPreferences {
  const legacy = defaultRecommendationFilterPreferences();
  legacy.recommendationMode = RecommendationMode.WEB;
  return legacy;
}

function terminalPage(page: FeedPage): FeedPage {
  return { items: page.items, cursor: terminalCursor(page.cursor) };
}

function localRecommendationScore(item: FeedItem): number {
  return (item.target.voteupCount ?? 0) * 4 + (item.target.followerCount ?? 0) * 2 +
    (item.target.answerCount ?? 0) + (item.target.commentCount ?? 0);
}

function mergeFeedSourceItems(first: Array<FeedItem>, second: Array<FeedItem>): Array<FeedItem> {
  const result: Array<FeedItem> = [];
  const identities: Set<string> = new Set();
  first.concat(second).forEach((item: FeedItem): void => {
    const identity = feedItemIdentity(item);
    if (!identities.has(identity)) {
      identities.add(identity);
      result.push(item);
    }
  });
  return result;
}

function blockableFeedSummary(item: FeedItem): BlockableContentSummary {
  const summary: BlockableContentSummary = {
    contentId: item.target.id,
    contentKind: item.target.kind,
    title: item.target.title,
    excerpt: item.target.excerpt,
    content: item.target.content,
    url: item.target.url,
    topicIds: item.target.topicIds,
    voteupCount: item.target.voteupCount,
    answerCount: item.target.answerCount,
    followerCount: item.target.followerCount,
    isPaid: item.target.isPaid
  };
  if (item.target.author !== undefined) {
    summary.authorId = item.target.author.id;
    summary.authorName = item.target.author.name;
    summary.authorFollowerCount = item.target.authorFollowerCount;
    summary.authorIsFollowing = item.target.authorIsFollowing;
  }
  return summary;
}

function cloneStringSet(source: Set<string>): Set<string> {
  const copy = new Set<string>();
  source.forEach((value: string): void => {
    copy.add(value);
  });
  return copy;
}
