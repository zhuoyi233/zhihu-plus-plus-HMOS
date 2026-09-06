import { ComponentContent } from '@kit.ArkUI';
import { LoginSessionGateway, OnlineHistoryRepository, ReadHistoryGateway, SessionStatus } from 'data';
import { FeedPullDownIndicatorOptions, feedPullDownIndicator } from './AppPageChrome';
import {
  ReadHistoryController,
  ReadHistoryItem,
  readHistoryKindLabel,
  ReadHistoryOpenTarget,
  ReadHistoryPhase,
  readHistoryTimeLabel,
  ReadHistoryViewState
} from './ReadHistoryState';

export type OpenReadHistoryItem = (target: ReadHistoryOpenTarget) => void;

/** 在线历史记录页：对齐上游 OnlineHistoryScreen 的卡片信息流。 */
@Component
export struct ReadHistoryPage {
  history: ReadHistoryGateway | undefined = undefined;
  onlineHistory: OnlineHistoryRepository | undefined = undefined;
  session: LoginSessionGateway | undefined = undefined;
  onOpen: OpenReadHistoryItem = (_target: ReadHistoryOpenTarget): void => {};
  onGoLogin: () => void = (): void => {};
  onNavigateLocal: () => void = (): void => {};
  @State private viewState: ReadHistoryViewState = {
    phase: ReadHistoryPhase.LOADING,
    items: [],
    busy: false,
    message: '正在加载历史记录',
    requiresLogin: false,
    loadingMore: false,
    canLoadMore: false
  };
  @State private refreshing: boolean = false;
  @State private confirmClear: boolean = false;
  // 标题栏溢出菜单在 stackBuilder 子树内，动作经 AppStorage tick 广播到本页（同 loginFeedReloadTick 模式）。
  // @StorageProp 键用字面量（装饰器要求编译期常量），值与 HistoryTitleBar.ets 导出常量一一对应。
  @StorageProp('readHistoryOpenLocalTick') @Watch('onOpenLocalTick') private openLocalTick: number = 0;
  @StorageProp('readHistoryClearTick') @Watch('onClearTick') private clearTick: number = 0;
  private controller?: ReadHistoryController;
  // 下拉刷新自定义加载圆圈（refreshingContent 需 ComponentContent，随页面销毁释放）
  private refreshContent?: ComponentContent<FeedPullDownIndicatorOptions> = undefined;

  aboutToAppear(): void {
    // 返回栈重显（页面实例与状态保留）时 aboutToAppear 可能再次触发；
    // 控制器仍存活时直接复用，避免重建控制器并重载记录导致滚动位置丢失。
    if (this.controller !== undefined) {
      this.controller.activate();
      return;
    }
    const history = this.history;
    if (history === undefined) {
      this.viewState = {
        phase: ReadHistoryPhase.ERROR,
        items: [],
        busy: false,
        message: '历史记录数据源未配置',
        requiresLogin: false,
        loadingMore: false,
        canLoadMore: false
      };
      return;
    }
    const session = this.session;
    const onlineEnabled = session !== undefined &&
      session.getState().status === SessionStatus.AUTHENTICATED;
    this.controller = new ReadHistoryController(history, this.onlineHistory, onlineEnabled,
      (state: ReadHistoryViewState): void => {
        this.viewState = state;
        this.refreshing = false;
      });
    this.refreshContent = new ComponentContent(this.getUIContext(), wrapBuilder(feedPullDownIndicator),
      new FeedPullDownIndicatorOptions());
    this.controller.activate();
  }

  aboutToDisappear(): void {
    this.controller?.deactivate();
    this.controller = undefined;
    this.refreshContent?.dispose();
    this.refreshContent = undefined;
    this.refreshing = false;
    this.confirmClear = false;
  }

  private onOpenLocalTick(): void {
    if (this.openLocalTick > 0) {
      this.onNavigateLocal();
    }
  }

