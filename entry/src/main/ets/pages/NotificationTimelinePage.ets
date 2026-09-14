import { isSafeDecimalContentId, P1Destination, P1DestinationName } from 'core';
import {
  emojiStore,
  LoginSessionGateway,
  MobileNotificationRepository,
  MobileNotificationTimelineItem,
  mobileNotificationAvatarUrl,
  mobileNotificationDisplaySubtitle,
  mobileNotificationDisplayTitle,
  mobileNotificationSourceText,
  NotificationPreferences,
  NotificationSettingsGateway
} from 'data';
import { EmojiText } from './EmojiText';
import { contentLinkDestination, timelineItemDestination } from './NotificationLinkResolver';
import { notificationPlainText } from './PrivateMessageContent';
import { NotificationTimelineController, NotificationTimelinePhase, NotificationTimelineViewState } from './NotificationTimelineState';

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

/**
 * 通知分类/邀请回答时间线页（对齐上游 NotificationTimelineScreen 与
 * NotificationItemView / InvitationAnswerItem 的信息层级）。
 */
@Component
export struct NotificationTimelinePage {
  entryName: string = '';
  repository: MobileNotificationRepository | undefined = undefined;
  settings: NotificationSettingsGateway | undefined = undefined;
  session: LoginSessionGateway | undefined = undefined;
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {};
  @State private phase: NotificationTimelinePhase = NotificationTimelinePhase.IDLE;
  @State private items: Array<MobileNotificationTimelineItem> = [];
  @State private loadingMore: boolean = false;
  @State private canLoadMore: boolean = false;
  @State private requiresLogin: boolean = false;
  @State private errorMessage: string = '';
  @State private preferences?: NotificationPreferences = undefined;
  private controller?: NotificationTimelineController;

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      emojiStore.ensureLoaded(context);
    }
    const repository = this.repository;
    const session = this.session;
    if (repository === undefined || session === undefined) {
      this.phase = NotificationTimelinePhase.ERROR;
      this.errorMessage = '消息数据源未配置';
      return;
    }
    this.controller = new NotificationTimelineController(this.entryName, repository, session,
      (state: NotificationTimelineViewState): void => this.applyState(state));
    this.controller.activate();
    this.loadPreferences();
    this.controller.loadInitial();
  }

  aboutToDisappear(): void {
    this.controller?.deactivate();
    this.controller = undefined;
  }

  build() {
    Column() {
      if (this.phase === NotificationTimelinePhase.IDLE ||
        this.phase === NotificationTimelinePhase.LOADING) {
        this.statusPanel('正在加载消息…', false, 'p3_notification_timeline_loading')
      } else if (this.phase === NotificationTimelinePhase.ERROR) {
        this.statusPanel(this.errorMessage, true, 'p3_notification_timeline_error')
      } else if (this.phase === NotificationTimelinePhase.EMPTY) {
        this.statusPanel('这里还什么都没有', false, 'p3_notification_timeline_empty')
      } else {
        List({ space: 0 }) {
          ForEach(this.items, (item: MobileNotificationTimelineItem) => {
            ListItem() {
              if (item.type === 'empty') {
                this.emptyRow(item)
              } else if (this.entryName === 'invite') {
                this.invitationAnswerItem(item)
              } else {
                this.timelineItemRow(item)
              }
            }
          }, (item: MobileNotificationTimelineItem): string =>
            `p3_notification_timeline_${item.uniqueId.length > 0 ? item.uniqueId : item.id}`)

          if (this.loadingMore) {
            ListItem() {
              Row() {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color($r('app.color.brand_primary'))
                Text('正在加载更多…')
                  .fontSize($r('app.float.p1_secondary_font_size'))
                  .fontColor($r('app.color.secondary_text'))
                  .margin({ left: 8 })
              }
              .id('p3_notification_timeline_load_more')
              .justifyContent(FlexAlign.Center)
              .width('100%')
              .padding(12)
            }
          }
        }
        .id('p3_notification_timeline_list')
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .onReachEnd(() => this.controller?.loadMore())
      }
    }
    .id('p3_notification_timeline_page')
    .width('100%')
    .height('100%')
    .padding({ top: 94 })
    .backgroundColor($r('app.color.page_background'))
  }

  /** 时间线卡片（未读点 + 头像 + 标题/副标题/正文 + 相对时间 + 来源框）。 */
  @Builder
  private timelineItemRow(item: MobileNotificationTimelineItem) {
    Column() {
      Row() {
        Column() {
          if (!item.isRead) {
            Circle()
              .width(6)
              .height(6)
              .fill($r('app.color.error_text'))
          }
        }
        .width(10)
        .padding({ top: 10, right: 4 })

        if (mobileNotificationAvatarUrl(item).length > 0) {
          Image(mobileNotificationAvatarUrl(item))
            .width(44)
            .height(44)
            .borderRadius(22)
            .backgroundColor($r('app.color.surface_background'))
            .objectFit(ImageFit.Cover)
            .margin({ right: 12 })
        }

        Column() {
          Text(mobileNotificationDisplayTitle(item))
            .fontSize($r('app.float.p1_body_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          if (mobileNotificationDisplaySubtitle(item).length > 0) {
            Text(mobileNotificationDisplaySubtitle(item))
              .fontSize($r('app.float.p1_secondary_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 3 })
              .width('100%')
          }

          if (this.contentTextOf(item).length > 0) {
            EmojiText({
              text: this.contentTextOf(item),
              fontSize: 13,
              fontColor: $r('app.color.secondary_text'),
              maxLines: 3
            })
              .margin({ top: 4 })
              .width('100%')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (relativeTime(item.created).length > 0) {
          Text(relativeTime(item.created))
            .fontSize($r('app.float.p1_caption_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .margin({ left: 8 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      if (mobileNotificationSourceText(item).length > 0) {
        Text(mobileNotificationSourceText(item))
          .fontSize($r('app.float.p1_caption_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding(12)
          .borderRadius(8)
          .backgroundColor($r('app.color.surface_background'))
          .margin({ top: 10 })
      }
    }
    .id(`p3_notification_timeline_item_${item.uniqueId.length > 0 ? item.uniqueId : item.id}`)
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(item.isRead ? Color.Transparent : $r('app.color.brand_primary_container'))
    .onClick((): void => {
      const destination = timelineItemDestination(item);
      if (destination === undefined) {
        this.getUIContext().getPromptAction().showToast({ message: '暂不支持打开此通知' });
        return;
      }
      this.navigate(destination);
    })
  }

  /** 邀请回答项（对齐上游 InvitationAnswerItem：作者头部 + 问题卡 + 写/看回答按钮）。 */
  @Builder
  private invitationAnswerItem(item: MobileNotificationTimelineItem) {
    Column() {
      Row() {
        if (mobileNotificationAvatarUrl(item).length > 0) {
          Image(mobileNotificationAvatarUrl(item))
            .width(44)
            .height(44)
            .borderRadius(22)
            .backgroundColor($r('app.color.surface_background'))
            .objectFit(ImageFit.Cover)
        } else {
          Circle()
            .width(44)
            .height(44)
            .fill($r('app.color.brand_primary_container'))
        }

        Column({ space: 3 }) {
          Row() {
            Text(this.invitationAuthorName(item))
              .fontSize($r('app.float.p1_body_font_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.primary_text'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            if ((item.head?.labels.length ?? 0) > 0) {
              Text(item.head?.labels[0].text ?? '')
                .fontSize($r('app.float.p1_caption_font_size'))
                .fontColor($r('app.color.brand_primary'))
                .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                .borderRadius(4)
                .backgroundColor($r('app.color.brand_primary_container'))
                .margin({ left: 6 })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(this.invitationSubtitle(item))
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 10 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ top: 12, bottom: 10 })

      Column() {
        if (this.invitationRewardText(item).length > 0) {
          Text(this.invitationRewardText(item))
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ bottom: 8 })
            .width('100%')
        }

        Text(this.invitationQuestionTitle(item))
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .width('100%')

        Row() {
          Text(item.targetSource?.subText ?? '')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Button() {
            Row({ space: 5 }) {
              SymbolGlyph($r('sys.symbol.square_and_pencil'))
                .fontSize(16)
                .fontColor([Color.White])
              Text((item.target?.hasAnswer ?? false) ? '查看回答' : '写回答')
                .fontSize($r('app.float.p1_secondary_font_size'))
                .fontColor(Color.White)
            }
            .alignItems(VerticalAlign.Center)
          }
            .id(`p3_invitation_answer_${item.uniqueId.length > 0 ? item.uniqueId : item.id}`)
            .height(32)
            .padding({ left: 12, right: 12 })
            .backgroundColor($r('app.color.brand_primary'))
            .onClick((): void => this.openInvitationAnswer(item))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ top: 10 })
      }
      .width('100%')
      .padding(14)
      .borderRadius(14)
      .backgroundColor($r('app.color.surface_background'))
      .onClick((): void => this.openInvitationQuestion(item))
    }
    .id(`p3_invitation_${item.uniqueId.length > 0 ? item.uniqueId : item.id}`)
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 12 })
  }

  @Builder
  private emptyRow(item: MobileNotificationTimelineItem) {
    Text(item.emptyInfo?.text ?? '')
      .fontSize(20)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.primary_text'))
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  @Builder
  private statusPanel(message: string, retry: boolean, testId: string) {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      if (testId === 'p3_notification_timeline_loading') {
        LoadingProgress()
          .id('p3_notification_timeline_loading_progress')
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
            .id('p3_notification_timeline_status_login')
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
    .height('100%')
  }

  private contentTextOf(item: MobileNotificationTimelineItem): string {
    const content = item.content;
    if (content === undefined) {
      return '';
    }
    if (content.subTitle === '喜欢了你的评论') {
      return notificationPlainText(content.subText);
    }
    return notificationPlainText(content.text);
  }

  private invitationAuthorName(item: MobileNotificationTimelineItem): string {
    const contentTitle = item.content?.title ?? '';
    if (contentTitle.trim().length > 0) {
      return contentTitle;
    }
    const authorName = item.head?.author?.name ?? '';
    if (authorName.trim().length > 0) {
      return authorName;
    }
    return item.detailTitle;
  }

  private invitationRewardText(item: MobileNotificationTimelineItem): string {
    if (item.additionalInfo.length === 0) {
      return '';
    }
    return stripHtml(item.additionalInfo[0].text);
  }

  private invitationQuestionTitle(item: MobileNotificationTimelineItem): string {
    const targetTitle = item.target?.title ?? '';
    if (targetTitle.trim().length > 0) {
      return targetTitle;
    }
    return item.targetSource?.text ?? '';
  }

  private invitationSubtitle(item: MobileNotificationTimelineItem): string {
    const subTitle = item.content?.subTitle ?? '';
    const time = this.invitationTime(item.created);
    if (subTitle.length > 0 && time.length > 0) {
      return `${subTitle} · ${time}`;
    }
    return subTitle.length > 0 ? subTitle : time;
  }

  private invitationTime(created: number): string {
    if (created <= 0) {
      return '';
    }
    try {
      const date = new Date(created * 1000);
      const now = new Date();
      const sameDay = date.getFullYear() === now.getFullYear() &&
        date.getMonth() === now.getMonth() && date.getDate() === now.getDate();
      if (sameDay) {
        const hour = date.getHours().toString().padStart(2, '0');
        const minute = date.getMinutes().toString().padStart(2, '0');
        return ` ${hour}:${minute}`;
      }
      const yesterday = new Date(now.getTime() - 24 * 60 * 60 * 1000);
      const isYesterday = date.getFullYear() === yesterday.getFullYear() &&
        date.getMonth() === yesterday.getMonth() && date.getDate() === yesterday.getDate();
      if (isYesterday) {
        return ' 昨天';
      }
      const month = (date.getMonth() + 1).toString().padStart(2, '0');
      const day = date.getDate().toString().padStart(2, '0');
      return ` ${month}-${day}`;
    } catch (_error) {
      return '';
    }
  }

  private openInvitationQuestion(item: MobileNotificationTimelineItem): void {
    const questionId = item.target?.id ?? '';
    if (isSafeDecimalContentId(questionId)) {
      this.navigate({ name: P1DestinationName.QUESTION, id: questionId });
      return;
    }
    this.getUIContext().getPromptAction().showToast({ message: '无法打开这个问题' });
  }

  private openInvitationAnswer(item: MobileNotificationTimelineItem): void {
    const target = item.target;
    if (target === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: '无法回答这个问题' });
      return;
    }
    const myAnswerUrl = target.myAnswerUrl.trim().length > 0 ? target.myAnswerUrl : '';
    if (myAnswerUrl.length > 0) {
      const destination = contentLinkDestination(myAnswerUrl);
      if (destination !== undefined) {
        this.navigate(destination);
        return;
      }
    }
    const questionId = isSafeDecimalContentId(target.id) ? target.id : '';
    if (questionId.length > 0) {
      this.navigate({ name: P1DestinationName.WRITE_ANSWER, questionId: questionId });
      return;
    }
    this.getUIContext().getPromptAction().showToast({ message: '无法回答这个问题' });
  }

  private loadPreferences(): void {
    const settings = this.settings;
    if (settings === undefined) {
      return;
    }
    settings.loadNotificationPreferences().then((preferences: NotificationPreferences): void => {
      this.preferences = preferences;
      this.controller?.setPreferences(preferences);
    }).catch((_error: Error): void => {
      this.preferences = undefined;
    });
  }

  private applyState(state: NotificationTimelineViewState): void {
    this.phase = state.phase;
    this.items = state.items;
    this.loadingMore = state.loadingMore;
    this.canLoadMore = state.canLoadMore;
    this.requiresLogin = state.requiresLogin;
    this.errorMessage = state.errorMessage ?? '';
  }
}
