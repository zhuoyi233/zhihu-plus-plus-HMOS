import { FeedItem, PageCursor } from './DomainModels';

export enum ChannelFeedSource {
  FOLLOWING = 'following',
  HOT = 'hot',
  DAILY = 'daily'
}

export enum ChannelFeedItemKind {
  CONTENT = 'content',
  DAILY_STORY = 'daily_story'
}

export interface ChannelContentItem {
  readonly kind: ChannelFeedItemKind.CONTENT;
  readonly feedItem: FeedItem;
  readonly topicIds: Array<string>;
}

export interface DailyStorySummary {
  readonly id: string;
  readonly title: string;
  readonly hint: string;
  readonly url: string;
  readonly imageUrl?: string;
  readonly storyType: number;
  readonly date: string;
}

export interface ChannelDailyStoryItem {
  readonly kind: ChannelFeedItemKind.DAILY_STORY;
  readonly story: DailyStorySummary;
}

export type ChannelFeedItem = ChannelContentItem | ChannelDailyStoryItem;

export interface ChannelFeedPage {
  readonly items: Array<ChannelFeedItem>;
  readonly cursor: PageCursor;
}

export function isDailyFeedDateCursor(value: string): boolean {
  if (!/^\d{8}$/.test(value)) {
    return false;
  }
  const year = Number(value.substring(0, 4));
  const month = Number(value.substring(4, 6));
  const day = Number(value.substring(6, 8));
  if (year < 2000 || year > 2099 || month < 1 || month > 12 || day < 1) {
    return false;
  }
  const monthDays: Array<number> = [31, year % 4 === 0 ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return day <= monthDays[month - 1];
}

export function channelFeedItemIdentity(item: ChannelFeedItem): string {
  if (item.kind === ChannelFeedItemKind.CONTENT) {
    return `content:${item.feedItem.target.kind}:${item.feedItem.target.id}`;
  }
  return `daily:${item.story.id}`;
}
