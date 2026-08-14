import { OnlineHistoryEntry, OnlineHistoryPage } from '../domain/OnlineHistoryModels';
import { decodeOnlineHistoryPage } from '../domain/ZhihuOnlineHistoryDecoder';
import { ZhihuHttpClient, ZhihuHttpResponse } from '../network/ZhihuHttpClient';
import { OnlineHistoryRepository } from './OnlineHistoryRepository';

export const ONLINE_HISTORY_BASE_URL = 'https://www.zhihu.com/api/v4/unify-consumption/read_history';
export const ONLINE_HISTORY_LIMIT: number = 10;
export const ONLINE_HISTORY_MAX_OFFSET: number = 100000;
const ONLINE_HISTORY_CURSOR_MAX_LENGTH: number = 4096;

export enum OnlineHistoryRepositoryFailureKind {
  INVALID_CURSOR = 'invalid_cursor',
  REPEATED_CURSOR = 'repeated_cursor',
  CANCELLED = 'cancelled'
}

export class OnlineHistoryRepositoryFailure extends Error {
  readonly kind: OnlineHistoryRepositoryFailureKind;

  constructor(kind: OnlineHistoryRepositoryFailureKind) {
    let message = '在线历史请求已取消';
    if (kind === OnlineHistoryRepositoryFailureKind.INVALID_CURSOR) {
      message = '在线历史分页地址不受信任';
    } else if (kind === OnlineHistoryRepositoryFailureKind.REPEATED_CURSOR) {
      message = '在线历史分页游标已被请求';
    }
    super(message);
    this.name = 'OnlineHistoryRepositoryFailure';
    this.kind = kind;
  }
}

export function buildOnlineHistoryUrl(offset: number): string {
  if (!Number.isSafeInteger(offset) || offset < 0 || offset > ONLINE_HISTORY_MAX_OFFSET) {
    throw new OnlineHistoryRepositoryFailure(OnlineHistoryRepositoryFailureKind.INVALID_CURSOR);
  }
  return `${ONLINE_HISTORY_BASE_URL}?offset=${offset}&limit=${ONLINE_HISTORY_LIMIT}`;
}

export function isOnlineHistoryCursorUrl(url: string): boolean {
  if (url.length === 0 || url.length > ONLINE_HISTORY_CURSOR_MAX_LENGTH ||
    /[\u0000-\u0020\u007F-\uFFFF]/.test(url)) {
    return false;
  }
  if (!url.startsWith(`${ONLINE_HISTORY_BASE_URL}?`)) {
    return false;
  }
  const query = url.substring(url.indexOf('?') + 1);
  if (query.length === 0) {
    return false;
  }
  const parts = query.split('&');
  if (parts.length !== 2) {
    return false;
  }
  const offset = queryIntParameter(parts, 'offset');
  const limit = queryIntParameter(parts, 'limit');
  return offset !== undefined && offset <= ONLINE_HISTORY_MAX_OFFSET && limit === ONLINE_HISTORY_LIMIT;
}

export function canonicalOnlineHistoryCursorKey(url: string): string {
  const query = url.substring(url.indexOf('?') + 1);
  const parts = query.split('&').slice().sort();
  return `${ONLINE_HISTORY_BASE_URL}?${parts.join('&')}`;
}

export function onlineHistoryOffsetOf(url: string): number {
  if (!isOnlineHistoryCursorUrl(url)) {
    throw new OnlineHistoryRepositoryFailure(OnlineHistoryRepositoryFailureKind.INVALID_CURSOR);
  }
  const query = url.substring(url.indexOf('?') + 1);
  return queryIntParameter(query.split('&'), 'offset') ?? 0;
}

