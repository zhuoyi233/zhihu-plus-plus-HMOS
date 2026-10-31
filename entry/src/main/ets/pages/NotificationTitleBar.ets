import { AppDestination, AppDestinationName } from 'core';
import { TopBarActionButton } from './components/TopBarActionButton';
import { TopBarBackMode, TopBarContent } from './components/TopBarContent';

/**
 * 消息中心标题栏内容：左对齐标题「消息」+ 右上角「全部已读／设置」（对齐 main 的
 * CenterAlignedTopAppBar actions，动作按计划 §3.7 排列）。
 *
 * 与 NotificationPage 分属 HdsNavDestination 的 stackBuilder 与内容两棵子树，经 AppStorage 键通信
 * （同 HistoryTitleBar 模式）：已读可见性/忙碌态由页面发布，动作只发 tick。
 * 返回键由 HDS 原生 backIcon 承载；「全部已读」仅在确有未读时出现，忙碌时只禁用该动作，
 * 设置入口保持可点击（不带入 feature 的联动禁用或加载图标）。
 */
export const NOTIFICATION_HUB_UNREAD_TOTAL_KEY = 'notificationHubUnreadTotal';
export const NOTIFICATION_TIMELINE_REFRESH_TICK_KEY = 'notificationTimelineRefreshTick';
export const NOTIFICATION_TIMELINE_ENTRY_KEY = 'notificationTimelineVisibleEntry';
export const NOTIFICATION_HUB_REFRESH_TICK_KEY = 'notificationHubRefreshTick';
export const NOTIFICATION_HUB_BUSY_KEY = 'notificationHubBusy';
export const NOTIFICATION_HUB_MARK_READ_TICK_KEY = 'notificationHubMarkReadTick';

@Component
export struct NotificationTitleBar {
  @StorageProp(NOTIFICATION_HUB_UNREAD_TOTAL_KEY) unreadTotal: number = 0;
  @StorageProp(NOTIFICATION_HUB_BUSY_KEY) busy: boolean = false;
  @Prop backMode: TopBarBackMode = TopBarBackMode.HDS;
  navigate: (destination: AppDestination) => void = (_destination: AppDestination): void => {
  };

  build() {
    TopBarContent({
      backMode: this.backMode,
      title: '消息',
      titleId: 'notifications_title',
      hasTrailingSlot: true,
      trailingSlot: (): void => this.notificationActions()
    })
  }

  @Builder
  private notificationActions() {
    if (this.unreadTotal > 0) {
      TopBarActionButton({
        icon: $r('sys.symbol.checkmark'),
        elementId: 'notifications_mark_all_read',
        label: '全部标记为已读',
        disabled: this.busy,
        onAction: (): void => this.publishMarkRead()
      })
    }
    TopBarActionButton({
      icon: $r('sys.symbol.gearshape'),
      elementId: 'notifications_settings_entry',
      label: '打开通知设置',
      onAction: (): void => {
        this.navigate({ name: AppDestinationName.NOTIFICATION_SETTINGS });
      }
    })
  }

  private publishMarkRead(): void {
    AppStorage.setOrCreate(NOTIFICATION_HUB_MARK_READ_TICK_KEY,
      (AppStorage.get<number>(NOTIFICATION_HUB_MARK_READ_TICK_KEY) ?? 0) + 1);
  }
}
