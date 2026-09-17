import { PageCursor } from './DomainModels';

/**
 * 通知分类（对齐上游 `NotificationViewModel.MobileNotificationCategory`，移动端
 * message/v3 / timeline/entry 的四个入口）。
 */
export enum MobileNotificationCategory {
  COMMENT = 'comment',
  LIKE = 'like',
  FAVORITE = 'favlist_me',
  FOLLOW = 'follow'
}

export const MOBILE_NOTIFICATION_CATEGORIES: Array<MobileNotificationCategory> = [
  MobileNotificationCategory.COMMENT,
  MobileNotificationCategory.LIKE,
  MobileNotificationCategory.FAVORITE,
  MobileNotificationCategory.FOLLOW
];

/** 邀请回答时间线入口（不属于四分类，由 message/v3 的 columnHead 触达）。 */
export const MOBILE_NOTIFICATION_INVITE_ENTRY = 'invite';

export interface MobileNotificationCategoryInfo {
  readonly entryName: string;
  readonly detailTitle: string;
}

export function mobileNotificationCategoryInfo(category: MobileNotificationCategory):
  MobileNotificationCategoryInfo {
  if (category === MobileNotificationCategory.LIKE) {
    return { entryName: 'like', detailTitle: '赞同喜欢' };
  }
  if (category === MobileNotificationCategory.FAVORITE) {
    return { entryName: 'favlist_me', detailTitle: '收藏了我' };
  }
  if (category === MobileNotificationCategory.FOLLOW) {
    return { entryName: 'follow', detailTitle: '关注订阅' };
  }
  return { entryName: 'comment', detailTitle: '评论转发@' };
}

export function mobileNotificationCategoryByEntryName(entryName: string): MobileNotificationCategory |
  undefined {
  const match = MOBILE_NOTIFICATION_CATEGORIES.find((category: MobileNotificationCategory): boolean =>
    mobileNotificationCategoryInfo(category).entryName === entryName);
  return match;
}

export interface MobileNotificationHeadEntry {
  readonly detailTitle: string;
  readonly unreadCount: number;
}

export interface MobileNotificationColumnHead {
  readonly id: string;
  readonly title: string;
  readonly textPrefix: string;
  readonly text: string;
  readonly targetLink: string;
  readonly unreadCount: number;
  readonly created: number;
}

export interface MobileNotificationAuthor {
  readonly id: string;
  readonly name: string;
  readonly urlToken: string;
  readonly headline: string;
  readonly avatarUrl: string;
}

export interface MobileNotificationLabel {
  readonly text: string;
}

export interface MobileNotificationContent {
  readonly title: string;
  readonly subTitle: string;
  readonly text: string;
  readonly subText: string;
  readonly abstractText: string;
  readonly targetLink: string;
  readonly subTargetLink: string;
  readonly subIcon: string;
  readonly isDeleted: boolean;
}

export interface MobileNotificationTargetSource {
  readonly text: string;
  readonly subText: string;
  readonly targetLink: string;
  readonly isDeleted: boolean;
}

export interface MobileNotificationTarget {
  readonly id: string;
  readonly type: string;
  readonly name: string;
  readonly title: string;
  readonly urlToken: string;
  readonly avatarUrl: string;
  readonly url: string;
  readonly myAnswerUrl: string;
  readonly hasAnswer: boolean;
}

export interface MobileNotificationHead {
  readonly author?: MobileNotificationAuthor;
  readonly avatarUrl: string;
  readonly targetLink: string;
  readonly labels: Array<MobileNotificationLabel>;
}

export interface MobileNotificationEmptyInfo {
  readonly text: string;
  readonly number: number;
}

export interface MobileNotificationAdditionalInfo {
  readonly id: number;
  readonly text: string;
}

export interface MobileNotificationTimelineItem {
  readonly id: string;
  readonly uniqueId: string;
  readonly type: string;
  readonly cardType: string;
  readonly detailTitle: string;
  readonly isRead: boolean;
  readonly unreadCount: number;
  readonly created: number;
  readonly createdStr: string;
  readonly head?: MobileNotificationHead;
  readonly content?: MobileNotificationContent;
  readonly targetSource?: MobileNotificationTargetSource;
  readonly target?: MobileNotificationTarget;
  readonly emptyInfo?: MobileNotificationEmptyInfo;
  readonly additionalInfo: Array<MobileNotificationAdditionalInfo>;
}

export function mobileTimelineStableId(item: MobileNotificationTimelineItem): string {
  if (item.uniqueId.length > 0) {
    return item.uniqueId;
  }
  if (item.id.length > 0) {
    return item.id;
  }
  return `${item.created}-${item.cardType}-${item.detailTitle}`;
}

