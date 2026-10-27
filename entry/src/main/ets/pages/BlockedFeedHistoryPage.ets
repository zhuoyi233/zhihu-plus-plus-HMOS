import { CenteredOverlayDialog } from './CenteredOverlayDialog';
import {
  onThemeColor,
  BlockedFeedHistoryGateway,
  BlockedFeedRecord,
  DEFAULT_THEME_COLOR,
  FeedCardStyle
} from 'data';
import {
  BlockedFeedHistoryController,
  BlockedFeedHistoryPhase,
  BlockedFeedHistoryViewState,
  blockedFeedHistoryItemLabel
} from './BlockedFeedHistoryState';
import { adaptiveOverlayWidth, isWideOverlayContainer, ADAPTIVE_OVERLAY_MENU_WIDTH_VP } from '../common/style/AdaptiveOverlayLayout';
import { settingsGroupBackground, settingsGroupRadius } from './AccountSettingsLayout';

/**
 * 屏蔽记录：说明、状态与记录共用一个主列表，嵌入设置右栏时由宿主画标题并提供“更多”。
 */
@Component
export struct BlockedFeedHistoryPage {
  history: BlockedFeedHistoryGateway | undefined = undefined;
  onBack: () => void = (): void => {};
  /** 嵌入设置容器：不画自带标题、不叠加覆盖式让位，动作交给宿主标题栏。 */
  @Prop embedded: boolean = false;
  /** 宿主动作槽登记：嵌入时把“更多”菜单交给宿主标题栏渲染。 */
  onRegisterHeaderActions: (handler: () => void) => void = (_handler: () => void): void => {};
  onReleaseHeaderActions: () => void = (): void => {};
  @State private viewState: BlockedFeedHistoryViewState = {
    phase: BlockedFeedHistoryPhase.LOADING,
    records: [],
    busy: false,
    message: '正在读取屏蔽记录'
  };
  @State @Watch('clearDialogChanged') private confirmClear: boolean = false;
  @State private historyActionsSheetShown: boolean = false;
  @State private overlayWidthVp: number = 0;
  @StorageProp('statusBarHeight') private statusBarHeightVp: number = 0;
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @StorageProp('feedCardStyle') private feedCardStyle: string = FeedCardStyle.DIVIDER;
  private controller?: BlockedFeedHistoryController;

