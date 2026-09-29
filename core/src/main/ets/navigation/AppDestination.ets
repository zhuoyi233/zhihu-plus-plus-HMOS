import { JsonObjectValue, JsonNumberValue, JsonStringValue, parseStrictJson } from './StrictJson';

export enum AppDestinationName {
  HOME = 'Home',
  FOLLOWING = 'Following',
  HOT = 'Hot',
  DAILY = 'Daily',
  DAILY_STORY = 'DailyStory',
  QUESTION = 'Question',
  ANSWER = 'Answer',
  ARTICLE = 'Article',
  VIDEO = 'Video',
  PIN = 'Pin',
  PEOPLE = 'People',
  COMMENT = 'Comment',
  SEARCH = 'Search',
  COLLECTION = 'Collection',
  COLLECTIONS = 'Collections',
  NOTIFICATION = 'Notification',
  NOTIFICATION_ENTRY = 'NotificationEntry',
  NOTIFICATION_SETTINGS = 'NotificationSettings',
  PRIVATE_MESSAGE = 'PrivateMessage',
  LOGIN = 'Login',
  SETTINGS = 'Settings',
  APPEARANCE_SETTINGS = 'AppearanceSettings',
  THEME_COLOR_SETTINGS = 'ThemeColorSettings',
  IDENTITY_MANAGEMENT = 'IdentityManagement',
  READING_SETTINGS = 'ReadingSettings',
  SYSTEM_UPDATE_SETTINGS = 'SystemUpdateSettings',
  WHATS_NEW = 'WhatsNew',
  RECOMMENDATION_FILTER_SETTINGS = 'RecommendationFilterSettings',
  BLOCKING_RULES = 'BlockingRules',
  BLOCKED_FEED_HISTORY = 'BlockedFeedHistory',
  READ_HISTORY = 'ReadHistory',
  LOCAL_HISTORY = 'LocalHistory',
  TECHNICAL_LAB = 'TechnicalLab',
  READER_PROBE = 'ReaderProbe',
  IMAGE_PROBE = 'ImageProbe',
  DATABASE_PROBE = 'DatabaseProbe',
  DEEP_LINK_PROBE = 'DeepLinkProbe',
  QR_SCAN_PROBE = 'QrScanProbe',
  QR_DESKTOP_LOGIN_SCAN = 'QrDesktopLoginScan',
  BACKGROUND_TASK_PROBE = 'BackgroundTaskProbe',
  DOMAIN_FIXTURE_PROBE = 'DomainFixtureProbe',
  WRITE_ANSWER = 'WriteAnswer',
  WRITE_PIN = 'WritePin',
  PIN_DRAFTS = 'PinDrafts'
}

export interface StatelessDestination {
  readonly name: AppDestinationName.HOME | AppDestinationName.FOLLOWING | AppDestinationName.HOT |
    AppDestinationName.DAILY | AppDestinationName.NOTIFICATION;
}

/** WHATS_NEW 不在本联合内：它有独立接口 WhatsNewDestination（带可选 version 参数），
 * isInfrastructureDestination 对其单独返回 true。 */
export interface InfrastructureDestination {
  readonly name: AppDestinationName.LOGIN | AppDestinationName.SETTINGS | AppDestinationName.APPEARANCE_SETTINGS |
    AppDestinationName.THEME_COLOR_SETTINGS |
    AppDestinationName.IDENTITY_MANAGEMENT | AppDestinationName.READING_SETTINGS |
    AppDestinationName.SYSTEM_UPDATE_SETTINGS |
    AppDestinationName.RECOMMENDATION_FILTER_SETTINGS |
    AppDestinationName.BLOCKING_RULES |
    AppDestinationName.BLOCKED_FEED_HISTORY | AppDestinationName.READ_HISTORY | AppDestinationName.LOCAL_HISTORY |
    AppDestinationName.TECHNICAL_LAB |
    AppDestinationName.NOTIFICATION_SETTINGS | AppDestinationName.NOTIFICATION_ENTRY |
    AppDestinationName.PRIVATE_MESSAGE |
    AppDestinationName.READER_PROBE | AppDestinationName.IMAGE_PROBE |
    AppDestinationName.DATABASE_PROBE | AppDestinationName.DEEP_LINK_PROBE |
    AppDestinationName.QR_SCAN_PROBE | AppDestinationName.QR_DESKTOP_LOGIN_SCAN |
    AppDestinationName.BACKGROUND_TASK_PROBE |
    AppDestinationName.DOMAIN_FIXTURE_PROBE | AppDestinationName.PIN_DRAFTS;
}

