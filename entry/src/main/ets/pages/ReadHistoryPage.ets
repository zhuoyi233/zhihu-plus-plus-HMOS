import {
  ReadHistoryGateway
} from 'data';
import {
  ReadHistoryController,
  ReadHistoryItem,
  readHistoryKindLabel,
  readHistoryOpenTarget,
  ReadHistoryOpenTarget,
  ReadHistoryPhase,
  ReadHistoryViewState
} from './ReadHistoryState';

export type OpenReadHistoryItem = (target: ReadHistoryOpenTarget) => void;

@Component
export struct ReadHistoryPage {
  history: ReadHistoryGateway | undefined = undefined;
  onOpen: OpenReadHistoryItem = (_target: ReadHistoryOpenTarget): void => {};
  @State private viewState: ReadHistoryViewState = {
    phase: ReadHistoryPhase.LOADING,
    items: [],
    busy: false,
    message: '正在读取本地已读记录'
  };
  @State private confirmClear: boolean = false;
  private controller?: ReadHistoryController;

  aboutToAppear(): void {
    const history = this.history;
    if (history === undefined) {
      this.viewState = {
        phase: ReadHistoryPhase.ERROR,
        items: [],
        busy: false,
        message: '已读记录数据源未配置'
      };
      return;
    }
    this.controller = new ReadHistoryController(history, (state: ReadHistoryViewState): void => {
      this.viewState = state;
    });
    this.controller.activate();
  }

  aboutToDisappear(): void {
    this.controller?.deactivate();
    this.controller = undefined;
    this.confirmClear = false;
  }

  build() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Text('只保存在本机；不保存正文、Cookie、搜索词或账号信息。')
        .id('p2_read_history_privacy')
        .fontSize($r('app.float.p1_caption_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      Row() {
        Text(this.viewState.message)
          .id('p2_read_history_status')
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor(this.viewState.phase === ReadHistoryPhase.ERROR ?
            $r('app.color.error_text') : $r('app.color.secondary_text'))
          .layoutWeight(1)
        Button('清空')
          .id('p2_read_history_clear')
          .enabled(!this.viewState.busy && this.viewState.items.length > 0)
          .onClick((): void => {
            this.confirmClear = true;
          })
      }
      .width('100%')
      if (this.viewState.phase === ReadHistoryPhase.LOADING && this.viewState.items.length === 0) {
        LoadingProgress()
          .id('p2_read_history_loading')
          .width(40)
          .height(40)
          .color($r('app.color.brand_primary'))
      } else if (this.viewState.items.length === 0) {
        Column({ space: $r('app.float.p1_spacing_medium') }) {
          Text(this.viewState.phase === ReadHistoryPhase.EMPTY ? '暂无本地已读记录' : this.viewState.message)
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .textAlign(TextAlign.Center)
            .width('100%')
          if (this.viewState.phase === ReadHistoryPhase.ERROR) {
            Button('重新读取')
              .id('p2_read_history_retry')
              .enabled(!this.viewState.busy)
              .onClick((): void => {
                this.controller?.reload();
              })
          }
        }
        .justifyContent(FlexAlign.Center)
        .layoutWeight(1)
        .width('100%')
      } else {
        List({ space: $r('app.float.p1_spacing_small') }) {
          ForEach(this.viewState.items, (item: ReadHistoryItem) => {
            ListItem() {
              this.historyRow(item)
            }
          }, (item: ReadHistoryItem): string => item.contentKey)
        }
        .id('p2_read_history_list')
        .layoutWeight(1)
        .width('100%')
      }
      if (this.confirmClear) {
        this.clearConfirmation()
      }
    }
    .id('p2_read_history_page')
    .width('100%')
    .height('100%')
    .padding($r('app.float.p1_page_padding'))
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private historyRow(item: ReadHistoryItem) {
    Row({ space: $r('app.float.p1_spacing_small') }) {
      Column({ space: 2 }) {
        Text(`${readHistoryKindLabel(item.kind)} #${item.id}`)
          .fontSize($r('app.float.p1_body_font_size'))
          .width('100%')
        Text(this.displayTime(item.openedAt))
          .fontSize($r('app.float.p1_caption_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }
      .layoutWeight(1)
      Button('打开')
        .id(`p2_read_history_open_${item.contentKey}`)
        .enabled(!this.viewState.busy)
        .onClick((): void => this.onOpen(readHistoryOpenTarget(item)))
      Button('删除')
        .id(`p2_read_history_delete_${item.contentKey}`)
        .enabled(!this.viewState.busy)
        .onClick((): void => {
          this.controller?.delete(item.contentKey);
        })
    }
    .width('100%')
    .padding($r('app.float.p1_spacing_medium'))
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.p1_card_radius'))
  }

  @Builder
  private clearConfirmation() {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      Text('确认清空全部本地已读记录？此操作无法撤销。')
        .fontSize($r('app.float.p1_body_font_size'))
        .width('100%')
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Button('取消')
          .layoutWeight(1)
          .onClick((): void => {
            this.confirmClear = false;
          })
        Button('确认清空')
          .id('p2_read_history_clear_confirm')
          .layoutWeight(1)
          .enabled(!this.viewState.busy)
          .onClick((): void => {
            this.confirmClear = false;
            this.controller?.clear();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding($r('app.float.p1_spacing_medium'))
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.p1_card_radius'))
  }

  private displayTime(openedAt: number): string {
    try {
      return new Date(openedAt).toISOString().replace('T', ' ').substring(0, 19);
    } catch (_error) {
      return '时间未知';
    }
  }
}
