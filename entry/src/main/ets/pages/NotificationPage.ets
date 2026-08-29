import { P1Destination, P1DestinationName } from 'core';
import {
  LoginSessionGateway,
  matchNotificationKind,
  NotificationCategory,
  NotificationItem,
  NotificationPreferences,
  NotificationSettingsGateway,
  NotificationRepository,
  notificationCategoryInfo,
  notificationDisplayInApp,
  NotificationTargetKind,
  NotificationUnreadCounts
} from 'data';
import {
  NotificationController,
  NotificationPhase,
  NOTIFICATION_CATEGORY_ORDER,
  NotificationViewState
} from './NotificationState';

function relativeTime(created: number): string {
  if (created <= 0) {
    return '';
  }
  const deltaSeconds = Math.floor((Date.now() - created * 1000) / 1000);
  if (deltaSeconds < 60) {
    return '刚刚';
  }
  const minutes = Math.floor(deltaSeconds / 60);
  if (minutes < 60) {
    return `${minutes} 分钟前`;
  }
  const hours = Math.floor(minutes / 60);
  if (hours < 24) {
    return `${hours} 小时前`;
  }
  const days = Math.floor(hours / 24);
  if (days < 7) {
    return `${days} 天前`;
  }
  try {
    return new Date(created * 1000).toISOString().replace('T', ' ').substring(0, 10);
  } catch (_error) {
    return '';
  }
}

function stripHtml(source: string): string {
  if (source.length === 0) {
    return '';
  }
  return source.replace(/<[^>]*>/g, '').replace(/&nbsp;/g, ' ').trim();
}

function displayTitle(item: NotificationItem): string {
  const verb = item.verb.trim();
  if (verb.length > 0) {
    return verb;
  }
  if (item.target !== undefined && item.target.title.trim().length > 0) {
    return item.target.title;
  }
  const actorNames = item.actors.map((actor): string => actor.name).filter((name: string): boolean => name.length > 0);
  if (actorNames.length > 0) {
    return `${actorNames.join('、')} 与你互动`;
  }
  return '新通知';
}

function shouldShowByPreferences(item: NotificationItem, preferences: NotificationPreferences | undefined): boolean {
  if (preferences === undefined) {
    return true;
  }
  const verb = item.verb.trim();
  if (verb.length === 0) {
    return true;
  }
  const kind = matchNotificationKind(verb);
  if (kind === undefined) {
    return true;
  }
  return notificationDisplayInApp(preferences, kind);
}

export function notificationOpenTarget(item: NotificationItem): P1Destination | undefined {
  const target = item.target;
  if (target === undefined || target.id.trim().length === 0) {
    return undefined;
  }
  if (target.kind === NotificationTargetKind.QUESTION) {
    return { name: P1DestinationName.QUESTION, id: target.id };
  }
  if (target.kind === NotificationTargetKind.ANSWER) {
    return { name: P1DestinationName.ANSWER, id: target.id };
  }
  if (target.kind === NotificationTargetKind.ARTICLE) {
    return { name: P1DestinationName.ARTICLE, id: target.id };
  }
  if (target.kind === NotificationTargetKind.PIN) {
    return { name: P1DestinationName.PIN, id: target.id };
  }
  if (target.kind === NotificationTargetKind.PEOPLE) {
    const id = target.id;
    const safeIdentifier = /^[A-Za-z0-9_-]{1,200}$/.test(id) ? id : undefined;
    if (safeIdentifier === undefined) {
      return undefined;
    }
    return { name: P1DestinationName.PEOPLE, id: safeIdentifier };
  }
  return undefined;
}

@Component
export struct NotificationPage {
  repository: NotificationRepository | undefined = undefined;
  settings: NotificationSettingsGateway | undefined = undefined;
  session: LoginSessionGateway | undefined = undefined;
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {};
  onBack: () => void = (): void => {};
  @State private phase: NotificationPhase = NotificationPhase.IDLE;
  @State private selectedCategory: NotificationCategory = NotificationCategory.DEFAULT;
  @State private items: Array<NotificationItem> = [];
  @State private loadingMore: boolean = false;
  @State private canLoadMore: boolean = false;
  @State private requiresLogin: boolean = false;
  @State private busy: boolean = false;
  @State private unreadTotal: number = 0;
  @State private categoryUnread: NotificationUnreadCounts = {
    defaultCount: 0,
    followCount: 0,
    voteThankCount: 0
  };
  @State private errorMessage: string = '';
  @State private preferences?: NotificationPreferences = undefined;
  private controller?: NotificationController;

