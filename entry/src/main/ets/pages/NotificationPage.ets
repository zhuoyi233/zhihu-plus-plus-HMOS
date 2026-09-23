import { P1Destination, P1DestinationName } from 'core';
import {
  onThemeColor,
  DEFAULT_THEME_COLOR,
  emojiStore,
  LoginSessionGateway,
  MobileNotificationCategory,
  MOBILE_NOTIFICATION_CATEGORIES,
  mobileNotificationCategoryInfo,
  MobileNotificationCategoryUnreadCounts,
  MobileNotificationColumnHead,
  MobileNotificationRepository,
  MobileNotificationTimelineItem,
  mobileNotificationAvatarUrl,
  NotificationPreferences,
  NotificationSettingsGateway,
  mobileNotificationDisplayTitle,
  themeColorContainerColor
} from 'data';
import { NotificationController, NotificationPhase, NotificationViewState } from './NotificationState';
import { NOTIFICATION_HUB_BUSY_KEY, NOTIFICATION_HUB_MARK_READ_TICK_KEY,
  NOTIFICATION_HUB_UNREAD_TOTAL_KEY } from './NotificationTitleBar';
import { timelineItemDestination } from './NotificationLinkResolver';
import { FLOATING_TITLE_BAR_OFFSET } from './AppPageChrome';

/** 会话行右侧日期（对齐上游 `notificationListDate`：MM-dd）。 */
function conversationDate(item: MobileNotificationTimelineItem): string {
  if (item.created > 0) {
    try {
      const date = new Date(item.created * 1000);
      const month = (date.getMonth() + 1).toString().padStart(2, '0');
      const day = date.getDate().toString().padStart(2, '0');
      return `${month}-${day}`;
    } catch (_error) {
      return '';
    }
  }
  return item.createdStr;
}

function categorySymbol(category: MobileNotificationCategory): Resource {
  if (category === MobileNotificationCategory.LIKE) {
    return $r('sys.symbol.heart');
  }
  if (category === MobileNotificationCategory.FAVORITE) {
    return $r('sys.symbol.bookmark');
  }
  if (category === MobileNotificationCategory.FOLLOW) {
    return $r('sys.symbol.person_badge_plus');
  }
  return $r('sys.symbol.ellipsis_bubble');
}

function formatUnreadBadge(count: number): string {
  return count > 99 ? '99+' : count.toString();
}