function queryIntParameter(parts: Array<string>, wantedName: string): number | undefined {
  for (const part of parts) {
    if (part.length === 0) {
      return undefined;
    }
    const separator = part.indexOf('=');
    if (separator <= 0 || separator === part.length - 1) {
      return undefined;
    }
    const encodedName = part.substring(0, separator);
    const encodedValue = part.substring(separator + 1);
    let name: string;
    let value: string;
    try {
      name = decodeURIComponent(encodedName.replace(/\+/g, '%20'));
      value = decodeURIComponent(encodedValue.replace(/\+/g, '%20'));
    } catch (_error) {
      return undefined;
    }
    if (name === wantedName) {
      if (!/^(?:0|[1-9][0-9]*)$/.test(value)) {
        return undefined;
      }
      return Number(value);
    }
  }
  return undefined;
}

function terminalCursor(page: OnlineHistoryPage): OnlineHistoryPage {
  return {
    items: page.items,
    cursor: {
      isEnd: true,
      isStart: page.cursor.isStart,
      page: page.cursor.page,
      total: page.cursor.total
    }
  };
}

export class DefaultOnlineHistoryRepository implements OnlineHistoryRepository {
  private readonly httpClient: ZhihuHttpClient;
  private requestedCursors: Set<string> = new Set<string>();
  private deliveredIdentities: Set<string> = new Set<string>();
  private generation: number = 0;

  constructor(httpClient: ZhihuHttpClient) {
    this.httpClient = httpClient;
  }

  cancel(): void {
    this.generation += 1;
    this.httpClient.cancel();
  }

  async loadPage(cursor?: string): Promise<OnlineHistoryPage> {
    if (cursor !== undefined && !isOnlineHistoryCursorUrl(cursor)) {
      throw new OnlineHistoryRepositoryFailure(OnlineHistoryRepositoryFailureKind.INVALID_CURSOR);
    }
    const requestGeneration = this.generation;
    const offset = cursor === undefined ? 0 : onlineHistoryOffsetOf(cursor);
    const requestUrl = cursor === undefined ? buildOnlineHistoryUrl(0) : cursor;
    const cursorKey = canonicalOnlineHistoryCursorKey(requestUrl);
    if (cursor !== undefined && this.requestedCursors.has(cursorKey)) {
      throw new OnlineHistoryRepositoryFailure(OnlineHistoryRepositoryFailureKind.REPEATED_CURSOR);
    }
    const response: ZhihuHttpResponse = await this.httpClient.execute({
      url: requestUrl,
      accept: 'application/json',
      useSession: true,
      signWithZse: true
    });
    if (requestGeneration !== this.generation) {
      throw new OnlineHistoryRepositoryFailure(OnlineHistoryRepositoryFailureKind.CANCELLED);
    }
    const decodedPage = decodeOnlineHistoryPage(response.body);
    const nextRequested = cursor === undefined ? new Set<string>() : cloneStringSet(this.requestedCursors);
    const nextDelivered = cursor === undefined ? new Set<string>() : cloneStringSet(this.deliveredIdentities);
    nextRequested.add(cursorKey);
    const items: Array<OnlineHistoryEntry> = [];
    decodedPage.items.forEach((item: OnlineHistoryEntry): void => {
      if (nextDelivered.has(item.contentKey)) {
        return;
      }
      nextDelivered.add(item.contentKey);
      items.push(item);
    });
    const next = (!decodedPage.cursor.isEnd && items.length > 0)
      ? buildOnlineHistoryUrl(offset + ONLINE_HISTORY_LIMIT)
      : undefined;
    const nextKey = next === undefined ? undefined : canonicalOnlineHistoryCursorKey(next);
    const cursorLoops = (next === undefined && !decodedPage.cursor.isEnd) || nextKey === cursorKey ||
      (nextKey !== undefined && nextRequested.has(nextKey));
    this.requestedCursors = nextRequested;
    this.deliveredIdentities = nextDelivered;
    const page: OnlineHistoryPage = {
      items: items,
      cursor: {
        isEnd: decodedPage.cursor.isEnd,
        isStart: decodedPage.cursor.isStart,
        next: next,
        page: decodedPage.cursor.page,
        total: decodedPage.cursor.total
      }
    };
    return cursorLoops ? terminalCursor(page) : page;
  }
}

function cloneStringSet(source: Set<string>): Set<string> {
  const copy = new Set<string>();
  source.forEach((value: string): void => {
    copy.add(value);
  });
  return copy;
}
