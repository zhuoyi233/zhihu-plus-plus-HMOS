import { P1Destination, P1DestinationName } from 'core';
import {
  LoginSessionGateway,
  MobileNotificationRepository,
  ZhihuPrivateMessage,
  privateMessageStableId
} from 'data';
import { PrivateMessageController, PrivateMessagePhase, PrivateMessageViewState } from './PrivateMessageState';
import { parsePrivateMessageSegments, PrivateMessageSegment, privateMessageDisplaySource } from './PrivateMessageContent';
import { contentLinkDestination } from './NotificationLinkResolver';

function relativeTime(createdTime: number): string {
  if (createdTime <= 0) {
    return '';
  }
  const deltaSeconds = Math.floor((Date.now() - createdTime * 1000) / 1000);
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
    return new Date(createdTime * 1000).toISOString().replace('T', ' ').substring(0, 10);
  } catch (_error) {
    return '';
  }
}

/** 私信会话页（对齐上游 PrivateMessageScreen：气泡列表 + 底部输入栏）。 */
@Component
export struct PrivateMessagePage {
  peerId: string = '';
  peerName: string = '';
  avatarUrl: string = '';
  repository: MobileNotificationRepository | undefined = undefined;
  session: LoginSessionGateway | undefined = undefined;
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {};
  @State private phase: PrivateMessagePhase = PrivateMessagePhase.IDLE;
  @State private items: Array<ZhihuPrivateMessage> = [];
  @State private sending: boolean = false;
  @State private loadingMore: boolean = false;
  @State private canLoadMore: boolean = false;
  @State private requiresLogin: boolean = false;
  @State private errorMessage: string = '';
  @State private sendError: string = '';
  @State private draft: string = '';
  @State private peerDisplayName: string = '';
  private controller?: PrivateMessageController;
  private scroller: Scroller = new Scroller();
  private lastStableId: string = '';
  /** 初始定位到最新消息前不响应顶部触发的翻页，避免前插改变目标下标。 */
  private initialScrollSettled: boolean = false;

  aboutToAppear(): void {
    this.peerDisplayName = this.peerName;
    const repository = this.repository;
    const session = this.session;
    if (repository === undefined || session === undefined) {
      this.phase = PrivateMessagePhase.ERROR;
      this.errorMessage = '私信数据源未配置';
      return;
    }
    this.controller = new PrivateMessageController(this.peerId, repository, session,
      (state: PrivateMessageViewState): void => this.applyState(state));
    this.controller.activate();
    this.controller.loadInitial();
  }

  aboutToDisappear(): void {
    this.controller?.deactivate();
    this.controller = undefined;
  }

