import {
  BlockedFeedHistoryGateway,
  BlockedFeedRecord
} from 'data';
import {
  BlockedFeedHistoryController,
  BlockedFeedHistoryPhase,
  BlockedFeedHistoryViewState,
  blockedFeedHistoryItemLabel
} from './BlockedFeedHistoryState';

@Component
export struct BlockedFeedHistoryPage {
  history: BlockedFeedHistoryGateway | undefined = undefined;
  onBack: () => void = (): void => {};
  @State private viewState: BlockedFeedHistoryViewState = {
    phase: BlockedFeedHistoryPhase.LOADING,
    records: [],
    busy: false,
    message: '正在读取屏蔽记录'
  };
  @State private confirmClear: boolean = false;
  @State private historyActionsSheetShown: boolean = false;
  private controller?: BlockedFeedHistoryController;

  aboutToAppear(): void {
    // P3-7：返回栈重显（页面实例与状态保留）时 aboutToAppear 可能再次触发；
    // 控制器仍存活时直接复用，避免重建控制器并重载记录导致滚动位置丢失。
    if (this.controller !== undefined) {
      this.controller.activate();
      return;
    }
    const history = this.history;
    if (history === undefined) {
      this.viewState = {
        phase: BlockedFeedHistoryPhase.ERROR,
        records: [],
        busy: false,
        message: '屏蔽记录数据源未配置'
      };
      return;
    }
    this.controller = new BlockedFeedHistoryController(history, (state: BlockedFeedHistoryViewState): void => {
      this.viewState = state;
    });
    this.controller.activate();
  }

  aboutToDisappear(): void {
    this.controller?.deactivate();
    this.controller = undefined;
    this.confirmClear = false;
    this.historyActionsSheetShown = false;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: $r('app.float.p1_spacing_medium') }) {
        Text('只保存在本机；记录你屏蔽过的作者、关键词和话题，不保存正文或账号信息。')
          .id('p3_blocked_feed_history_privacy')
          .fontSize($r('app.float.p1_caption_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
        Text(this.viewState.message)
          .id('p3_blocked_feed_history_status')
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor(this.viewState.phase === BlockedFeedHistoryPhase.ERROR ?
            $r('app.color.error_text') : $r('app.color.secondary_text'))
          .width('100%')
        if (this.viewState.phase === BlockedFeedHistoryPhase.LOADING && this.viewState.records.length === 0) {
          LoadingProgress()
            .id('p3_blocked_feed_history_loading')
            .width(40)
            .height(40)
            .color($r('app.color.brand_primary'))
        } else if (this.viewState.records.length === 0) {
          Column({ space: $r('app.float.p1_spacing_medium') }) {
            Text(this.viewState.phase === BlockedFeedHistoryPhase.EMPTY ? '暂无屏蔽记录' : this.viewState.message)
              .fontSize($r('app.float.p1_body_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .textAlign(TextAlign.Center)
              .width('100%')
            if (this.viewState.phase === BlockedFeedHistoryPhase.ERROR) {
              Button('重新读取')
                .id('p3_blocked_feed_history_retry')
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
          List({ space: 10 }) {
            ForEach(this.viewState.records, (record: BlockedFeedRecord) => {
              ListItem() {
                this.historyRow(record)
              }
            }, (record: BlockedFeedRecord): string => `${record.id}`)
          }
          .id('p3_blocked_feed_history_list')
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: $r('app.float.p1_page_padding'), right: $r('app.float.p1_page_padding'),
        top: 94, bottom: $r('app.float.p1_page_padding') })
      .backgroundColor($r('app.color.page_background'))

      Column()
        .bindSheet(this.historyActionsSheetShown, this.historyActionsSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false,
          maskColor: '#66000000',
          backgroundColor: $r('app.color.surface_background'),
          onDisappear: (): void => {
            if (this.historyActionsSheetShown) {
              this.historyActionsSheetShown = false;
            }
          }
        })
      Column()
        .bindSheet(this.confirmClear, this.clearConfirmation(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false,
          maskColor: '#66000000',
          backgroundColor: $r('app.color.surface_background'),
          onDisappear: (): void => {
            if (this.confirmClear) {
              this.confirmClear = false;
            }
          }
        })
    }
    .id('p3_blocked_feed_history_page')
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private pageHeader() {
    Row({ space: $r('app.float.p1_spacing_small') }) {
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(20)
          .fontColor([$r('app.color.primary_text')])
      }
      .id('p3_blocked_feed_history_back')
      .width(40)
      .height(40)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .accessibilityText('返回')
      .onClick((): void => this.onBack())
      Text('屏蔽记录')
        .fontSize($r('app.float.p1_heading_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .layoutWeight(1)
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.ellipsis_circle'))
          .fontSize(20)
          .fontColor([$r('app.color.primary_text')])
      }
      .id('p3_blocked_feed_history_actions')
      .width(40)
      .height(40)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .accessibilityText('屏蔽记录操作')
      .onClick((): void => {
        this.historyActionsSheetShown = true;
      })
    }
    .width('100%')
  }

  @Builder
  private historyActionsSheet() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Text('屏蔽记录操作')
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
        .id('p3_blocked_feed_history_actions_close')
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText('关闭屏蔽记录操作')
        .onClick((): void => {
          this.historyActionsSheetShown = false;
        })
      }
      .width('100%')
      Button('清空全部屏蔽记录')
        .id('p3_blocked_feed_history_clear')
        .width('100%')
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.error_text'))
        .backgroundColor($r('app.color.control_background'))
        .enabled(!this.viewState.busy && this.viewState.records.length > 0)
        .onClick((): void => {
          this.historyActionsSheetShown = false;
          this.confirmClear = true;
        })
    }
    .width('100%')
    .padding($r('app.float.p1_page_padding'))
  }

  @Builder
  private historyRow(record: BlockedFeedRecord) {
    Row({ space: $r('app.float.p1_spacing_small') }) {
      Column({ space: 2 }) {
        Text(`${blockedFeedHistoryItemLabel(record.kind)}：${record.ruleName}`)
          .id(`p3_blocked_feed_history_rule_${record.id}`)
          .fontSize($r('app.float.p1_body_font_size'))
          .fontWeight(FontWeight.Medium)
          .width('100%')
        Text(record.contentTitle)
          .fontSize($r('app.float.p1_caption_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.displayTime(record.blockedAt))
          .fontSize($r('app.float.p1_caption_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }
      .layoutWeight(1)
      Button('删除')
        .id(`p3_blocked_feed_history_delete_${record.id}`)
        .enabled(!this.viewState.busy)
        .onClick((): void => {
          this.controller?.delete(record.id);
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
      Text('清空屏蔽记录')
        .fontSize($r('app.float.p1_heading_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Text('确认清空全部屏蔽记录？此操作无法撤销。')
        .fontSize($r('app.float.p1_body_font_size'))
        .width('100%')
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Button('取消')
          .id('p3_blocked_feed_history_clear_cancel')
          .layoutWeight(1)
          .onClick((): void => {
            this.confirmClear = false;
          })
        Button('确认清空')
          .id('p3_blocked_feed_history_clear_confirm')
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
  }

  private displayTime(blockedAt: number): string {
    try {
      return new Date(blockedAt).toISOString().replace('T', ' ').substring(0, 19);
    } catch (_error) {
      return '时间未知';
    }
  }
}
