import { P1Destination, P1DestinationName } from 'core';

/**
 * 消息中心 HDS 标题栏注入内容：标题 + 右上角「已读/设置」（对齐上游
 * CenterAlignedTopAppBar 的 actions）。与 NotificationPage 分属
 * HdsNavDestination 的 stackBuilder 与内容两棵子树，经 AppStorage 键通信
 * （同 HistoryTitleBar 模式）：已读可见性/忙碌态由页面发布，动作只发 tick。
 */
export const NOTIFICATION_HUB_UNREAD_TOTAL_KEY = 'notificationHubUnreadTotal';
export const NOTIFICATION_HUB_BUSY_KEY = 'notificationHubBusy';
export const NOTIFICATION_HUB_MARK_READ_TICK_KEY = 'notificationHubMarkReadTick';

@Component
export struct NotificationTitleBar {
  @StorageProp(NOTIFICATION_HUB_UNREAD_TOTAL_KEY) unreadTotal: number = 0;
  @StorageProp(NOTIFICATION_HUB_BUSY_KEY) busy: boolean = false;
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {};

  build() {
    Row({ space: 8 }) {
      // 返回键由 HDS 标题栏默认 backIcon 承载（P1Shell 传入 action），这里从其右侧起排。
      Text('消息')
        .id('p3_notifications_title')
        .fontSize($r('app.float.p1_heading_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      if (this.unreadTotal > 0) {
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
          .id('p3_notifications_mark_all_read')
          .width(40)
          .height(40)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText('全部标记为已读')
          .enabled(!this.busy)
          .onClick((): void => this.publishMarkRead())
      }

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.gearshape'))
          .fontSize(20)
          .fontColor([$r('app.color.primary_text')])
      }
        .id('p3_notifications_settings_entry')
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText('打开通知设置')
        .onClick((): void => {
          this.navigate({ name: P1DestinationName.NOTIFICATION_SETTINGS });
        })
    }
    .width('100%')
    .height(48)
    // 左侧 64vp 让出 HDS 默认返回键的区域（同 HistoryTitleBar）。
    .padding({ left: 64, right: 8 })
    .alignItems(VerticalAlign.Center)
  }

  private publishMarkRead(): void {
    AppStorage.setOrCreate(NOTIFICATION_HUB_MARK_READ_TICK_KEY,
      (AppStorage.get<number>(NOTIFICATION_HUB_MARK_READ_TICK_KEY) ?? 0) + 1);
  }
}