  build() {
    Column() {
      if (this.phase === PrivateMessagePhase.IDLE || this.phase === PrivateMessagePhase.LOADING) {
        this.statusPanel('正在加载私信…', false, 'p3_private_message_loading')
      } else if (this.phase === PrivateMessagePhase.ERROR) {
        this.statusPanel(this.errorMessage, true, 'p3_private_message_error')
      } else if (this.phase === PrivateMessagePhase.EMPTY && this.items.length === 0) {
        this.statusPanel('还没有私信', false, 'p3_private_message_empty')
      } else {
        List({ space: 0, scroller: this.scroller }) {
          ForEach(this.items, (message: ZhihuPrivateMessage) => {
            ListItem() {
              this.messageBubble(message)
            }
          }, (message: ZhihuPrivateMessage): string => `p3_private_message_${privateMessageStableId(message)}`)

          if (this.loadingMore) {
            ListItem() {
              Row() {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color($r('app.color.brand_primary'))
                Text('正在加载更早的消息…')
                  .fontSize($r('app.float.p1_secondary_font_size'))
                  .fontColor($r('app.color.secondary_text'))
                  .margin({ left: 8 })
              }
              .id('p3_private_message_load_more')
              .justifyContent(FlexAlign.Center)
              .width('100%')
              .padding(12)
            }
          }

          if (this.sendError.length > 0) {
            ListItem() {
              Text(this.sendError)
                .fontSize($r('app.float.p1_caption_font_size'))
                .fontColor($r('app.color.error_text'))
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding(6)
            }
          }
        }
        .id('p3_private_message_list')
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .padding({ top: 12, bottom: 12 })
        .onReachStart(() => {
          if (this.initialScrollSettled) {
            this.controller?.loadMore();
          }
        })

        Divider()
          .color($r('app.color.surface_background'))
          .strokeWidth(1)

        Row() {
          TextInput({
            text: this.draft,
            placeholder: '发私信'
          })
            .enabled(!this.sending)
            .id('p3_private_message_input')
            .fontSize($r('app.float.p1_body_font_size'))
            .layoutWeight(1)
            .maxLines(4)
            .borderRadius(12)
            .onChange((value: string): void => {
              this.draft = value;
            })
            .onSubmit((): void => this.sendDraft())

          Button({ type: ButtonType.Normal, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.paperplane_fill'))
              .fontSize(20)
              .fontColor([Color.White])
          }
            .id('p3_private_message_send')
            .width(40)
            .height(40)
            .margin({ left: 8 })
            .borderRadius(20)
            .padding(0)
            .backgroundColor(this.draft.trim().length > 0 && !this.sending
              ? $r('app.color.brand_primary') : $r('app.color.surface_background'))
            .enabled(this.draft.trim().length > 0 && !this.sending)
            .onClick((): void => this.sendDraft())
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .alignItems(VerticalAlign.Center)
      }
    }
    .id('p3_private_message_page')
    .width('100%')
    .height('100%')
    .padding({ top: 94 })
    .backgroundColor($r('app.color.page_background'))
    .alignItems(HorizontalAlign.Start)
  }

  /** 气泡行（对齐上游 PrivateMessageBubble：收件左对齐带头像，发件右对齐主色气泡）。 */
  @Builder
  private messageBubble(message: ZhihuPrivateMessage) {
    Row() {
      if (this.isIncoming(message)) {
        Image(message.sender?.avatarUrl ?? '')
          .width(34)
          .height(34)
          .borderRadius(17)
          .backgroundColor($r('app.color.surface_background'))
          .objectFit(ImageFit.Cover)
          .margin({ right: 8 })
      }

      Column({ space: 2 }) {
        Text() {
          ForEach(parsePrivateMessageSegments(privateMessageDisplaySource(message)),
            (segment: PrivateMessageSegment) => {
              Span(segment.text)
                .fontColor(segment.url ? $r('app.color.brand_primary') : $r('app.color.primary_text'))
                .onClick((): void => this.openSegmentLink(segment))
            }, (segment: PrivateMessageSegment): string => `${segment.url}:${segment.text}`)
        }
          .fontSize($r('app.float.p1_body_font_size'))
          .width(this.isIncoming(message) ? '100%' : '88%')
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .borderRadius({
            topLeft: 16,
            topRight: 16,
            bottomLeft: this.isIncoming(message) ? 4 : 16,
            bottomRight: this.isIncoming(message) ? 16 : 4
          })
          .backgroundColor(this.isIncoming(message)
            ? $r('app.color.surface_background') : $r('app.color.brand_primary_container'))

        if (relativeTime(message.createdTime).length > 0) {
          Text(relativeTime(message.createdTime))
            .fontSize($r('app.float.p1_caption_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .padding({ left: 4, right: 4, top: 2, bottom: 2 })
        }
      }
      .alignItems(this.isIncoming(message) ? HorizontalAlign.Start : HorizontalAlign.End)
      .layoutWeight(1)
    }
    .id(`p3_private_message_row_${privateMessageStableId(message)}`)
    .width('100%')
    .padding({ left: 14, right: 14, top: 5, bottom: 5 })
    .alignItems(VerticalAlign.Bottom)
  }

  @Builder
  private statusPanel(message: string, retry: boolean, testId: string) {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      if (testId === 'p3_private_message_loading') {
        LoadingProgress()
          .id('p3_private_message_loading_progress')
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
            .id('p3_private_message_status_login')
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

  private isIncoming(message: ZhihuPrivateMessage): boolean {
    const sender = message.sender;
    if (sender === undefined) {
      return false;
    }
    return sender.id === this.peerId || sender.urlToken === this.peerId;
  }

  private openSegmentLink(segment: PrivateMessageSegment): void {
    if (segment.url.length === 0) {
      return;
    }
    const destination = contentLinkDestination(segment.url);
    if (destination === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: '暂不支持打开此链接' });
      return;
    }
    this.navigate(destination);
  }

  private sendDraft(): void {
    const content = this.draft.trim();
    if (content.length === 0 || this.sending) {
      return;
    }
    const controller = this.controller;
    if (controller === undefined) {
      return;
    }
    controller.send(content).then((sent: boolean): void => {
      if (sent) {
        this.draft = '';
      }
    }).catch((_error: Error): void => {
    });
  }

  private applyState(state: PrivateMessageViewState): void {
    const previous = this.items;
    this.phase = state.phase;
    this.items = state.items;
    this.sending = state.sending;
    this.loadingMore = state.loadingMore;
    this.canLoadMore = state.canLoadMore;
    this.requiresLogin = state.requiresLogin;
    this.errorMessage = state.errorMessage ?? '';
    this.sendError = state.sendError ?? '';
    if (state.peer !== undefined && state.peer.name.trim().length > 0) {
      this.peerDisplayName = state.peer.name;
    }
    // 顶部前插旧消息后，把滚动锚定到原首条，避免视口跳动。
    if (previous.length > 0 && this.items.length > previous.length) {
      const previousFirstId = privateMessageStableId(previous[0]);
      let anchorIndex = -1;
      for (let index = 0; index < this.items.length; index += 1) {
        if (privateMessageStableId(this.items[index]) === previousFirstId) {
          anchorIndex = index;
          break;
        }
      }
      if (anchorIndex > 0) {
        setTimeout((): void => {
          this.scroller.scrollToIndex(anchorIndex, false);
        }, 50);
        return;
      }
    }

    // 新消息到达时滚到底部（列表按时间正序，底部为最新）。
    if (this.items.length > 0) {
      const lastId = privateMessageStableId(this.items[this.items.length - 1]);
      if (lastId !== this.lastStableId) {
        this.lastStableId = lastId;
        const count = this.items.length;
        if (previous.length === 0 || count !== previous.length) {
          setTimeout((): void => {
            this.scroller.scrollToIndex(count - 1, false);
            this.initialScrollSettled = true;
          }, 50);
        }
      }
    }
  }
}