export interface ContentDestination {
  readonly name: AppDestinationName.QUESTION | AppDestinationName.ANSWER |
    AppDestinationName.ARTICLE | AppDestinationName.VIDEO | AppDestinationName.PIN |
    AppDestinationName.PEOPLE | AppDestinationName.COLLECTION | AppDestinationName.COLLECTIONS |
    AppDestinationName.DAILY_STORY;
  readonly id: string;
}

export interface CommentDestination {
  readonly name: AppDestinationName.COMMENT;
  readonly contentType: 'answer' | 'article' | 'question' | 'pin';
  readonly contentId: string;
  readonly commentId?: string;
  /** 划线句评论（seg_id 维度，对齐上游 SegmentCommentHolder）：携带后评论页改为划线评论数据源。 */
  readonly segmentId?: string;
  readonly segmentContent?: string;
  readonly segmentParagraphId?: string;
  readonly segmentStartOffset?: number;
  readonly segmentEndOffset?: number;
}

export interface SearchDestination {
  readonly name: AppDestinationName.SEARCH;
  readonly query: string;
}

export interface WriteAnswerDestination {
  readonly name: AppDestinationName.WRITE_ANSWER;
  readonly questionId: string;
  readonly answerId?: string;
}

export interface WritePinDestination {
  readonly name: AppDestinationName.WRITE_PIN;
  readonly draftId: string;
}

/** 通知分类/邀请回答时间线入口（对齐上游 `Notification.Entry`）。 */
export interface NotificationEntryDestination {
  readonly name: AppDestinationName.NOTIFICATION_ENTRY;
  readonly entryName: string;
  readonly title: string;
}

/** 私信会话页（对齐上游 `Notification.Message`）。 */
export interface PrivateMessageDestination {
  readonly name: AppDestinationName.PRIVATE_MESSAGE;
  readonly peerId: string;
  readonly peerName?: string;
  readonly avatarUrl?: string;
}

/** “新版本更新”页：version 缺省时展示本机已装版本的 Release；携带时展示该目标版本
 * 的 Release（检查到更新后的“更新内容预览”，对齐主页更新卡片与设置页入口）。 */
export interface WhatsNewDestination {
  readonly name: AppDestinationName.WHATS_NEW;
  readonly version?: string;
}

export type AppDestination = StatelessDestination | InfrastructureDestination | ContentDestination |
  CommentDestination | SearchDestination | WriteAnswerDestination | WritePinDestination |
  NotificationEntryDestination | PrivateMessageDestination | WhatsNewDestination;

export const MAX_SEARCH_QUERY_LENGTH: number = 200;
export const MAX_DECIMAL_CONTENT_ID_LENGTH: number = 30;
export const MAX_PEOPLE_IDENTIFIER_LENGTH: number = 200;
export const LOCAL_DRAFT_ID_LENGTH: number = 36;

export function isSafeSearchDestinationQuery(value: string | undefined): boolean {
  return typeof value === 'string' && value.length <= MAX_SEARCH_QUERY_LENGTH &&
    !/[\u0000-\u001F\u007F-\u009F]/.test(value);
}

export function isSafeDecimalContentId(value: string | undefined): boolean {
  return typeof value === 'string' && /^\d{1,30}$/.test(value);
}

export function isSafePinContentId(value: string | undefined): boolean {
  return typeof value === 'string' && /^[1-9][0-9]{0,29}$/.test(value);
}

export function isSafePeopleIdentifier(value: string | undefined): boolean {
  return typeof value === 'string' && /^[A-Za-z0-9_-]{1,200}$/.test(value);
}

/** P4 本地草稿使用规范化的小写 UUID，避免把任意字符串作为持久化键或导航身份。 */
export function isSafeLocalDraftId(value: string | undefined): boolean {
  return typeof value === 'string' && value.length === LOCAL_DRAFT_ID_LENGTH &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value);
}

