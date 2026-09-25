import { onThemeColor, DEFAULT_THEME_COLOR, ReadHistoryGateway } from 'data';
import { FLOATING_TITLE_BAR_OFFSET, FeedPullDownIndicatorHost } from './AppPageChrome';
import {
  LocalHistoryController,
  ReadHistoryItem,
  readHistoryKindLabel,
  ReadHistoryOpenTarget,
  ReadHistoryPhase,
  readHistoryTimeLabel,
  ReadHistoryViewState
} from './ReadHistoryState';

/** 本地历史记录页：对齐上游 LegacyLocalHistoryScreen，一次性读取本机已读记录的卡片列表。 */
@Component
export struct LocalHistoryPage {
  history: ReadHistoryGateway | undefined = undefined;
  onOpen: (target: ReadHistoryOpenTarget) => void = (_target: ReadHistoryOpenTarget): void => {};
  @State private viewState: ReadHistoryViewState = {
    phase: ReadHistoryPhase.LOADING,
    items: [],
    busy: false,
    message: '正在读取本地历史记录',
    requiresLogin: false,
    loadingMore: false,
    canLoadMore: false
  };
  @State @Watch('syncRefreshIndicator') private refreshing: boolean = false;
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  private controller?: LocalHistoryController;
  // 下拉刷新自定义加载圆圈（refreshingContent 需 ComponentContent，随页面销毁释放）
  private indicator?: FeedPullDownIndicatorHost = undefined;

  aboutToAppear(): void {
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
        message: '本地历史记录数据源未配置',
        requiresLogin: false,
        loadingMore: false,
        canLoadMore: false
      };
      return;
    }
    this.controller = new LocalHistoryController(history, (state: ReadHistoryViewState): void => {
      this.viewState = state;
      // 对齐上游 FeedPullToRefresh：指示器 = 下拉触发 && 加载中，加载结束（无论成败）才停。
      // Refresh 需 $$ 双向绑定让手势回写生效，否则刷新圈会永远卡住（见 ReadHistoryPage 注释）。
      this.refreshing = state.busy && state.phase === ReadHistoryPhase.LOADING;
    });
    this.indicator = new FeedPullDownIndicatorHost(this.getUIContext(), 0);
    this.controller.activate();
  }

  aboutToDisappear(): void {
    this.controller?.deactivate();
    this.controller = undefined;
    this.indicator?.dispose();
    this.indicator = undefined;
  }

  /** 圆圈只在间隙展开时绘制（ArkUI 收起头部后不裁剪自定义内容）。 */
  private syncRefreshIndicator(): void {
    this.indicator?.setRefreshing(this.refreshing);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: $r('app.float.p1_spacing_medium') }) {
        Text('只保存在本机；不保存正文、Cookie、搜索词或账号信息。')
          .id('p2_read_history_privacy')
          .fontSize($r('app.float.p1_caption_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
        if (this.viewState.phase === ReadHistoryPhase.LOADING && this.viewState.items.length === 0) {
          LoadingProgress()
            .id('p2_local_history_loading')
            .width(40)
            .height(40)
            .color(this.resolvedThemeColor)
        } else if (this.viewState.items.length === 0) {
          Column({ space: $r('app.float.p1_spacing_medium') }) {
            Text(this.viewState.message)
              .id('p2_local_history_empty')
              .fontSize($r('app.float.p1_body_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .textAlign(TextAlign.Center)
              .width('100%')
            if (this.viewState.phase === ReadHistoryPhase.ERROR) {
              Button('重新读取')
                .backgroundColor(this.resolvedThemeColor)
                .fontColor(onThemeColor(this.resolvedThemeColor))
                .id('p2_local_history_retry')
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
            refreshing: $$this.refreshing,
            refreshingContent: this.indicator?.view(),
            offset: 80,
            friction: 100
          }) {
            List({ space: 12 }) {
              ForEach(this.viewState.items, (item: ReadHistoryItem) => {
                ListItem() {
                  this.localHistoryCard(item)
                }
                .width('100%')
              }, (item: ReadHistoryItem): string => item.contentKey)
            }
            .id('p2_local_history_list')
            .width('100%')
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
          }
          .id('p2_local_history_pull_refresh')
          .width('100%')
          .layoutWeight(1)
          .onRefreshing((): void => {
            void this.controller?.reload();
          })
          .onStateChange((status: RefreshStatus): void => this.indicator?.onStateChange(status))
        }
      }
      .width('100%')
      .height('100%')
      // 让位统一约定：内容容器 padding top = FLOATING_TITLE_BAR_OFFSET，刷新指示区域
      // 从悬浮标题栏下沿开始（对齐上游 FeedPullToRefresh 的 indicator padding）
      .padding({ left: $r('app.float.p1_page_padding'), right: $r('app.float.p1_page_padding'),
        top: FLOATING_TITLE_BAR_OFFSET, bottom: $r('app.float.p1_page_padding') })
      .backgroundColor($r('app.color.page_background'))
    }
    .id('p2_local_history_page')
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private localHistoryCard(item: ReadHistoryItem) {
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
          .id(`p3_local_history_item_menu_${item.contentKey}`)
          .width(32)
          .height(32)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .enabled(!this.viewState.busy)
          .bindMenu(this.itemMenu(item))
          .accessibilityText('该条本地记录操作')
        }
        .width('100%')

        Text(this.itemTitle(item))
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .id(`p2_local_history_card_${item.contentKey}`)
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
    .borderRadius($r('app.float.p1_card_radius'))
    .backgroundColor($r('app.color.surface_background'))
    .accessibilityText(`打开${readHistoryKindLabel(item.kind)}：${this.itemTitle(item)}`)
    .onClick((): void => this.onOpen({ kind: item.kind, id: item.id }))
  }

  private itemMenu(item: ReadHistoryItem): Array<MenuElement> {
    return [{
      value: '删除该条本地记录',
      action: (): void => {
        void this.controller?.delete(item.contentKey);
      }
    }];
  }

  private itemTitle(item: ReadHistoryItem): string {
    const title = item.title.trim();
    return title.length > 0 ? title : `${readHistoryKindLabel(item.kind)} #${item.id}`;
  }
}
