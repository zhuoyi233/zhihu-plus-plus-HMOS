import { decodeMobileMessagePage, decodeMobileTimelinePage, decodePrivateMessagePage,
  decodePrivateMessagePeer, decodePrivateMessageReceipt } from '../domain/MobileNotificationDecoder';
import { MobileNotificationAuthor, MobileNotificationMessagePage, MobileNotificationTimelinePage,
  ZhihuPrivateMessage, ZhihuPrivateMessagePage } from '../domain/MobileNotificationModels';
import { PageCursor } from '../domain/DomainModels';
import { encryptZhihuMessageBody } from '../network/ZhihuMessageBodyEncryptor';
import { ZhihuMobileHttpClient, ZhihuMobileHttpRequest } from '../network/ZhihuMobileClient';
import { ZhihuHttpMethod, ZhihuHttpResponse } from '../network/ZhihuHttpClient';
import { MobileNotificationRepository } from './MobileNotificationRepository';

const MOBILE_NOTIFICATION_LIMIT = 20;
const MOBILE_NOTIFICATION_CURSOR_MAX_LENGTH = 4096;
const MOBILE_MESSAGE_URL = 'https://api.zhihu.com/notifications/v3/message/v3';
const MOBILE_TIMELINE_URL = 'https://api.zhihu.com/notifications/v3/timeline/entry';
const MOBILE_PRIVATE_MESSAGE_URL = 'https://api.zhihu.com/messages';
const MOBILE_PRIVATE_MESSAGE_USER_URL = 'https://api.zhihu.com/messages/user';
/** 上游发私信时声明的移动端加密协议版本。 */
const MOBILE_ZSE93_ENCRYPTED_FORM = '101_1_1.0';

export function isValidMobileNotificationEntryName(entryName: string): boolean {
  return /^[a-z_]{1,40}$/.test(entryName);
}

export function isValidPrivateMessagePeerId(peerId: string): boolean {
  return /^[A-Za-z0-9_-]{1,128}$/.test(peerId);
}

export function buildMobileMessageListUrl(cursor?: string): string {
  if (cursor === undefined) {
    return `${MOBILE_MESSAGE_URL}?limit=${MOBILE_NOTIFICATION_LIMIT}`;
  }
  // 上游返回的游标可能是 http://，统一规范化为 https:// 再请求（对齐上游 replace）。
  const normalized = normalizeCursorUrl(cursor);
  if (!isMobileMessageCursorUrl(normalized)) {
    throw new MobileNotificationRepositoryFailure(MobileNotificationRepositoryFailureKind.INVALID_CURSOR);
  }
  return normalized;
}

export function isMobileMessageCursorUrl(cursor: string): boolean {
  if (cursor.length === 0 || cursor.length > MOBILE_NOTIFICATION_CURSOR_MAX_LENGTH ||
    /[\u0000-\u0020\u007F-\uFFFF]/.test(cursor)) {
    return false;
  }
  const prefix = `${MOBILE_MESSAGE_URL}?`;
  return cursor.startsWith(prefix) && !cursor.includes('#');
}

export function buildMobileTimelineListUrl(entryName: string, cursor?: string): string {
  if (!isValidMobileNotificationEntryName(entryName)) {
    throw new MobileNotificationRepositoryFailure(MobileNotificationRepositoryFailureKind.INVALID_ENTRY);
  }
  if (cursor === undefined) {
    const inviteQuery = entryName === 'invite' ? 'invite_with_time_slice=1&' : '';
    return `${MOBILE_TIMELINE_URL}/${entryName}?${inviteQuery}limit=${MOBILE_NOTIFICATION_LIMIT}`;
  }
  const normalized = normalizeCursorUrl(cursor);
  if (!isMobileTimelineCursorUrl(entryName, normalized)) {
    throw new MobileNotificationRepositoryFailure(MobileNotificationRepositoryFailureKind.INVALID_CURSOR);
  }
  return normalized;
}

export function isMobileTimelineCursorUrl(entryName: string, cursor: string): boolean {
  if (cursor.length === 0 || cursor.length > MOBILE_NOTIFICATION_CURSOR_MAX_LENGTH ||
    /[\u0000-\u0020\u007F-\uFFFF]/.test(cursor)) {
    return false;
  }
  const prefix = `${MOBILE_TIMELINE_URL}/${entryName}?`;
  return cursor.startsWith(prefix) && !cursor.includes('#');
}

