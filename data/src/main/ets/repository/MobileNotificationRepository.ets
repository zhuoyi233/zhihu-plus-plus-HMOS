import {
  MobileNotificationAuthor,
  MobileNotificationMessagePage,
  MobileNotificationTimelinePage,
  ZhihuPrivateMessage,
  ZhihuPrivateMessagePage
} from '../domain/MobileNotificationModels';

/**
 * 通知仓库（移动端 v3，对齐上游 `NotificationViewModel`/
 * `NotificationTimelineViewModel`/`PrivateMessageViewModel` 的端点与语义）。
 */
export interface MobileNotificationRepository {
  /** 消息中心首屏/分页：GET /notifications/v3/message/v3（含 head 未读数与 columnHead 邀请行）。 */
  getMessagePage(cursor?: string): Promise<MobileNotificationMessagePage>;
  /** 分类/邀请回答时间线：GET /notifications/v3/timeline/entry/{entry}。 */
  getTimelinePage(entryName: string, cursor?: string): Promise<MobileNotificationTimelinePage>;
  /** 单入口全部已读：POST /notifications/v3/timeline/entry/{entry}/actions/readall。 */
  markEntryAsRead(entryName: string): Promise<void>;
  /** 私信会话分页：GET /messages?sender_id={peerId}。 */
  getPrivateMessagePage(peerId: string, cursor?: string): Promise<ZhihuPrivateMessagePage>;
  /** 私信对象信息：GET /messages/user/{peerId}。 */
  getPrivateMessagePeer(peerId: string): Promise<MobileNotificationAuthor>;
  /** 发送私信：POST /messages（加密表单体）。返回服务端回执消息。 */
  sendPrivateMessage(peerId: string, content: string): Promise<ZhihuPrivateMessage>;
  cancel(): void;
}