  private clearDialog: CustomDialogController = new CustomDialogController({
    builder: CenteredOverlayDialog({ content: (): void => { this.clearConfirmation(); } }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    maskColor: '#99000000',
    backgroundColor: $r('app.color.surface_background'),
    cancel: (): void => { this.confirmClear = false; }
  });

  private clearDialogChanged(): void {
    if (this.confirmClear) {
      this.clearDialog.open();
    } else {
      this.clearDialog.close();
    }
  }

  aboutToAppear(): void {
    if (this.embedded) {
      this.onRegisterHeaderActions((): void => {
        this.historyActionsSheetShown = true;
      });
    }
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
    if (this.embedded) {
      this.onReleaseHeaderActions();
    }
    this.controller?.deactivate();
    this.controller = undefined;
    this.confirmClear = false;
    this.historyActionsSheetShown = false;
  }

  private isCardStyle(): boolean {
    return this.feedCardStyle === FeedCardStyle.CARD;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.historyList()

      if (!this.embedded) {
        Column() {
          this.pageHeader()
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8 })
        .position({ x: 0, y: Math.max(this.statusBarHeightVp, 0) })
        .zIndex(2)
      } else if (this.historyActionsSheetShown) {
        // 嵌入时不用全屏 sheet：动作限定在右栏内的覆盖容器，背景设置目录同时被遮罩阻断。
        this.embeddedActionsOverlay()
      }
    }
    .id('blocked_feed_history_page')
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      const width = Number(newArea.width);
      if (width > 0) {
        this.overlayWidthVp = width;
      }
    })
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private historyList() {
    List({ space: this.isCardStyle() ? 10 : 0 }) {
      ListItem() {
        Text('只保存在本机；记录你屏蔽过的作者、关键词和话题，不保存正文或账号信息。删除记录不会解除屏蔽规则。')
          .id('blocked_feed_history_privacy')
          .fontSize($r('app.float.caption_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
          .padding({ top: 4, bottom: 4 })
      }

      ListItem() {
        Text(this.viewState.message)
          .id('blocked_feed_history_status')
          .fontSize($r('app.float.body_font_size'))
          .fontColor(this.viewState.phase === BlockedFeedHistoryPhase.ERROR ?
            $r('app.color.error_text') : $r('app.color.secondary_text'))
          .width('100%')
          .padding({ top: 4, bottom: 4 })
      }

      if (this.viewState.phase === BlockedFeedHistoryPhase.LOADING && this.viewState.records.length === 0) {
        ListItem() {
          Row() {
            LoadingProgress()
              .id('blocked_feed_history_loading')
              .width(40)
              .height(40)
              .color(this.resolvedThemeColor)
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 48, bottom: 48 })
        }
      } else if (this.viewState.records.length === 0) {
        ListItem() {
          Column({ space: $r('app.float.spacing_medium') }) {
            Text(this.viewState.phase === BlockedFeedHistoryPhase.EMPTY ? '暂无屏蔽记录' : this.viewState.message)
              .fontSize($r('app.float.body_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .textAlign(TextAlign.Center)
              .width('100%')
            if (this.viewState.phase === BlockedFeedHistoryPhase.ERROR) {
              Button('重新读取')
                .backgroundColor(this.resolvedThemeColor)
                .fontColor(onThemeColor(this.resolvedThemeColor))
                .id('blocked_feed_history_retry')
                .enabled(!this.viewState.busy)
                .onClick((): void => {
                  this.controller?.reload();
                })
            }
          }
          .justifyContent(FlexAlign.Center)
          .width('100%')
          .padding({ top: 48, bottom: 48 })
        }
      } else {
        ForEach(this.viewState.records, (record: BlockedFeedRecord) => {
          ListItem() {
            this.historyRow(record)
          }
        }, (record: BlockedFeedRecord): string => `${record.id}`)
      }
    }
    .id('blocked_feed_history_list')
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .padding({
      left: $r('app.float.page_padding'),
      right: $r('app.float.page_padding'),
      top: this.embedded ? 4 : 94,
      bottom: $r('app.float.page_padding')
    })
  }

  @Builder
  private pageHeader() {
    Row({ space: $r('app.float.spacing_small') }) {
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(20)
          .fontColor([$r('app.color.primary_text')])
      }
      .id('blocked_feed_history_back')
      .width(40)
      .height(40)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .accessibilityText('返回')
      .onClick((): void => this.onBack())
      Text('屏蔽记录')
        .fontSize($r('app.float.heading_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .layoutWeight(1)
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.ellipsis_circle'))
          .fontSize(20)
          .fontColor([$r('app.color.primary_text')])
      }
      .id('blocked_feed_history_actions')
      .width(40)
      .height(40)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .accessibilityText('屏蔽记录操作')
      .bindSheet(this.historyActionsSheetShown, this.historyActionsSheet(), {
        preferType: isWideOverlayContainer(this.overlayWidthVp) ? SheetType.POPUP : SheetType.BOTTOM,
        width: isWideOverlayContainer(this.overlayWidthVp)
          ? adaptiveOverlayWidth(this.overlayWidthVp, ADAPTIVE_OVERLAY_MENU_WIDTH_VP) : '100%',
        height: SheetSize.FIT_CONTENT,
        dragBar: !isWideOverlayContainer(this.overlayWidthVp),
        showClose: false,
        maskColor: '#99000000',
        backgroundColor: $r('app.color.surface_background'),
        onDisappear: (): void => {
          if (this.historyActionsSheetShown) {
            this.historyActionsSheetShown = false;
          }
        }
      })
      .onClick((): void => {
        this.historyActionsSheetShown = true;
      })
    }
    .width('100%')
  }

  @Builder
  private embeddedActionsOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#99000000')
        .onClick((): void => {
          this.historyActionsSheetShown = false;
        })
      Column() {
        this.historyActionsSheet()
      }
      .width('88%')
      .constraintSize({ maxWidth: 420 })
      .backgroundColor(settingsGroupBackground(FeedCardStyle.CARD))
      .borderRadius(settingsGroupRadius(FeedCardStyle.CARD))
      .shadow({ radius: 24, color: '#33000000', offsetY: 8 })
    }
    .id('blocked_feed_history_actions_overlay')
    .width('100%')
    .height('100%')
    .zIndex(3)
  }

  @Builder
  private historyActionsSheet() {
    Column({ space: $r('app.float.spacing_medium') }) {
      Row({ space: $r('app.float.spacing_small') }) {
        Text('屏蔽记录操作')
          .fontSize($r('app.float.heading_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
        .id('blocked_feed_history_actions_close')
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
        .id('blocked_feed_history_clear')
        .width('100%')
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.error_text'))
        .backgroundColor($r('app.color.control_background'))
        .enabled(!this.viewState.busy && this.viewState.records.length > 0)
        .onClick((): void => {
          this.historyActionsSheetShown = false;
          this.confirmClear = true;
        })
    }
    .width('100%')
    .padding($r('app.float.page_padding'))
  }

  @Builder
  private historyRow(record: BlockedFeedRecord) {
    Row({ space: $r('app.float.spacing_small') }) {
      Column({ space: 2 }) {
        Text(`${blockedFeedHistoryItemLabel(record.kind)}：${record.ruleName}`)
          .id(`blocked_feed_history_rule_${record.id}`)
          .fontSize($r('app.float.body_font_size'))
          .fontWeight(FontWeight.Medium)
          .width('100%')
        Text(record.contentTitle)
          .fontSize($r('app.float.caption_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.displayTime(record.blockedAt))
          .fontSize($r('app.float.caption_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }
      .layoutWeight(1)
      Button('删除记录')
        .backgroundColor($r('app.color.control_background'))
        .fontColor($r('app.color.primary_text'))
        .fontSize($r('app.float.secondary_font_size'))
        .id(`blocked_feed_history_delete_${record.id}`)
        .enabled(!this.viewState.busy)
        .onClick((): void => {
          this.controller?.delete(record.id);
        })
    }
    .width('100%')
    .padding(this.isCardStyle() ? 14 : 12)
    .backgroundColor(this.isCardStyle() ? $r('app.color.card_background') : Color.Transparent)
    .borderRadius(this.isCardStyle() ? $r('app.float.card_radius') : 0)
  }

  @Builder
  private clearConfirmation() {
    Column({ space: $r('app.float.spacing_small') }) {
      Text('清空屏蔽记录')
        .fontSize($r('app.float.heading_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Text('确认清空全部屏蔽记录？仅清空记录，屏蔽规则继续生效；此操作无法撤销。')
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Row({ space: $r('app.float.spacing_small') }) {
        Button('取消')
          .backgroundColor($r('app.color.control_background'))
          .fontColor($r('app.color.primary_text'))
          .id('blocked_feed_history_clear_cancel')
          .layoutWeight(1)
          .onClick((): void => {
            this.confirmClear = false;
          })
        Button('确认清空')
          .backgroundColor(this.resolvedThemeColor)
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .id('blocked_feed_history_clear_confirm')
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
    .padding($r('app.float.spacing_medium'))
  }

  private displayTime(blockedAt: number): string {
    try {
      return new Date(blockedAt).toISOString().replace('T', ' ').substring(0, 19);
    } catch (_error) {
      return '时间未知';
    }
  }
}