export function buildMobileReadAllUrl(entryName: string): string {
  if (!isValidMobileNotificationEntryName(entryName)) {
    throw new MobileNotificationRepositoryFailure(MobileNotificationRepositoryFailureKind.INVALID_ENTRY);
  }
  return `${MOBILE_TIMELINE_URL}/${entryName}/actions/readall`;
}

export function buildPrivateMessageListUrl(peerId: string, cursor?: string): string {
  if (!isValidPrivateMessagePeerId(peerId)) {
    throw new MobileNotificationRepositoryFailure(MobileNotificationRepositoryFailureKind.INVALID_PEER);
  }
  if (cursor === undefined) {
    return `${MOBILE_PRIVATE_MESSAGE_URL}?limit=${MOBILE_NOTIFICATION_LIMIT}&sender_id=${peerId}`;
  }
  const normalized = normalizeCursorUrl(cursor);
  if (!isPrivateMessageCursorUrl(peerId, normalized)) {
    throw new MobileNotificationRepositoryFailure(MobileNotificationRepositoryFailureKind.INVALID_CURSOR);
  }
  return normalized;
}

export function isPrivateMessageCursorUrl(peerId: string, cursor: string): boolean {
  if (cursor.length === 0 || cursor.length > MOBILE_NOTIFICATION_CURSOR_MAX_LENGTH ||
    /[\u0000-\u0020\u007F-\uFFFF]/.test(cursor)) {
    return false;
  }
  const prefix = `${MOBILE_PRIVATE_MESSAGE_URL}?`;
  if (!cursor.startsWith(prefix) || cursor.includes('#')) {
    return false;
  }
  // 游标必须锚定同一会话，防止跨会话/跨接口投递。
  const match = /(?:^|[?&])sender_id=([A-Za-z0-9_-]{1,128})(?:&|$)/.exec(cursor);
  return match !== null && match[1] === peerId;
}

function normalizeCursorUrl(cursor: string): string {
  if (cursor.startsWith('http://')) {
    const rest = cursor.substring('http://'.length);
    return `https://${rest}`;
  }
  return cursor;
}

function guardCursorLoop(next: string | undefined, requestUrl: string, cursor: PageCursor): PageCursor {
  if (next !== undefined && next === requestUrl) {
    return {
      isEnd: true,
      isStart: cursor.isStart,
      next: undefined,
      previous: cursor.previous,
      page: cursor.page,
      total: cursor.total
    };
  }
  return cursor;
}

export enum MobileNotificationRepositoryFailureKind {
  INVALID_CURSOR = 'invalid_cursor',
  INVALID_ENTRY = 'invalid_entry',
  INVALID_PEER = 'invalid_peer',
  CANCELLED = 'cancelled'
}

export class MobileNotificationRepositoryFailure extends Error {
  readonly kind: MobileNotificationRepositoryFailureKind;

  constructor(kind: MobileNotificationRepositoryFailureKind) {
    let message = '通知请求已取消';
    if (kind === MobileNotificationRepositoryFailureKind.INVALID_CURSOR) {
      message = '通知返回了不受信任的分页地址';
    } else if (kind === MobileNotificationRepositoryFailureKind.INVALID_ENTRY) {
      message = '通知入口名称无效';
    } else if (kind === MobileNotificationRepositoryFailureKind.INVALID_PEER) {
      message = '私信对象标识无效';
    }
    super(message);
    this.name = 'MobileNotificationRepositoryFailure';
    this.kind = kind;
  }
}

/**
 * 通知仓库（移动端 v3）。列表/已读/私信均走 api.zhihu.com 的移动端协议通道
 * （Android UA + 版本头 + 会话 Cookie，无 web ZSE 签名），语义对齐上游
 * `NotificationViewModel`/`NotificationTimelineViewModel`/`PrivateMessageViewModel`。
 */
export class DefaultMobileNotificationRepository implements MobileNotificationRepository {
  private readonly httpClient: ZhihuMobileHttpClient;
  private generation: number = 0;

  constructor(httpClient: ZhihuMobileHttpClient = new ZhihuMobileHttpClient()) {
    this.httpClient = httpClient;
  }

