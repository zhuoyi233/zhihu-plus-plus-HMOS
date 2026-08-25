import { LoginSessionGateway, SessionStatus } from 'data';
import { PinDraftResumeItem, PinDraftResumeListGateway } from './PinPublishPage';

export type PinDraftOpenCallback = (draftId: string) => void;

enum PinDraftInboxPhase {
  LOADING,
  READY,
  LOGIN_REQUIRED,
  UNAVAILABLE
}

/**
 * 只读取当前已认证账号的想法草稿元数据。正文始终由编辑页按草稿键从加密存储恢复，
 * 因而草稿列表、路由和 UI dump 都不会承载 HTML 或账号凭证。
 */
@Component
export struct PinDraftInboxPage {
  gateway: PinDraftResumeListGateway | undefined = undefined;
  session: LoginSessionGateway | undefined = undefined;
  onOpen: PinDraftOpenCallback = (_draftId: string): void => {};
  onGoLogin: () => void = (): void => {};
  @State private phase: PinDraftInboxPhase = PinDraftInboxPhase.LOADING;
  @State private items: Array<PinDraftResumeItem> = [];
  private generation: number = 0;

  aboutToAppear(): void {
    this.load();
  }

  aboutToDisappear(): void {
    this.generation += 1;
    this.items = [];
  }

  build() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Text('本地想法草稿')
          .id('p4_pin_drafts_title')
          .layoutWeight(1)
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
        if (this.phase === PinDraftInboxPhase.READY) {
          Button('刷新')
            .id('p4_pin_drafts_refresh')
            .onClick((): void => this.load())
        }
      }
      .width('100%')

      Text(this.statusMessage())
        .id('p4_pin_drafts_status')
        .width('100%')
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))

      if (this.phase === PinDraftInboxPhase.LOGIN_REQUIRED) {
        Button('去登录')
          .id('p4_pin_drafts_login')
          .width('100%')
          .onClick((): void => this.onGoLogin())
      } else if (this.phase === PinDraftInboxPhase.UNAVAILABLE) {
        Text('草稿服务暂不可用，请返回后重试。')
          .id('p4_pin_drafts_unavailable')
          .width('100%')
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.secondary_text'))
      } else if (this.phase === PinDraftInboxPhase.LOADING) {
        Text('正在读取本地草稿…')
          .id('p4_pin_drafts_loading')
          .width('100%')
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.secondary_text'))
      } else if (this.items.length === 0) {
        Text('当前账号没有可恢复的想法草稿。')
          .id('p4_pin_drafts_empty')
          .width('100%')
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.secondary_text'))
      } else {
        List({ space: $r('app.float.p1_spacing_small') }) {
          ForEach(this.items, (item: PinDraftResumeItem) => {
            ListItem() {
              Button(item.title)
                .id(`p4_pin_draft_open_${item.draftId}`)
                .width('100%')
                .fontSize($r('app.float.p1_body_font_size'))
                .onClick((): void => this.onOpen(item.draftId))
            }
          }, (item: PinDraftResumeItem): string => item.draftId)
        }
        .id('p4_pin_drafts_list')
        .width('100%')
        .layoutWeight(1)
      }
    }
    .id('p4_pin_drafts_page')
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .padding($r('app.float.p1_page_padding'))
    .backgroundColor($r('app.color.page_background'))
  }

  private load(): void {
    const session = this.session;
    if (session === undefined || session.getState().status !== SessionStatus.AUTHENTICATED) {
      this.phase = PinDraftInboxPhase.LOGIN_REQUIRED;
      this.items = [];
      return;
    }
    const gateway = this.gateway;
    if (gateway === undefined) {
      this.phase = PinDraftInboxPhase.UNAVAILABLE;
      this.items = [];
      return;
    }
    const generation = this.generation + 1;
    this.generation = generation;
    this.phase = PinDraftInboxPhase.LOADING;
    this.items = [];
    gateway.listResumeItems().then((items: Array<PinDraftResumeItem>): void => {
      if (generation !== this.generation) {
        return;
      }
      if (session.getState().status !== SessionStatus.AUTHENTICATED) {
        this.phase = PinDraftInboxPhase.LOGIN_REQUIRED;
        return;
      }
      this.items = items;
      this.phase = PinDraftInboxPhase.READY;
    }, (_error: Error): void => {
      if (generation === this.generation) {
        this.phase = PinDraftInboxPhase.UNAVAILABLE;
      }
    });
  }

  private statusMessage(): string {
    switch (this.phase) {
      case PinDraftInboxPhase.LOGIN_REQUIRED:
        return '登录后可恢复本账号的本地草稿';
      case PinDraftInboxPhase.UNAVAILABLE:
        return '暂时无法读取草稿';
      case PinDraftInboxPhase.READY:
        return '草稿正文仅在打开编辑页后从本机加密存储恢复';
      default:
        return '正在准备草稿箱';
    }
  }
}