  aboutToAppear(): void {
    const repository = this.repository;
    const session = this.session;
    if (repository === undefined || session === undefined) {
      this.phase = NotificationPhase.ERROR;
      this.errorMessage = '通知数据源未配置';
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

  build() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
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
            .onClick(() => this.controller?.markAllRead())
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

      this.categoryBar()

      if (this.phase === NotificationPhase.IDLE || this.phase === NotificationPhase.LOADING) {
        this.statusPanel('正在加载通知…', false, 'p3_notifications_loading')
      } else if (this.phase === NotificationPhase.ERROR) {
        this.statusPanel(this.errorMessage, true, 'p3_notifications_error')
      } else if (this.phase === NotificationPhase.EMPTY) {
        this.statusPanel('暂无通知', false, 'p3_notifications_empty')
      } else {
        if (this.errorMessage.length > 0) {
          Row({ space: $r('app.float.p1_spacing_small') }) {
            Text(this.errorMessage)
              .fontSize($r('app.float.p1_secondary_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .layoutWeight(1)
            if (this.requiresLogin) {
              Button('去登录')
                .id('p3_notifications_login')
                .onClick((): void => this.navigate({ name: P1DestinationName.LOGIN }))
            } else {
              Button('重试')
                .id('p3_notifications_retry_more')
                .onClick(() => this.controller?.retry())
            }
          }
          .width('100%')
          .padding($r('app.float.p1_spacing_small'))
          .borderRadius($r('app.float.p1_card_radius'))
          .backgroundColor($r('app.color.surface_background'))
        }

        List({ space: 10 }) {
          ForEach(this.visibleItems(), (item: NotificationItem) => {
            ListItem() {
              this.notificationCard(item)
            }
          }, (item: NotificationItem): string => `${item.category}:${item.id}`)

          if (this.loadingMore || this.canLoadMore) {
            ListItem() {
              Button(this.loadingMore ? '正在加载更多…' : '加载更多')
                .id('p3_notifications_load_more')
                .width('100%')
                .fontSize($r('app.float.p1_secondary_font_size'))
                .enabled(!this.loadingMore && !this.busy)
                .onClick(() => this.controller?.loadMore())
            }
          }
        }
        .id('p3_notifications_list')
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .onReachEnd(() => this.controller?.loadMore())
      }
    }
    .id('p3_notifications_page')
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .padding({
      left: $r('app.float.p1_page_padding'),
      right: $r('app.float.p1_page_padding'),
      top: 94,
      bottom: $r('app.float.p1_page_padding')
    })
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private categoryBar() {
    Scroll() {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        ForEach(NOTIFICATION_CATEGORY_ORDER, (category: NotificationCategory) => {
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row({ space: 4 }) {
              Text(notificationCategoryInfo(category).detailTitle)
                .fontSize($r('app.float.p1_body_font_size'))
                .fontColor(this.selectedCategory === category ?
                  $r('app.color.brand_primary') : $r('app.color.primary_text'))
                .fontWeight(this.selectedCategory === category ? FontWeight.Medium : FontWeight.Normal)
              if (this.categoryBadge(category).length > 0) {
                Text(this.categoryBadge(category))
                  .fontSize($r('app.float.p1_caption_font_size'))
                  .fontColor($r('app.color.error_text'))
              }
            }
          }
          .id(`p3_notifications_category_${category}`)
          .height(44)
          .padding({ left: $r('app.float.p1_spacing_medium'), right: $r('app.float.p1_spacing_medium') })
          .backgroundColor(Color.Transparent)
          .border({
            width: { bottom: this.selectedCategory === category ? 2 : 0 },
            color: $r('app.color.brand_primary')
          })
          .onClick((): void => {
            this.controller?.selectCategory(category);
          })
        }, (category: NotificationCategory): string => category)
      }
      .padding({ left: $r('app.float.p1_spacing_small'), right: $r('app.float.p1_spacing_small') })
    }
    .id('p3_notifications_category_bar')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(44)
  }

  @Builder
  private notificationCard(item: NotificationItem) {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Row()
          .width(8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(item.isRead ? $r('app.color.page_background') : $r('app.color.brand_primary'))
        Text(notificationCategoryInfo(item.category).detailTitle)
          .id(`p3_notifications_item_category_${item.id}`)
          .fontSize($r('app.float.p1_caption_font_size'))
          .fontColor($r('app.color.brand_primary'))
        Text(relativeTime(item.createTime))
          .fontSize($r('app.float.p1_caption_font_size'))
          .fontColor($r('app.color.secondary_text'))
        Blank()
          .layoutWeight(1)
        if (item.mergeCount > 1) {
          Text(`${item.mergeCount} 条`)
            .fontSize($r('app.float.p1_caption_font_size'))
            .fontColor($r('app.color.secondary_text'))
        }
      }
      .width('100%')

      Text(this.cardTitle(item))
        .id(`p3_notifications_item_title_${item.id}`)
        .fontSize($r('app.float.p1_body_font_size'))
        .fontWeight(item.isRead ? FontWeight.Normal : FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .width('100%')

      if (this.cardBody(item).length > 0) {
        Text(this.cardBody(item))
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .id(`p3_notifications_item_${item.id}`)
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
    .borderRadius($r('app.float.p1_card_radius'))
    .backgroundColor(item.isRead ? $r('app.color.card_background') : $r('app.color.surface_background'))
    .onClick((): void => {
      this.controller?.markItemRead(item.id);
      const destination = notificationOpenTarget(item);
      if (destination !== undefined) {
        this.navigate(destination);
      }
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
          .color($r('app.color.brand_primary'))
      }
      Text(message)
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .textAlign(TextAlign.Center)
        .width('100%')
      if (retry) {
        if (this.requiresLogin) {
          Button('去登录')
            .id('p3_notifications_status_login')
            .fontSize($r('app.float.p1_body_font_size'))
            .onClick((): void => this.navigate({ name: P1DestinationName.LOGIN }))
        } else {
          Button('重新加载')
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
    .layoutWeight(1)
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

  private visibleItems(): Array<NotificationItem> {
    if (this.preferences === undefined) {
      return this.items;
    }
    return this.items.filter((item: NotificationItem): boolean =>
      shouldShowByPreferences(item, this.preferences));
  }

  private categoryBadge(category: NotificationCategory): string {
    let count = 0;
    if (category === NotificationCategory.DEFAULT) {
      count = this.categoryUnread.defaultCount;
    } else if (category === NotificationCategory.FOLLOW) {
      count = this.categoryUnread.followCount;
    } else {
      count = this.categoryUnread.voteThankCount;
    }
    return count > 0 ? (count > 99 ? '99+' : count.toString()) : '';
  }

  private cardTitle(item: NotificationItem): string {
    return displayTitle(item);
  }

  private cardBody(item: NotificationItem): string {
    const parts: Array<string> = [];
    if (item.contentText.trim().length > 0) {
      parts.push(stripHtml(item.contentText));
    }
    if (item.extendText.trim().length > 0) {
      parts.push(stripHtml(item.extendText));
    }
    if (item.target !== undefined && item.target.title.trim().length > 0 &&
      item.verb.trim().length > 0) {
      const targetTitle = stripHtml(item.target.title);
      if (targetTitle.length > 0 && targetTitle !== stripHtml(item.contentText)) {
        parts.push(`「${targetTitle}」`);
      }
    }
    return parts.join(' ');
  }

  private applyState(state: NotificationViewState): void {
    this.phase = state.phase;
    this.selectedCategory = state.selectedCategory;
    this.items = state.items;
    this.loadingMore = state.loadingMore;
    this.canLoadMore = state.canLoadMore;
    this.requiresLogin = state.requiresLogin;
    this.busy = state.busy;
    this.unreadTotal = state.unreadTotal;
    this.categoryUnread = state.categoryUnread;
    this.errorMessage = state.errorMessage ?? '';
  }
}