export function isAppDestinationName(name: string): boolean {
  switch (name) {
    case AppDestinationName.HOME:
    case AppDestinationName.FOLLOWING:
    case AppDestinationName.HOT:
    case AppDestinationName.DAILY:
    case AppDestinationName.DAILY_STORY:
    case AppDestinationName.QUESTION:
    case AppDestinationName.ANSWER:
    case AppDestinationName.ARTICLE:
    case AppDestinationName.VIDEO:
    case AppDestinationName.PIN:
    case AppDestinationName.PEOPLE:
    case AppDestinationName.COMMENT:
    case AppDestinationName.SEARCH:
    case AppDestinationName.COLLECTION:
    case AppDestinationName.COLLECTIONS:
    case AppDestinationName.NOTIFICATION:
    case AppDestinationName.NOTIFICATION_ENTRY:
    case AppDestinationName.NOTIFICATION_SETTINGS:
    case AppDestinationName.PRIVATE_MESSAGE:
    case AppDestinationName.LOGIN:
    case AppDestinationName.SETTINGS:
    case AppDestinationName.APPEARANCE_SETTINGS:
    case AppDestinationName.THEME_COLOR_SETTINGS:
    case AppDestinationName.IDENTITY_MANAGEMENT:
    case AppDestinationName.READING_SETTINGS:
    case AppDestinationName.SYSTEM_UPDATE_SETTINGS:
    case AppDestinationName.WHATS_NEW:
    case AppDestinationName.RECOMMENDATION_FILTER_SETTINGS:
    case AppDestinationName.BLOCKING_RULES:
    case AppDestinationName.BLOCKED_FEED_HISTORY:
    case AppDestinationName.READ_HISTORY:
    case AppDestinationName.LOCAL_HISTORY:
    case AppDestinationName.TECHNICAL_LAB:
    case AppDestinationName.READER_PROBE:
    case AppDestinationName.IMAGE_PROBE:
    case AppDestinationName.DATABASE_PROBE:
    case AppDestinationName.DEEP_LINK_PROBE:
    case AppDestinationName.QR_SCAN_PROBE:
    case AppDestinationName.QR_DESKTOP_LOGIN_SCAN:
    case AppDestinationName.BACKGROUND_TASK_PROBE:
    case AppDestinationName.DOMAIN_FIXTURE_PROBE:
    case AppDestinationName.WRITE_ANSWER:
    case AppDestinationName.WRITE_PIN:
    case AppDestinationName.PIN_DRAFTS:
      return true;
    default:
      return false;
  }
}