/** 消息中心页（对齐上游 NotificationScreen：四分类宫格 + 邀请回答行 + 会话列表）。 */
@Component
export struct NotificationPage {
  repository: MobileNotificationRepository | undefined = undefined;
  settings: NotificationSettingsGateway | undefined = undefined;
  session: LoginSessionGateway | undefined = undefined;
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {};
  onBack: () => void = (): void => {};
  @State private phase: NotificationPhase = NotificationPhase.IDLE;
  @State private items: Array<MobileNotificationTimelineItem> = [];
  @State private loadingMore: boolean = false;
  @State private canLoadMore: boolean = false;
  @State private requiresLogin: boolean = false;
  @State private busy: boolean = false;
  @State private unreadTotal: number = 0;
  @State private categoryUnread: MobileNotificationCategoryUnreadCounts =
    { comment: 0, like: 0, favorite: 0, follow: 0 };
  @State private invitation?: MobileNotificationColumnHead = undefined;
  @State private errorMessage: string = '';
  @State private preferences?: NotificationPreferences = undefined;
  @StorageProp(NOTIFICATION_HUB_MARK_READ_TICK_KEY) @Watch('onMarkReadTick') markReadTick: number = 0;
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  private controller?: NotificationController;

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      // 懒加载知乎小表情表；加载完成后 EmojiText 经 emojiCatalogVersion 广播自动重建。
      emojiStore.ensureLoaded(context);
    }
    const repository = this.repository;
    const session = this.session;
    if (repository === undefined || session === undefined) {
      this.phase = NotificationPhase.ERROR;
      this.errorMessage = '消息数据源未配置';
      return;
    }
    this.controller = new NotificationController(repository, session,
      (state: NotificationViewState): void => this.applyState(state));
    this.controller.activate();
    this.loadPreferences();
    this.controller.loadInitial();
  }

  aboutToDisappear(): void {
    this.controller?.deactivate();
    this.controller = undefined;
  }

  /** 标题栏「已读」按钮经 AppStorage 广播触发（跨组件通道）。 */
  onMarkReadTick(): void {
    if (this.markReadTick > 0) {
      this.controller?.markAllRead();
    }
  }

  build() {
    Column() {
      if (this.phase === NotificationPhase.IDLE || this.phase === NotificationPhase.LOADING) {
        this.statusPanel('正在加载消息…', false, 'p3_notifications_loading')
      } else if (this.phase === NotificationPhase.ERROR) {
        this.statusPanel(this.errorMessage, true, 'p3_notifications_error')
      } else {
        List({ space: 0 }) {
          ListItem() {
            this.categoryRow()
          }

          if (this.invitation !== undefined) {
            ListItem() {
              Divider()
                .color($r('app.color.surface_background'))
                .strokeWidth(1)
            }

            ListItem() {
              this.invitationRow(this.invitation)
            }
          }

          ListItem() {
            Divider()
              .color($r('app.color.surface_background'))
              .strokeWidth(8)
          }

          ForEach(this.items, (item: MobileNotificationTimelineItem) => {
            ListItem() {
              this.conversationRow(item)
            }
          }, (item: MobileNotificationTimelineItem): string =>
            `p3_notifications_item_${item.uniqueId.length > 0 ? item.uniqueId : item.id}`)

          if (this.loadingMore) {
            ListItem() {
              Row() {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color(this.resolvedThemeColor)
                Text('正在加载更多…')
                  .fontSize($r('app.float.p1_secondary_font_size'))
                  .fontColor($r('app.color.secondary_text'))
                  .margin({ left: 8 })
              }
              .id('p3_notifications_load_more')
              .justifyContent(FlexAlign.Center)
              .width('100%')
              .padding(12)
            }
          }

          if (this.errorMessage.length > 0 && this.phase === NotificationPhase.READY) {
            ListItem() {
              Text(this.errorMessage)
                .fontSize($r('app.float.p1_secondary_font_size'))
                .fontColor($r('app.color.secondary_text'))
                .width('100%')
                .padding(12)
                .textAlign(TextAlign.Center)
            }
          }
        }
        .id('p3_notifications_list')
        .width('100%')
        // 顶栏让位：内缩滚动内容起点，未滚动时首屏内容仍从标题栏下沿开始
        .contentStartOffset(FLOATING_TITLE_BAR_OFFSET)
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .onReachEnd(() => this.controller?.loadMore())

        if (this.phase === NotificationPhase.EMPTY) {
          Column() {
            Text('暂无消息')
              .fontSize($r('app.float.p1_body_font_size'))
              .fontColor($r('app.color.secondary_text'))
          }
          .id('p3_notifications_empty')
          .width('100%')
          .padding(24)
        }
      }
    }
    .id('p3_notifications_page')
    .width('100%')
    .height('100%')
    // 覆盖式顶栏：容器不设 top padding，滚动视口延伸到屏幕顶；
    // 首屏起始位置由列表的 contentStartOffset 内缩（见 AppPageChrome 约定）
    .backgroundColor($r('app.color.page_background'))
  }

  /** 四分类宫格（图标 36 + 未读角标 + 标题，均匀分布，圆角 12 点击区）。 */
  @Builder
  private categoryRow() {
    Row() {
      ForEach(MOBILE_NOTIFICATION_CATEGORIES, (category: MobileNotificationCategory) => {
        Column({ space: 8 }) {
          Stack({ alignContent: Alignment.TopEnd }) {
            SymbolGlyph(categorySymbol(category))
              .fontSize(36)
              .fontColor([$r('app.color.primary_text')])
            if (this.unreadBadgeOf(category) > 0) {
              Text(formatUnreadBadge(this.unreadBadgeOf(category)))
                .fontSize(11)
                .fontColor(Color.White)
                .minFontSize(8)
                .maxFontSize(11)
                .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                .borderRadius(9)
                .backgroundColor($r('app.color.error_text'))
                .margin({ left: 2, bottom: 18 })
            }
          }

          Text(mobileNotificationCategoryInfo(category).detailTitle)
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .id(`p3_notifications_category_${mobileNotificationCategoryInfo(category).entryName}`)
        .alignItems(HorizontalAlign.Center)
        .layoutWeight(1)
        .padding({ top: 4, bottom: 4 })
        .borderRadius(12)
        .onClick((): void => {
          this.navigate({
            name: P1DestinationName.NOTIFICATION_ENTRY,
            entryName: mobileNotificationCategoryInfo(category).entryName,
            title: mobileNotificationCategoryInfo(category).detailTitle
          });
        })
      }, (category: MobileNotificationCategory): string => category)
    }
    .id('p3_notifications_category_bar')
    .width('100%')
    .padding({ left: 8, right: 8, top: 14, bottom: 14 })
  }

  /** 邀请回答行（52 圆形主色图标 + 标题 + 摘要 + 未读角标）。 */
  @Builder
  private invitationRow(invitation: MobileNotificationColumnHead) {
    Row() {
      Stack() {
        Circle()
          .width(52)
          .height(52)
          .fill(this.resolvedThemeColor)
        SymbolGlyph($r('sys.symbol.person_crop_circle_fill_1'))
          .fontSize(28)
          .fontColor([Color.White])
      }

      Column({ space: 3 }) {
        Text(invitation.title.trim().length > 0 ? invitation.title : '邀请回答')
          .fontSize($r('app.float.p1_body_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${invitation.textPrefix}${invitation.text}`)
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 14 })

      if (invitation.unreadCount > 0) {
        Text(formatUnreadBadge(invitation.unreadCount))
          .fontSize(11)
          .fontColor(Color.White)
          .padding({ left: 5, right: 5, top: 1, bottom: 1 })
          .borderRadius(9)
          .backgroundColor($r('app.color.error_text'))
      }
    }
    .id('p3_notifications_invitation')
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .onClick((): void => {
      this.navigate({
        name: P1DestinationName.NOTIFICATION_ENTRY,
        entryName: 'invite',
        title: '邀请回答'
      });
    })
  }

  /** 会话行（52 头像 + 标题/日期 + 内容单行 + 未读角标）。 */
  @Builder
  private conversationRow(item: MobileNotificationTimelineItem) {
    Row() {
      if (mobileNotificationAvatarUrl(item).length > 0) {
        Image(mobileNotificationAvatarUrl(item))
          .width(52)
          .height(52)
          .borderRadius(26)
          .backgroundColor($r('app.color.surface_background'))
          .objectFit(ImageFit.Cover)
      } else {
        Stack() {
          Circle()
            .width(52)
            .height(52)
            .fill(themeColorContainerColor(this.resolvedThemeColor))
          SymbolGlyph($r('sys.symbol.bell'))
            .fontSize(22)
            .fontColor([this.resolvedThemeColor])
        }
      }

      Column({ space: 3 }) {
        Row() {
          Text(mobileNotificationDisplayTitle(item))
            .fontSize($r('app.float.p1_body_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          if (conversationDate(item).length > 0) {
            Text(conversationDate(item))
              .fontSize($r('app.float.p1_caption_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .margin({ left: 8 })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(item.content?.text ?? '')
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 14 })

      if (item.unreadCount > 0) {
        Text(formatUnreadBadge(item.unreadCount))
          .fontSize(11)
          .fontColor(Color.White)
          .padding({ left: 5, right: 5, top: 1, bottom: 1 })
          .borderRadius(9)
          .backgroundColor($r('app.color.error_text'))
          .margin({ left: 8 })
      }
    }
    .id(`p3_notifications_message_${item.uniqueId.length > 0 ? item.uniqueId : item.id}`)
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick((): void => {
      const destination = timelineItemDestination(item);
      if (destination === undefined) {
        this.getUIContext().getPromptAction().showToast({ message: '暂不支持打开此消息' });
        return;
      }
      this.navigate(destination);
    })
  }

  @Builder
  private statusPanel(message: string, retry: boolean, testId: string) {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      if (testId === 'p3_notifications_loading') {
        LoadingProgress()
          .id('p3_notifications_loading_progress')
          .width(40)
          .height(40)
          .color(this.resolvedThemeColor)
      }
      Text(message)
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .textAlign(TextAlign.Center)
        .width('100%')
      if (retry) {
        if (this.requiresLogin) {
          Button('去登录')
            .backgroundColor(this.resolvedThemeColor)
            .fontColor(onThemeColor(this.resolvedThemeColor))
            .id('p3_notifications_status_login')
            .fontSize($r('app.float.p1_body_font_size'))
            .onClick((): void => this.navigate({ name: P1DestinationName.LOGIN }))
        } else {
          Button('重新加载')
            .backgroundColor(this.resolvedThemeColor)
            .fontColor(onThemeColor(this.resolvedThemeColor))
            .id(`${testId}_retry`)
            .fontSize($r('app.float.p1_body_font_size'))
            .onClick(() => this.controller?.retry())
        }
      }
    }
    .id(testId)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .height('100%')
  }

  private unreadBadgeOf(category: MobileNotificationCategory): number {
    if (category === MobileNotificationCategory.LIKE) {
      return this.categoryUnread.like;
    }
    if (category === MobileNotificationCategory.FAVORITE) {
      return this.categoryUnread.favorite;
    }
    if (category === MobileNotificationCategory.FOLLOW) {
      return this.categoryUnread.follow;
    }
    return this.categoryUnread.comment;
  }

  private loadPreferences(): void {
    const settings = this.settings;
    if (settings === undefined) {
      return;
    }
    settings.loadNotificationPreferences().then((preferences: NotificationPreferences): void => {
      this.preferences = preferences;
    }).catch((_error: Error): void => {
      this.preferences = undefined;
    });
  }

  private applyState(state: NotificationViewState): void {
    this.phase = state.phase;
    this.items = state.items;
    this.loadingMore = state.loadingMore;
    this.canLoadMore = state.canLoadMore;
    this.requiresLogin = state.requiresLogin;
    this.busy = state.busy;
    this.unreadTotal = state.unreadTotal;
    this.categoryUnread = state.categoryUnread;
    this.invitation = state.invitation;
    this.errorMessage = state.errorMessage ?? '';
    AppStorage.setOrCreate(NOTIFICATION_HUB_UNREAD_TOTAL_KEY, this.unreadTotal);
    AppStorage.setOrCreate(NOTIFICATION_HUB_BUSY_KEY, this.busy);
  }
}