/** 展示标题（对齐上游 `displayTitle`：content.title → detailTitle → target.name → 「通知」）。 */
export function mobileNotificationDisplayTitle(item: MobileNotificationTimelineItem): string {
  const contentTitle = item.content?.title ?? '';
  if (contentTitle.trim().length > 0) {
    return contentTitle;
  }
  if (item.detailTitle.trim().length > 0) {
    return item.detailTitle;
  }
  const targetName = item.target?.name ?? '';
  if (targetName.trim().length > 0) {
    return targetName;
  }
  return '通知';
}

/** 展示副标题（对齐上游 `displaySubtitle`：评论了/赞同了/喜欢了 且不以「：」结尾时补冒号）。 */
export function mobileNotificationDisplaySubtitle(item: MobileNotificationTimelineItem): string {
  const subtitle = item.content?.subTitle ?? '';
  if ((!subtitle.endsWith('：') && subtitle.startsWith('评论了')) ||
    subtitle.startsWith('赞同了') || subtitle.startsWith('喜欢了')) {
    return `${subtitle}：`;
  }
  return subtitle;
}

/** 来源摘要（对齐上游 `sourceText`：targetSource.text/subText 按行拼接）。 */
export function mobileNotificationSourceText(item: MobileNotificationTimelineItem): string {
  const parts: Array<string> = [];
  const source = item.targetSource;
  if (source !== undefined) {
    if (source.text.trim().length > 0) {
      parts.push(source.text);
    }
    if (source.subText.trim().length > 0) {
      parts.push(source.subText);
    }
  }
  return parts.join('\n');
}

/** 头像（对齐上游 `avatarUrl`：head.avatarUrl → head.author.avatarUrl → target.avatarUrl → content.subIcon）。 */
export function mobileNotificationAvatarUrl(item: MobileNotificationTimelineItem): string {
  const headAvatar = item.head?.avatarUrl ?? '';
  if (headAvatar.trim().length > 0) {
    return headAvatar;
  }
  const authorAvatar = item.head?.author?.avatarUrl ?? '';
  if (authorAvatar.trim().length > 0) {
    return authorAvatar;
  }
  const targetAvatar = item.target?.avatarUrl ?? '';
  if (targetAvatar.trim().length > 0) {
    return targetAvatar;
  }
  const subIcon = item.content?.subIcon ?? '';
  return subIcon.trim().length > 0 ? subIcon : '';
}

export interface MobileNotificationCategoryUnreadCounts {
  readonly comment: number;
  readonly like: number;
  readonly favorite: number;
  readonly follow: number;
}

export function emptyMobileCategoryUnreadCounts(): MobileNotificationCategoryUnreadCounts {
  return { comment: 0, like: 0, favorite: 0, follow: 0 };
}

export function mobileCategoryUnreadCount(counts: MobileNotificationCategoryUnreadCounts,
  category: MobileNotificationCategory): number {
  if (category === MobileNotificationCategory.LIKE) {
    return counts.like;
  }
  if (category === MobileNotificationCategory.FAVORITE) {
    return counts.favorite;
  }
  if (category === MobileNotificationCategory.FOLLOW) {
    return counts.follow;
  }
  return counts.comment;
}

export function mobileNotificationUnreadTotal(counts: MobileNotificationCategoryUnreadCounts): number {
  return counts.comment + counts.like + counts.favorite + counts.follow;
}

export interface MobileNotificationMessageOverview {
  readonly head: Array<MobileNotificationHeadEntry>;
  readonly columnHead: Array<MobileNotificationColumnHead>;
}

export interface MobileNotificationMessagePage {
  readonly overview: MobileNotificationMessageOverview;
  readonly items: Array<MobileNotificationTimelineItem>;
  readonly cursor: PageCursor;
}

export interface MobileNotificationTimelinePage {
  readonly items: Array<MobileNotificationTimelineItem>;
  readonly cursor: PageCursor;
}

export interface ZhihuPrivateMessage {
  readonly id: string;
  readonly type: string;
  readonly contentType: number;
  readonly content: string;
  readonly createdTime: number;
  /** 卡片消息的摘要（对齐上游 ZhihuPrivateMessagePlugin.excerpt，优先于 content 展示）。 */
  readonly pluginExcerpt: string;
  readonly sender?: MobileNotificationAuthor;
  readonly receiver?: MobileNotificationAuthor;
}

export function privateMessageStableId(message: ZhihuPrivateMessage): string {
  if (message.id.length > 0) {
    return message.id;
  }
  return `${message.createdTime}-${message.sender?.id ?? ''}-${message.receiver?.id ?? ''}`;
}

export interface ZhihuPrivateMessagePage {
  readonly items: Array<ZhihuPrivateMessage>;
  readonly cursor: PageCursor;
}