export function decodeAppDestination(name: string, param: Object): AppDestination | undefined {
  if (!isAppDestinationName(name)) {
    return undefined;
  }
  let wire: JsonObjectValue;
  try {
    const parsed = parseStrictJson(JSON.stringify(param));
    if (!(parsed instanceof JsonObjectValue)) {
      return undefined;
    }
    wire = parsed;
  } catch (_error) {
    return undefined;
  }
  const wireName = readString(wire, 'name');
  if (wireName !== name) {
    return undefined;
  }

  switch (name) {
    case AppDestinationName.HOME:
      return hasNoParameters(wire) ? { name: AppDestinationName.HOME } : undefined;
    case AppDestinationName.FOLLOWING:
      return hasNoParameters(wire) ? { name: AppDestinationName.FOLLOWING } : undefined;
    case AppDestinationName.HOT:
      return hasNoParameters(wire) ? { name: AppDestinationName.HOT } : undefined;
    case AppDestinationName.DAILY:
      return hasNoParameters(wire) ? { name: AppDestinationName.DAILY } : undefined;
    case AppDestinationName.DAILY_STORY:
      return decodeContent(wire, AppDestinationName.DAILY_STORY);
    case AppDestinationName.NOTIFICATION:
      return hasNoParameters(wire) ? { name: AppDestinationName.NOTIFICATION } : undefined;
    case AppDestinationName.NOTIFICATION_ENTRY:
      return decodeNotificationEntry(wire);
    case AppDestinationName.PRIVATE_MESSAGE:
      return decodePrivateMessage(wire);
    case AppDestinationName.NOTIFICATION_SETTINGS:
      return hasNoParameters(wire) ? { name: AppDestinationName.NOTIFICATION_SETTINGS } : undefined;
    case AppDestinationName.APPEARANCE_SETTINGS:
      return hasNoParameters(wire) ? { name: AppDestinationName.APPEARANCE_SETTINGS } : undefined;
    case AppDestinationName.THEME_COLOR_SETTINGS:
      return hasNoParameters(wire) ? { name: AppDestinationName.THEME_COLOR_SETTINGS } : undefined;
    case AppDestinationName.IDENTITY_MANAGEMENT:
      return hasNoParameters(wire) ? { name: AppDestinationName.IDENTITY_MANAGEMENT } : undefined;
    case AppDestinationName.READING_SETTINGS:
      return hasNoParameters(wire) ? { name: AppDestinationName.READING_SETTINGS } : undefined;
    case AppDestinationName.SYSTEM_UPDATE_SETTINGS:
      return hasNoParameters(wire) ? { name: AppDestinationName.SYSTEM_UPDATE_SETTINGS } : undefined;
    case AppDestinationName.WHATS_NEW:
      return decodeWhatsNew(wire);
    case AppDestinationName.RECOMMENDATION_FILTER_SETTINGS:
      return hasNoParameters(wire) ? { name: AppDestinationName.RECOMMENDATION_FILTER_SETTINGS } : undefined;
    case AppDestinationName.LOGIN:
      return hasNoParameters(wire) ? { name: AppDestinationName.LOGIN } : undefined;
    case AppDestinationName.SETTINGS:
      return hasNoParameters(wire) ? { name: AppDestinationName.SETTINGS } : undefined;
    case AppDestinationName.BLOCKING_RULES:
      return hasNoParameters(wire) ? { name: AppDestinationName.BLOCKING_RULES } : undefined;
    case AppDestinationName.BLOCKED_FEED_HISTORY:
      return hasNoParameters(wire) ? { name: AppDestinationName.BLOCKED_FEED_HISTORY } : undefined;
    case AppDestinationName.READ_HISTORY:
      return hasNoParameters(wire) ? { name: AppDestinationName.READ_HISTORY } : undefined;
    case AppDestinationName.LOCAL_HISTORY:
      return hasNoParameters(wire) ? { name: AppDestinationName.LOCAL_HISTORY } : undefined;
    case AppDestinationName.TECHNICAL_LAB:
      return hasNoParameters(wire) ? { name: AppDestinationName.TECHNICAL_LAB } : undefined;
    case AppDestinationName.READER_PROBE:
      return hasNoParameters(wire) ? { name: AppDestinationName.READER_PROBE } : undefined;
    case AppDestinationName.IMAGE_PROBE:
      return hasNoParameters(wire) ? { name: AppDestinationName.IMAGE_PROBE } : undefined;
    case AppDestinationName.DATABASE_PROBE:
      return hasNoParameters(wire) ? { name: AppDestinationName.DATABASE_PROBE } : undefined;
    case AppDestinationName.DEEP_LINK_PROBE:
      return hasNoParameters(wire) ? { name: AppDestinationName.DEEP_LINK_PROBE } : undefined;
    case AppDestinationName.QR_SCAN_PROBE:
      return hasNoParameters(wire) ? { name: AppDestinationName.QR_SCAN_PROBE } : undefined;
    case AppDestinationName.QR_DESKTOP_LOGIN_SCAN:
      return hasNoParameters(wire) ? { name: AppDestinationName.QR_DESKTOP_LOGIN_SCAN } : undefined;
    case AppDestinationName.BACKGROUND_TASK_PROBE:
      return hasNoParameters(wire) ? { name: AppDestinationName.BACKGROUND_TASK_PROBE } : undefined;
    case AppDestinationName.DOMAIN_FIXTURE_PROBE:
      return hasNoParameters(wire) ? { name: AppDestinationName.DOMAIN_FIXTURE_PROBE } : undefined;
    case AppDestinationName.PIN_DRAFTS:
      return hasNoParameters(wire) ? { name: AppDestinationName.PIN_DRAFTS } : undefined;
    case AppDestinationName.QUESTION:
      return decodeContent(wire, AppDestinationName.QUESTION);
    case AppDestinationName.ANSWER:
      return decodeContent(wire, AppDestinationName.ANSWER);
    case AppDestinationName.ARTICLE:
      return decodeContent(wire, AppDestinationName.ARTICLE);
    case AppDestinationName.VIDEO:
      return decodeContent(wire, AppDestinationName.VIDEO);
    case AppDestinationName.PIN:
      return decodeContent(wire, AppDestinationName.PIN);
    case AppDestinationName.PEOPLE:
      return decodeContent(wire, AppDestinationName.PEOPLE);
    case AppDestinationName.COLLECTION:
      return decodeContent(wire, AppDestinationName.COLLECTION);
    case AppDestinationName.COLLECTIONS:
      return decodeContent(wire, AppDestinationName.COLLECTIONS);
    case AppDestinationName.WRITE_ANSWER:
      return decodeWriteAnswer(wire);
    case AppDestinationName.WRITE_PIN:
      return decodeWritePin(wire);
    case AppDestinationName.COMMENT:
      const contentType = readString(wire, 'contentType');
      const contentId = readString(wire, 'contentId');
      const commentId = readString(wire, 'commentId');
      const segmentId = readString(wire, 'segmentId');
      const segmentContent = readString(wire, 'segmentContent');
      const segmentParagraphId = readString(wire, 'segmentParagraphId');
      const segmentStartOffset = readNonNegativeInt(wire, 'segmentStartOffset');
      const segmentEndOffset = readNonNegativeInt(wire, 'segmentEndOffset');
      const hasSegment = segmentId !== undefined || segmentContent !== undefined ||
        segmentParagraphId !== undefined || segmentStartOffset !== undefined || segmentEndOffset !== undefined;
      if ((contentType !== 'answer' && contentType !== 'article' && contentType !== 'question' && contentType !== 'pin') ||
        contentId === undefined || !hasText(contentId) || readString(wire, 'id') !== undefined || readString(wire, 'query') !== undefined ||
        (commentId !== undefined && !hasText(commentId)) ||
        (hasSegment && (segmentId === undefined || !isSafeSegmentId(segmentId) ||
          segmentContent === undefined || !hasText(segmentContent) ||
          segmentParagraphId === undefined || !hasText(segmentParagraphId) ||
          segmentStartOffset === undefined || segmentEndOffset === undefined || segmentEndOffset < segmentStartOffset)) ||
        !hasOnlyFields(wire, ['name', 'contentType', 'contentId', 'commentId', 'segmentId', 'segmentContent',
          'segmentParagraphId', 'segmentStartOffset', 'segmentEndOffset'])) {
        return undefined;
      }
      if (hasSegment) {
        return {
          name: AppDestinationName.COMMENT,
          contentType: contentType,
          contentId: contentId,
          segmentId: segmentId,
          segmentContent: segmentContent,
          segmentParagraphId: segmentParagraphId,
          segmentStartOffset: segmentStartOffset,
          segmentEndOffset: segmentEndOffset
        };
      }
      return commentId === undefined
        ? { name: AppDestinationName.COMMENT, contentType: contentType, contentId: contentId }
        : {
          name: AppDestinationName.COMMENT,
          contentType: contentType,
          contentId: contentId,
          commentId: commentId
        };
    case AppDestinationName.SEARCH:
      const query = readString(wire, 'query');
      if (query === undefined || !isSafeSearchDestinationQuery(query) || readString(wire, 'id') !== undefined ||
        readString(wire, 'contentId') !== undefined || readString(wire, 'commentId') !== undefined ||
        !hasOnlyFields(wire, ['name', 'query'])) {
        return undefined;
      }
      return { name: AppDestinationName.SEARCH, query: query };
    default:
      return undefined;
  }
}

