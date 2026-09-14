import { MobileNotificationTimelineItem } from './MobileNotificationModels';

/**
 * 应用内显示开关对应的通知类型（对齐上游 NotificationTypes.kt）。
 * `inviteAnswer` 为 opt-in，默认关闭；修复或扩展不得改变默认开关策略。
 */
export enum NotificationKind {
  LIKE_ANSWER = 'like_answer',
  LIKE_COMMENT = 'like_comment',
  REPLY_COMMENT = 'reply_comment',
  INVITE_ANSWER = 'invite_answer'
}

export const NOTIFICATION_KINDS: Array<NotificationKind> = [
  NotificationKind.LIKE_ANSWER,
  NotificationKind.LIKE_COMMENT,
  NotificationKind.REPLY_COMMENT,
  NotificationKind.INVITE_ANSWER
];

export interface NotificationKindInfo {
  readonly displayName: string;
  readonly defaultValue: boolean;
}

export function notificationKindInfo(kind: NotificationKind): NotificationKindInfo {
  if (kind === NotificationKind.LIKE_COMMENT) {
    return { displayName: '喜欢了你的评论', defaultValue: true };
  }
  if (kind === NotificationKind.REPLY_COMMENT) {
    return { displayName: '回复了你的评论', defaultValue: true };
  }
  if (kind === NotificationKind.INVITE_ANSWER) {
    return { displayName: '邀请你回答问题', defaultValue: false };
  }
  return { displayName: '喜欢了你的回答', defaultValue: true };
}

/**
 * 按通知动词匹配通知类型。语义与上游 `matchNotificationType` 一致
 * （全串匹配），用于应用内显示开关的过滤。
 */
export function matchNotificationKind(verb: string): NotificationKind | undefined {
  if (/^喜欢了你的回答$/.test(verb)) {
    return NotificationKind.LIKE_ANSWER;
  }
  if (/^喜欢了.*你的评论$/.test(verb)) {
    return NotificationKind.LIKE_COMMENT;
  }
  if (/^回复了.*你的评论$/.test(verb)) {
    return NotificationKind.REPLY_COMMENT;
  }
  if (/^\s?(邀请你回答问题|的提问等你来答|邀请你回答)$/.test(verb)) {
    return NotificationKind.INVITE_ANSWER;
  }
  return undefined;
}

export interface NotificationPreferences {
  readonly likeAnswerDisplay: boolean;
  readonly likeCommentDisplay: boolean;
  readonly replyCommentDisplay: boolean;
  readonly inviteAnswerDisplay: boolean;
  readonly autoMarkAsRead: boolean;
  readonly unreadBadge: boolean;
}

export function defaultNotificationPreferences(): NotificationPreferences {
  return {
    likeAnswerDisplay: true,
    likeCommentDisplay: true,
    replyCommentDisplay: true,
    inviteAnswerDisplay: false,
    autoMarkAsRead: false,
    unreadBadge: true
  };
}

export function normalizeNotificationPreferences(value: NotificationPreferences): NotificationPreferences {
  const defaults = defaultNotificationPreferences();
  return {
    likeAnswerDisplay: typeof value.likeAnswerDisplay === 'boolean' ? value.likeAnswerDisplay : defaults.likeAnswerDisplay,
    likeCommentDisplay: typeof value.likeCommentDisplay === 'boolean' ? value.likeCommentDisplay : defaults.likeCommentDisplay,
    replyCommentDisplay: typeof value.replyCommentDisplay === 'boolean' ? value.replyCommentDisplay : defaults.replyCommentDisplay,
    inviteAnswerDisplay: typeof value.inviteAnswerDisplay === 'boolean' ? value.inviteAnswerDisplay : defaults.inviteAnswerDisplay,
    autoMarkAsRead: typeof value.autoMarkAsRead === 'boolean' ? value.autoMarkAsRead : defaults.autoMarkAsRead,
    unreadBadge: typeof value.unreadBadge === 'boolean' ? value.unreadBadge : defaults.unreadBadge
  };
}

export function notificationDisplayInApp(preferences: NotificationPreferences, kind: NotificationKind): boolean {
  if (kind === NotificationKind.LIKE_COMMENT) {
    return preferences.likeCommentDisplay;
  }
  if (kind === NotificationKind.REPLY_COMMENT) {
    return preferences.replyCommentDisplay;
  }
  if (kind === NotificationKind.INVITE_ANSWER) {
    return preferences.inviteAnswerDisplay;
  }
  return preferences.likeAnswerDisplay;
}

export function withNotificationDisplayInApp(
  preferences: NotificationPreferences,
  kind: NotificationKind,
  enabled: boolean
): NotificationPreferences {
  return {
    likeAnswerDisplay: kind === NotificationKind.LIKE_ANSWER ? enabled : preferences.likeAnswerDisplay,
    likeCommentDisplay: kind === NotificationKind.LIKE_COMMENT ? enabled : preferences.likeCommentDisplay,
    replyCommentDisplay: kind === NotificationKind.REPLY_COMMENT ? enabled : preferences.replyCommentDisplay,
    inviteAnswerDisplay: kind === NotificationKind.INVITE_ANSWER ? enabled : preferences.inviteAnswerDisplay,
    autoMarkAsRead: preferences.autoMarkAsRead,
    unreadBadge: preferences.unreadBadge
  };
}

/**
 * 通知偏好持久化网关，由 AppPreferencesStore 实现（key 前缀 `notification_`，
 * 与 Android 上游 `display_in_app_`/`auto_mark_notifications_read`/
 * `show_unread_badge` 的默认值语义一致，仅 key 命名不同）。
 */
export interface NotificationSettingsGateway {
  loadNotificationPreferences(): Promise<NotificationPreferences>;
  saveNotificationPreferences(value: NotificationPreferences): Promise<void>;
}

/**
 * 时间线条目是否按显示开关放行（对齐上游 `shouldShowNotification`：
 * 动词取 content.title/subTitle/text 中首个非空串）。
 */
export function shouldShowMobileNotification(item: MobileNotificationTimelineItem,
  preferences: NotificationPreferences): boolean {
  const content = item.content;
  if (content === undefined) {
    return true;
  }
  let verb = content.title.trim();
  if (verb.length === 0) {
    verb = content.subTitle.trim();
  }
  if (verb.length === 0) {
    verb = content.text.trim();
  }
  if (verb.length === 0) {
    return true;
  }
  const kind = matchNotificationKind(verb);
  if (kind === undefined) {
    return true;
  }
  return notificationDisplayInApp(preferences, kind);
}
