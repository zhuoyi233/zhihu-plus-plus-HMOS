import { MobileNotificationTimelineItem } from 'data';

/** 同一会话的摘要、日期、未读数变化时重建行；分页去重仍使用数据层稳定 ID。 */
export function notificationItemRenderKey(item: MobileNotificationTimelineItem): string {
  return JSON.stringify(item);
}