export function isInfrastructureDestination(destination: AppDestination): boolean {
  switch (destination.name) {
    case AppDestinationName.LOGIN:
    case AppDestinationName.SETTINGS:
    case AppDestinationName.APPEARANCE_SETTINGS:
    case AppDestinationName.THEME_COLOR_SETTINGS:
    case AppDestinationName.IDENTITY_MANAGEMENT:
    case AppDestinationName.READING_SETTINGS:
    case AppDestinationName.SYSTEM_UPDATE_SETTINGS:
    case AppDestinationName.WHATS_NEW:
    case AppDestinationName.RECOMMENDATION_FILTER_SETTINGS:
    case AppDestinationName.BLOCKING_RULES:
    case AppDestinationName.BLOCKED_FEED_HISTORY:
    case AppDestinationName.READ_HISTORY:
    case AppDestinationName.LOCAL_HISTORY:
    case AppDestinationName.TECHNICAL_LAB:
    case AppDestinationName.NOTIFICATION_SETTINGS:
    case AppDestinationName.NOTIFICATION_ENTRY:
    case AppDestinationName.PRIVATE_MESSAGE:
    case AppDestinationName.READER_PROBE:
    case AppDestinationName.IMAGE_PROBE:
    case AppDestinationName.DATABASE_PROBE:
    case AppDestinationName.DEEP_LINK_PROBE:
    case AppDestinationName.QR_SCAN_PROBE:
    case AppDestinationName.QR_DESKTOP_LOGIN_SCAN:
    case AppDestinationName.BACKGROUND_TASK_PROBE:
    case AppDestinationName.DOMAIN_FIXTURE_PROBE:
    case AppDestinationName.PIN_DRAFTS:
      return true;
    default:
      return false;
  }
}

