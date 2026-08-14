import {
  NotificationCategory,
  NotificationPage,
  NotificationUnreadCounts
} from '../domain/NotificationModels';

export interface NotificationRepository {
  getNotificationsPage(category: NotificationCategory, cursor?: string): Promise<NotificationPage>;
  getUnreadCounts(): Promise<NotificationUnreadCounts>;
  markAllAsRead(): Promise<void>;
  cancel(): void;
}
