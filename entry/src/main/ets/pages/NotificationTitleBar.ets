import { AppDestination, AppDestinationName } from 'core';
import { TopBarActionButton } from './components/TopBarActionButton';
import { TopBarBackMode, TopBarContent } from './components/TopBarContent';

/**
 * 消息中心 HDS 标题栏注入内容：标题 + 右上角「已读/设置」（对齐上游
 * CenterAlignedTopAppBar 的 actions）。与 NotificationPage 分属
 * HdsNavDestination 的 stackBuilder 与内容两棵子树，经 AppStorage 键通信
 * （同 HistoryTitleBar 模式）：已读可见性/忙碌态由页面发布，动作只发 tick。
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
  @Prop backMode: TopBarBackMode = TopBarBackMode.CUSTOM;
  navigate: (destination: AppDestination) => void = (_destination: AppDestination): void => {
  };
  onBack: () => void = (): void => {
  };

  build() {
    TopBarContent({
      backMode: this.backMode,
      title: '消息',
      titleId: 'notifications_title',
      backId: 'notifications_back',
      onBack: (): void => {
        this.onBack();
      },
      // 设置入口常驻；「全部已读」只在确有未读时出现，不渲染无效按钮。
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
        busy: this.busy,
        onAction: (): void => {
          this.publishMarkRead();
        }
      })
    }
    TopBarActionButton({
      icon: $r('sys.symbol.gearshape'),
      elementId: 'notifications_settings_entry',
      label: '打开通知设置',
      disabled: this.busy,
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