export function shouldReloadAfterAuthentication(destination: AppDestination): boolean {
  switch (destination.name) {
    case AppDestinationName.QUESTION:
    case AppDestinationName.ANSWER:
    case AppDestinationName.ARTICLE:
    case AppDestinationName.SEARCH:
    case AppDestinationName.FOLLOWING:
    case AppDestinationName.HOT:
    case AppDestinationName.PIN:
    case AppDestinationName.PEOPLE:
    case AppDestinationName.READ_HISTORY:
    case AppDestinationName.COLLECTION:
    case AppDestinationName.COLLECTIONS:
    case AppDestinationName.NOTIFICATION:
    case AppDestinationName.NOTIFICATION_ENTRY:
    case AppDestinationName.PRIVATE_MESSAGE:
    case AppDestinationName.WRITE_ANSWER:
    case AppDestinationName.WRITE_PIN:
    case AppDestinationName.PIN_DRAFTS:
      return true;
    default:
      return false;
  }
}

/** 校验 WhatsNewDestination.version：仅接受点分数字版本名（如 0.5.4），防止任意字符串入栈。 */
export function isSafeWhatsNewVersion(value: string | undefined): boolean {
  return typeof value === 'string' && /^\d{1,4}(\.\d{1,4}){0,3}$/.test(value);
}

function decodeWhatsNew(wire: JsonObjectValue): WhatsNewDestination | undefined {
  const version = readString(wire, 'version');
  // version 缺省 = 展示本机版本的版本说明模式；携带时必须是安全的点分数字版本名。
  if ((version !== undefined && !isSafeWhatsNewVersion(version)) ||
    !hasOnlyFields(wire, version === undefined ? ['name'] : ['name', 'version'])) {
    return undefined;
  }
  return version === undefined ? { name: AppDestinationName.WHATS_NEW } : { name: AppDestinationName.WHATS_NEW, version: version };
}

function decodeContent(wire: JsonObjectValue, name: AppDestinationName.QUESTION | AppDestinationName.ANSWER |
  AppDestinationName.ARTICLE | AppDestinationName.VIDEO | AppDestinationName.PIN |
  AppDestinationName.PEOPLE | AppDestinationName.COLLECTION | AppDestinationName.COLLECTIONS |
  AppDestinationName.DAILY_STORY): ContentDestination | undefined {
  const id = readString(wire, 'id');
  if (id === undefined || !hasText(id) ||
    readString(wire, 'contentId') !== undefined || readString(wire, 'commentId') !== undefined ||
    readString(wire, 'query') !== undefined ||
    !hasOnlyFields(wire, ['name', 'id'])) {
    return undefined;
  }
  let validId = true;
  if (name === AppDestinationName.PIN || name === AppDestinationName.DAILY_STORY) {
    validId = isSafePinContentId(id);
  } else if (name === AppDestinationName.PEOPLE || name === AppDestinationName.COLLECTIONS) {
    validId = isSafePeopleIdentifier(id);
  } else if (name === AppDestinationName.QUESTION || name === AppDestinationName.ANSWER ||
    name === AppDestinationName.ARTICLE || name === AppDestinationName.COLLECTION) {
    validId = isSafeDecimalContentId(id);
  }
  return validId ? { name: name, id: id } : undefined;
}

function hasNoParameters(wire: JsonObjectValue): boolean {
  return readString(wire, 'id') === undefined && readString(wire, 'contentId') === undefined &&
    readString(wire, 'commentId') === undefined && readString(wire, 'query') === undefined &&
    readString(wire, 'questionId') === undefined && readString(wire, 'answerId') === undefined &&
    readString(wire, 'draftId') === undefined &&
    hasOnlyFields(wire, ['name']);
}

/**
 * 通知分类/邀请回答时间线入口（对齐上游 `Notification.Entry`）。entryName 仅接受
 * 移动端 v3 的已知入口命名（comment/like/favlist_me/follow/invite 等）。
 */
function isSafeNotificationEntryName(value: string | undefined): boolean {
  return typeof value === 'string' && /^[a-z_]{1,40}$/.test(value);
}

