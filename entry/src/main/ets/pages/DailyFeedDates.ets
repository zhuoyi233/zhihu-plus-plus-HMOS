import { ChannelFeedItem, ChannelFeedItemKind, isDailyFeedDateCursor } from 'data';

export function dailyFeedDateAtIndex(items: Array<ChannelFeedItem>, index: number): string {
  if (items.length === 0 || index < 0) {
    return '';
  }
  // 底部加载指示器不属于内容，继续显示最后一张卡片的日期。
  const item = items[Math.min(index, items.length - 1)];
  return item.kind === ChannelFeedItemKind.DAILY_STORY ? item.story.date : '';
}

export function formatDailyDate(value: string): string {
  if (!isDailyFeedDateCursor(value)) {
    return value;
  }
  return `${value.substring(0, 4)}年${Number(value.substring(4, 6))}月${Number(value.substring(6, 8))}日`;
}

export function dailyDateCursor(date: Date): string {
  const month = `${date.getMonth() + 1}`.padStart(2, '0');
  const day = `${date.getDate()}`.padStart(2, '0');
  return `${date.getFullYear()}${month}${day}`;
}

export function dailyPickerDate(value: string): Date {
  if (!isDailyFeedDateCursor(value)) {
    return new Date();
  }
  return new Date(Number(value.substring(0, 4)), Number(value.substring(4, 6)) - 1,
    Number(value.substring(6, 8)));
}