  private onClearTick(): void {
    if (this.clearTick > 0) {
      this.confirmClear = true;
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: $r('app.float.p1_spacing_medium') }) {
        if (this.viewState.requiresLogin) {
          this.loginBanner()
        }
        if (this.viewState.phase === ReadHistoryPhase.LOADING && this.viewState.items.length === 0) {
          LoadingProgress()
            .id('p2_read_history_loading')
            .width(40)
            .height(40)
            .color($r('app.color.brand_primary'))
        } else if (this.viewState.items.length === 0) {
          Column({ space: $r('app.float.p1_spacing_medium') }) {
            Text(this.viewState.message)
              .id('p2_read_history_empty')
              .fontSize($r('app.float.p1_body_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .textAlign(TextAlign.Center)
              .width('100%')
            if (this.viewState.phase === ReadHistoryPhase.ERROR) {
              Button('重新加载')
                .id('p2_read_history_retry')
                .enabled(!this.viewState.busy)
                .onClick((): void => {
                  void this.controller?.reload();
                })
            }
          }
          .justifyContent(FlexAlign.Center)
          .layoutWeight(1)
          .width('100%')
        } else {
          Refresh({
            refreshing: this.refreshing,
            refreshingContent: this.refreshContent,
            offset: 80,
            friction: 100
          }) {
            List({ space: 12 }) {
              ForEach(this.viewState.items, (item: ReadHistoryItem) => {
                ListItem() {
                  this.historyCard(item)
                }
                .width('100%')
              }, (item: ReadHistoryItem): string => item.contentKey)

              if (this.viewState.loadingMore) {
                ListItem() {
                  LoadingProgress()
                    .id('p3_read_history_load_more')
                    .width(40)
                    .height(40)
                    .color($r('app.color.brand_primary'))
                }
                .width('100%')
                .padding({ top: 12, bottom: 12 })
              } else if (!this.viewState.canLoadMore) {
                ListItem() {
                  Text('已经到底啦')
                    .id('p2_read_history_end')
                    .fontSize($r('app.float.p1_secondary_font_size'))
                    .fontColor($r('app.color.secondary_text'))
                    .textAlign(TextAlign.Center)
                    .width('100%')
                    .padding({ top: 12, bottom: 12 })
                }
              }
            }
            .id('p2_read_history_list')
            .width('100%')
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .onReachEnd((): void => {
              void this.controller?.loadMore();
            })
          }
          .id('p2_read_history_pull_refresh')
          .width('100%')
          .layoutWeight(1)
          .onRefreshing((): void => {
            void this.controller?.reload();
          })
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: $r('app.float.p1_page_padding'), right: $r('app.float.p1_page_padding'),
        top: 94, bottom: $r('app.float.p1_page_padding') })
      .backgroundColor($r('app.color.page_background'))

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
    .id('p2_read_history_page')
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  /** 对齐上游 FeedCard：标题 2 行、作者 1 行、摘要 3 行 + 元信息行与右上角“更多”菜单。 */
  @Builder
  private historyCard(item: ReadHistoryItem) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Column({ space: $r('app.float.p1_spacing_small') }) {
        Row({ space: $r('app.float.p1_spacing_xsmall') }) {
          Text(`${readHistoryKindLabel(item.kind)} · ${readHistoryTimeLabel(item.openedAt)}`)
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.ellipsis_circle'))
              .fontSize(18)
              .fontColor([$r('app.color.secondary_text')])
          }
          .id(`p3_read_history_item_menu_${item.contentKey}`)
          .width(32)
          .height(32)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .enabled(!this.viewState.busy)
          .bindMenu(this.itemMenu(item))
          .accessibilityText('该条历史记录操作')
        }
        .width('100%')

        Text(this.itemTitle(item))
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (item.authorName !== undefined && item.authorName.length > 0) {
          Text(item.authorName)
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }

        if (item.summary.trim().length > 0) {
          Text(item.summary)
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .id(`p2_read_history_card_${item.contentKey}`)
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
    .borderRadius($r('app.float.p1_card_radius'))
    .backgroundColor($r('app.color.surface_background'))
    .accessibilityText(`打开${readHistoryKindLabel(item.kind)}：${this.itemTitle(item)}`)
    .onClick((): void => this.onOpen({ kind: item.kind, id: item.id }))
  }

  private itemMenu(item: ReadHistoryItem): Array<MenuElement> {
    return [{
      value: '删除该条历史记录',
      action: (): void => {
        void this.controller?.deleteEntry(item.contentKey);
      }
    }];
  }

  @Builder
  private loginBanner() {
    Row({ space: $r('app.float.p1_spacing_small') }) {
      Text('登录后可同步查看知乎账号的浏览历史')
        .id('p3_read_history_online_notice')
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .layoutWeight(1)
      Button('去登录')
        .id('p3_read_history_go_login')
        .fontSize($r('app.float.p1_secondary_font_size'))
        .onClick((): void => this.onGoLogin())
    }
    .width('100%')
    .padding($r('app.float.p1_spacing_medium'))
    .borderRadius($r('app.float.p1_card_radius'))
    .backgroundColor($r('app.color.surface_background'))
  }

  /** 对齐上游清除确认对话框：一次清除当前账号在线 + 本地全部历史记录。 */
  @Builder
  private clearConfirmation() {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      Text('确认清除历史记录')
        .fontSize($r('app.float.p1_heading_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Text('此操作会清除当前账号的在线和本地的全部历史记录。')
        .fontSize($r('app.float.p1_body_font_size'))
        .width('100%')
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Button('我再想想')
          .id('p3_read_history_clear_cancel')
          .layoutWeight(1)
          .onClick((): void => {
            this.confirmClear = false;
          })
        Button('确认')
          .id('p2_read_history_clear_confirm')
          .layoutWeight(1)
          .enabled(!this.viewState.busy)
          .onClick((): void => {
            this.confirmClear = false;
            void this.controller?.clearAll();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding($r('app.float.p1_spacing_medium'))
  }

  private itemTitle(item: ReadHistoryItem): string {
    const title = item.title.trim();
    return title.length > 0 ? title : `${readHistoryKindLabel(item.kind)} #${item.id}`;
  }
}