function isSafeNotificationEntryTitle(value: string | undefined): boolean {
  return typeof value === 'string' && value.trim().length > 0 && value.length <= 60 &&
    !/[\u0000-\u001F\u007F-\u009F]/.test(value);
}

function isSafePrivateMessagePeerId(value: string | undefined): boolean {
  return typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(value);
}

function isSafePrivateMessagePeerName(value: string | undefined): boolean {
  return typeof value === 'string' && value.trim().length > 0 && value.length <= 60 &&
    !/[\u0000-\u001F\u007F-\u009F]/.test(value);
}

function isSafePrivateMessageAvatarUrl(value: string | undefined): boolean {
  return typeof value === 'string' && value.length > 0 && value.length <= 500 &&
    /^https:\/\/[A-Za-z0-9.-]+(?::\d{2,5})?\/[A-Za-z0-9._~/%-]*(\?[A-Za-z0-9._~&=%-]*)?$/.test(value);
}

function decodeNotificationEntry(wire: JsonObjectValue): NotificationEntryDestination | undefined {
  const entryName = readString(wire, 'entryName');
  const title = readString(wire, 'title');
  if (!isSafeNotificationEntryName(entryName) || !isSafeNotificationEntryTitle(title) ||
    !hasOnlyFields(wire, ['name', 'entryName', 'title'])) {
    return undefined;
  }
  const destination: NotificationEntryDestination = {
    name: AppDestinationName.NOTIFICATION_ENTRY,
    entryName: entryName as string,
    title: title as string
  };
  return destination;
}

function decodePrivateMessage(wire: JsonObjectValue): PrivateMessageDestination | undefined {
  const peerId = readString(wire, 'peerId');
  const peerName = readString(wire, 'peerName');
  const avatarUrl = readString(wire, 'avatarUrl');
  if (!isSafePrivateMessagePeerId(peerId) ||
    (peerName !== undefined && !isSafePrivateMessagePeerName(peerName)) ||
    (avatarUrl !== undefined && !isSafePrivateMessageAvatarUrl(avatarUrl)) ||
    !hasOnlyFields(wire, ['name', 'peerId', 'peerName', 'avatarUrl'])) {
    return undefined;
  }
  const destination: PrivateMessageDestination = {
    name: AppDestinationName.PRIVATE_MESSAGE,
    peerId: peerId as string,
    peerName: peerName,
    avatarUrl: avatarUrl
  };
  return destination;
}

function decodeWriteAnswer(wire: JsonObjectValue): WriteAnswerDestination | undefined {
  const questionId = readString(wire, 'questionId');
  const answerId = readString(wire, 'answerId');
  if (questionId === undefined || !isSafeDecimalContentId(questionId) ||
    (answerId !== undefined && !isSafeDecimalContentId(answerId)) ||
    !hasOnlyFields(wire, ['name', 'questionId', 'answerId'])) {
    return undefined;
  }
  return answerId === undefined
    ? { name: AppDestinationName.WRITE_ANSWER, questionId: questionId }
    : { name: AppDestinationName.WRITE_ANSWER, questionId: questionId, answerId: answerId };
}

function decodeWritePin(wire: JsonObjectValue): WritePinDestination | undefined {
  const draftId = readString(wire, 'draftId');
  if (draftId === undefined || !isSafeLocalDraftId(draftId) || !hasOnlyFields(wire, ['name', 'draftId'])) {
    return undefined;
  }
  return { name: AppDestinationName.WRITE_PIN, draftId: draftId };
}

function hasText(value: string | undefined): boolean {
  return typeof value === 'string' && value.trim().length > 0;
}

function hasOnlyFields(wire: JsonObjectValue, allowed: Array<string>): boolean {
  return wire.entries.every((entry): boolean => allowed.includes(entry.name));
}

function readString(wire: JsonObjectValue, name: string): string | undefined {
  const value = wire.get(name);
  return value instanceof JsonStringValue ? value.value : undefined;
}

function readNonNegativeInt(wire: JsonObjectValue, name: string): number | undefined {
  const value = wire.get(name);
  if (value instanceof JsonNumberValue && Number.isSafeInteger(value.value) && value.value >= 0) {
    return value.value;
  }
  return undefined;
}

/** 划线 seg id：正整数（可逗号分隔多个，对齐上游 segIds joinToString(",")）。 */
function isSafeSegmentId(value: string): boolean {
  return /^[1-9][0-9]{0,29}(,[1-9][0-9]{0,29})*$/.test(value);
}
