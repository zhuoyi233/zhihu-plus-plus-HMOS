import { decodeNotificationPage, decodeUnreadCounts } from '../domain/NotificationDecoder';
import { PageCursor } from '../domain/DomainModels';
import {
  NotificationCategory,
  NotificationItem,
  NotificationPage,
  NotificationUnreadCounts,
  notificationItemIdentity,
  notificationCategoryInfo
} from '../domain/NotificationModels';
import { ZhihuHttpClient, ZhihuHttpMethod, ZhihuHttpResponse } from '../network/ZhihuHttpClient';
import { NotificationRepository } from './NotificationRepository';

const NOTIFICATION_LIMIT = 20;
const NOTIFICATION_CURSOR_MAX_LENGTH = 4096;
const NOTIFICATION_ENTRY_BASE_URL = 'https://www.zhihu.com/api/v4/notifications/v2';
const NOTIFICATION_UNREAD_INCLUDE = 'default_notifications_count,follow_notifications_count,vote_thank_notifications_count';

export enum NotificationRepositoryFailureKind {
  INVALID_CURSOR = 'invalid_cursor',
  REPEATED_CURSOR = 'repeated_cursor',
  CANCELLED = 'cancelled'
}

export class NotificationRepositoryFailure extends Error {
  readonly kind: NotificationRepositoryFailureKind;

  constructor(kind: NotificationRepositoryFailureKind) {
    let message = '通知请求已取消';
    if (kind === NotificationRepositoryFailureKind.INVALID_CURSOR) {
      message = '通知返回了不受信任的分页地址';
    } else if (kind === NotificationRepositoryFailureKind.REPEATED_CURSOR) {
      message = '通知分页游标已被请求';
    }
    super(message);
    this.name = 'NotificationRepositoryFailure';
    this.kind = kind;
  }
}

export function buildNotificationListUrl(category: NotificationCategory, cursor?: string): string {
  if (cursor === undefined) {
    return `${NOTIFICATION_ENTRY_BASE_URL}/${notificationCategoryInfo(category).entryName}?limit=${NOTIFICATION_LIMIT}`;
  }
  if (!isNotificationCursorUrl(category, cursor)) {
    throw new NotificationRepositoryFailure(NotificationRepositoryFailureKind.INVALID_CURSOR);
  }
  // 上游 zhihu 返回的游标可能是 http://，统一规范化为 https:// 再请求（对齐上游 .replace("http://", "https://")）。
  return cursor.startsWith('http://') ? `https://${cursor.substring('http://'.length)}` : cursor;
}

export function isNotificationCursorUrl(category: NotificationCategory, cursor: string): boolean {
  if (cursor.length === 0 || cursor.length > NOTIFICATION_CURSOR_MAX_LENGTH ||
    /[\u0000-\u0020\u007F-\uFFFF]/.test(cursor)) {
    return false;
  }
  const normalized = cursor.startsWith('http://') ? `https://${cursor.substring('http://'.length)}` : cursor;
  const prefix = `${NOTIFICATION_ENTRY_BASE_URL}/${notificationCategoryInfo(category).entryName}?`;
  return normalized.startsWith(prefix) && !normalized.includes('#');
}

export function buildNotificationUnreadUrl(): string {
  return `https://www.zhihu.com/api/v4/me?include=${encodeURIComponent(NOTIFICATION_UNREAD_INCLUDE)}`;
}

export function buildNotificationReadAllUrls(): Array<string> {
  return [
    `${NOTIFICATION_ENTRY_BASE_URL}/default/actions/readall`,
    `${NOTIFICATION_ENTRY_BASE_URL}/follow/actions/readall`,
    `${NOTIFICATION_ENTRY_BASE_URL}/vote_thank/actions/readall`
  ];
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

function cloneStringSet(source: Set<string>): Set<string> {
  const copy = new Set<string>();
  source.forEach((value: string): void => {
    copy.add(value);
  });
  return copy;
}

/**
 * 通知列表仓库（web v2）。列表/未读数/全部已读均 `useSession=true, signWithZse=true`，
 * 与上游 `NotificationViewModel` 的 web v2 语义一致；未读数与 readall 是独立请求，
 * 由调用方按登录门禁决定是否发起。
 */
export class DefaultNotificationRepository implements NotificationRepository {
  private readonly httpClient: ZhihuHttpClient;
  private generation: number = 0;
  private requestedCursors: Set<string> = new Set<string>();
  private deliveredIdentities: Set<string> = new Set<string>();

  constructor(httpClient: ZhihuHttpClient = new ZhihuHttpClient()) {
    this.httpClient = httpClient;
  }

  cancel(): void {
    this.generation += 1;
    this.httpClient.cancel();
  }

  async getNotificationsPage(category: NotificationCategory, cursor?: string): Promise<NotificationPage> {
    const requestGeneration = this.generation;
    const requestUrl = buildNotificationListUrl(category, cursor);
    if (cursor !== undefined && this.requestedCursors.has(requestUrl)) {
      throw new NotificationRepositoryFailure(NotificationRepositoryFailureKind.REPEATED_CURSOR);
    }
    const response = await this.execute(requestUrl, ZhihuHttpMethod.GET);
    if (requestGeneration !== this.generation) {
      throw new NotificationRepositoryFailure(NotificationRepositoryFailureKind.CANCELLED);
    }
    const page = decodeNotificationPage(response.body, category);
    return this.postDecode(page, cursor, requestUrl);
  }

  async getUnreadCounts(): Promise<NotificationUnreadCounts> {
    const requestGeneration = this.generation;
    const response = await this.execute(buildNotificationUnreadUrl(), ZhihuHttpMethod.GET);
    if (requestGeneration !== this.generation) {
      throw new NotificationRepositoryFailure(NotificationRepositoryFailureKind.CANCELLED);
    }
    return decodeUnreadCounts(response.body);
  }

  async markAllAsRead(): Promise<void> {
    const requestGeneration = this.generation;
    const urls = buildNotificationReadAllUrls();
    for (let index = 0; index < urls.length; index += 1) {
      await this.execute(urls[index], ZhihuHttpMethod.POST);
      if (requestGeneration !== this.generation) {
        throw new NotificationRepositoryFailure(NotificationRepositoryFailureKind.CANCELLED);
      }
    }
  }

  private async execute(url: string, method: ZhihuHttpMethod): Promise<ZhihuHttpResponse> {
    return this.httpClient.execute({
      url: url,
      method: method,
      accept: 'application/json',
      useSession: true,
      signWithZse: true
    });
  }

  private postDecode(page: NotificationPage, cursor: string | undefined,
    requestUrl: string): NotificationPage {
    const requested = cursor === undefined ? new Set<string>() : cloneStringSet(this.requestedCursors);
    const delivered = cursor === undefined
      ? new Set<string>()
      : cloneStringSet(this.deliveredIdentities);
    requested.add(requestUrl);
    const items = page.items.filter((item: NotificationItem): boolean => {
      const identity = notificationItemIdentity(item);
      if (delivered.has(identity)) {
        return false;
      }
      delivered.add(identity);
      return true;
    });
    const next = page.cursor.next;
    const cursorLoops = (next === undefined && !page.cursor.isEnd) || next === requestUrl ||
      (next !== undefined && requested.has(next));
    this.requestedCursors = requested;
    this.deliveredIdentities = delivered;
    return {
      items: items,
      cursor: cursorLoops ? terminalCursor(page.cursor) : page.cursor
    };
  }
}