  cancel(): void {
    this.generation += 1;
    this.httpClient.cancel();
  }

  async getMessagePage(cursor?: string): Promise<MobileNotificationMessagePage> {
    const requestGeneration = this.generation;
    const requestUrl = buildMobileMessageListUrl(cursor);
    const response = await this.get(requestUrl);
    if (requestGeneration !== this.generation) {
      throw new MobileNotificationRepositoryFailure(MobileNotificationRepositoryFailureKind.CANCELLED);
    }
    const page = decodeMobileMessagePage(response.body);
    return {
      overview: page.overview,
      items: page.items,
      cursor: guardCursorLoop(page.cursor.next, requestUrl, page.cursor)
    };
  }

  async getTimelinePage(entryName: string, cursor?: string): Promise<MobileNotificationTimelinePage> {
    const requestGeneration = this.generation;
    const requestUrl = buildMobileTimelineListUrl(entryName, cursor);
    const response = await this.get(requestUrl);
    if (requestGeneration !== this.generation) {
      throw new MobileNotificationRepositoryFailure(MobileNotificationRepositoryFailureKind.CANCELLED);
    }
    const page = decodeMobileTimelinePage(response.body);
    return {
      items: page.items,
      cursor: guardCursorLoop(page.cursor.next, requestUrl, page.cursor)
    };
  }

  async markEntryAsRead(entryName: string): Promise<void> {
    const requestGeneration = this.generation;
    const request: ZhihuMobileHttpRequest = {
      url: buildMobileReadAllUrl(entryName),
      method: ZhihuHttpMethod.POST
    };
    await this.httpClient.execute(request);
    if (requestGeneration !== this.generation) {
      throw new MobileNotificationRepositoryFailure(MobileNotificationRepositoryFailureKind.CANCELLED);
    }
  }

  async getPrivateMessagePage(peerId: string, cursor?: string): Promise<ZhihuPrivateMessagePage> {
    const requestGeneration = this.generation;
    const requestUrl = buildPrivateMessageListUrl(peerId, cursor);
    const response = await this.get(requestUrl);
    if (requestGeneration !== this.generation) {
      throw new MobileNotificationRepositoryFailure(MobileNotificationRepositoryFailureKind.CANCELLED);
    }
    return decodePrivateMessagePage(response.body);
  }

  async getPrivateMessagePeer(peerId: string): Promise<MobileNotificationAuthor> {
    const requestGeneration = this.generation;
    if (!isValidPrivateMessagePeerId(peerId)) {
      throw new MobileNotificationRepositoryFailure(MobileNotificationRepositoryFailureKind.INVALID_PEER);
    }
    const response = await this.get(`${MOBILE_PRIVATE_MESSAGE_USER_URL}/${peerId}`);
    if (requestGeneration !== this.generation) {
      throw new MobileNotificationRepositoryFailure(MobileNotificationRepositoryFailureKind.CANCELLED);
    }
    return decodePrivateMessagePeer(response.body);
  }

  async sendPrivateMessage(peerId: string, content: string): Promise<ZhihuPrivateMessage> {
    const requestGeneration = this.generation;
    if (!isValidPrivateMessagePeerId(peerId) || content.trim().length === 0) {
      throw new MobileNotificationRepositoryFailure(MobileNotificationRepositoryFailureKind.INVALID_PEER);
    }
    const form = `receiver_id=${encodeURIComponent(peerId)}` +
      `&content=${encodeURIComponent(content)}` +
      '&content_type=0&source_type=message_list';
    const request: ZhihuMobileHttpRequest = {
      url: MOBILE_PRIVATE_MESSAGE_URL,
      method: ZhihuHttpMethod.POST,
      body: encryptZhihuMessageBody(form),
      xZse93: MOBILE_ZSE93_ENCRYPTED_FORM
    };
    const response = await this.httpClient.execute(request);
    if (requestGeneration !== this.generation) {
      throw new MobileNotificationRepositoryFailure(MobileNotificationRepositoryFailureKind.CANCELLED);
    }
    return decodePrivateMessageReceipt(response.body);
  }

  private get(url: string): Promise<ZhihuHttpResponse> {
    const request: ZhihuMobileHttpRequest = {
      url: url,
      method: ZhihuHttpMethod.GET
    };
    return this.httpClient.execute(request);
  }
}
