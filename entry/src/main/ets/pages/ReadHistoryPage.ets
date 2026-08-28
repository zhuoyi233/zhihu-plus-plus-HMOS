import {
  LoginSessionGateway,
  OnlineHistoryRepository,
  ReadHistoryGateway,
  SessionStatus
} from 'data';
import {
  filterReadHistoryItems,
  groupReadHistoryItems,
  ReadHistoryController,
  ReadHistoryGroup,
  ReadHistoryItem,
  readHistoryKindLabel,
  readHistoryOpenTarget,
  ReadHistoryOpenTarget,
  ReadHistoryPhase,
  ReadHistorySourceFilter,
  readHistorySourceFilterLabel,
  readHistorySourceLabel,
  ReadHistoryViewState
} from './ReadHistoryState';

export type OpenReadHistoryItem = (target: ReadHistoryOpenTarget) => void;

@Component
export struct ReadHistoryPage {
  history: ReadHistoryGateway | undefined = undefined;
  onlineHistory: OnlineHistoryRepository | undefined = undefined;
  session: LoginSessionGateway | undefined = undefined;
  onOpen: OpenReadHistoryItem = (_target: ReadHistoryOpenTarget): void => {};
  onGoLogin: () => void = (): void => {};
  onBack: () => void = (): void => {};
  @State private viewState: ReadHistoryViewState = {
    phase: ReadHistoryPhase.LOADING,
    items: [],
    busy: false,
    message: '正在读取本地已读记录',
    requiresLogin: false,
    onlineEnabled: false,
    loadingMore: false,
    canLoadMore: false
  };
  @State private confirmClear: boolean = false;
  @State private sourceFilterSheetShown: boolean = false;
  @State private historyActionsSheetShown: boolean = false;
  @State private selectedSourceFilter: ReadHistorySourceFilter = ReadHistorySourceFilter.ALL;
  private controller?: ReadHistoryController;

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
        phase: ReadHistoryPhase.ERROR,
        items: [],
        busy: false,
        message: '已读记录数据源未配置',
        requiresLogin: false,
        onlineEnabled: false,
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
      });
    this.controller.activate();
  }

  aboutToDisappear(): void {
    this.controller?.deactivate();
    this.controller = undefined;
    this.confirmClear = false;
    this.sourceFilterSheetShown = false;
    this.historyActionsSheetShown = false;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: $r('app.float.p1_spacing_medium') }) {
        this.pageHeader()
        Text('只保存在本机；不保存正文、Cookie、搜索词或账号信息。')
          .id('p2_read_history_privacy')
          .fontSize($r('app.float.p1_caption_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
        Text(this.viewState.message)
          .id('p2_read_history_status')
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor(this.viewState.phase === ReadHistoryPhase.ERROR ?
            $r('app.color.error_text') : $r('app.color.secondary_text'))
          .width('100%')
        if (this.viewState.requiresLogin) {
          this.loginBanner()
        }
        if (this.viewState.phase === ReadHistoryPhase.LOADING && this.viewState.items.length === 0) {
          LoadingProgress()
            .id('p2_read_history_loading')
            .width(40)
            .height(40)
            .color($r('app.color.brand_primary'))
        } else if (this.visibleItems().length === 0) {
          Column({ space: $r('app.float.p1_spacing_medium') }) {
            Text(this.emptyHistoryMessage())
              .fontSize($r('app.float.p1_body_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .textAlign(TextAlign.Center)
              .width('100%')
            if (this.viewState.phase === ReadHistoryPhase.ERROR && this.viewState.items.length === 0) {
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
          List({ space: 10 }) {
            ForEach(groupReadHistoryItems(this.visibleItems()), (group: ReadHistoryGroup) => {
              ListItem() {
                this.groupSection(group)
              }
            }, (group: ReadHistoryGroup): string => group.kind)
            if ((this.viewState.canLoadMore || this.viewState.loadingMore) &&
              this.selectedSourceFilter !== ReadHistorySourceFilter.LOCAL) {
              ListItem() {
                Button(this.viewState.loadingMore ? '正在加载更多…' : '加载更多在线历史')
                  .id('p3_read_history_load_more')
                  .width('100%')
                  .fontSize($r('app.float.p1_secondary_font_size'))
                  .enabled(!this.viewState.loadingMore && !this.viewState.busy)
                  .onClick((): void => {
                    this.controller?.loadMore();
                  })
              }
            }
          }
          .id('p2_read_history_list')
          .layoutWeight(1)
          .width('100%')
        }
      }
      .width('100%')
      .height('100%')
      .padding($r('app.float.p1_page_padding'))
      .backgroundColor($r('app.color.page_background'))

      Column()
        .bindSheet(this.sourceFilterSheetShown, this.sourceFilterSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false,
          maskColor: '#66000000',
          backgroundColor: $r('app.color.surface_background'),
          onDisappear: (): void => {
            if (this.sourceFilterSheetShown) {
              this.sourceFilterSheetShown = false;
            }
          }
        })
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
    .id('p2_read_history_page')
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
      .id('p3_read_history_back')
      .width(40)
      .height(40)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .accessibilityText('返回')
      .onClick((): void => this.onBack())
      Text('已读记录')
        .fontSize($r('app.float.p1_heading_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .layoutWeight(1)
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.line_3_horizontal'))
          .fontSize(20)
          .fontColor([$r('app.color.primary_text')])
      }
      .id('p3_read_history_source_filter')
      .width(40)
      .height(40)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .accessibilityText(`筛选已读记录来源，当前${readHistorySourceFilterLabel(this.selectedSourceFilter)}`)
      .onClick((): void => {
        this.sourceFilterSheetShown = true;
      })
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.more'))
          .fontSize(20)
          .fontColor([$r('app.color.primary_text')])
      }
      .id('p3_read_history_actions')
      .width(40)
      .height(40)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .accessibilityText('已读记录操作')
      .onClick((): void => {
        this.historyActionsSheetShown = true;
      })
    }
    .width('100%')
  }

  @Builder
  private sourceFilterSheet() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Text('筛选记录来源')
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
        .id('p3_read_history_source_filter_close')
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText('关闭来源筛选')
        .onClick((): void => {
          this.sourceFilterSheetShown = false;
        })
      }
      .width('100%')
      this.sourceFilterOption(ReadHistorySourceFilter.ALL, '全部记录', 'p3_read_history_source_all')
      this.sourceFilterOption(ReadHistorySourceFilter.LOCAL, '本地记录', 'p3_read_history_source_local')
      this.sourceFilterOption(ReadHistorySourceFilter.ONLINE, '在线记录', 'p3_read_history_source_online')
    }
    .width('100%')
    .padding($r('app.float.p1_page_padding'))
  }

  @Builder
  private sourceFilterOption(filter: ReadHistorySourceFilter, label: string, testId: string) {
    Button(label)
      .id(testId)
      .width('100%')
      .fontSize($r('app.float.p1_body_font_size'))
      .fontColor(this.selectedSourceFilter === filter ? $r('app.color.on_brand') : $r('app.color.primary_text'))
      .backgroundColor(this.selectedSourceFilter === filter ?
        $r('app.color.brand_primary') : $r('app.color.control_background'))
      .onClick((): void => {
        this.selectedSourceFilter = filter;
        this.sourceFilterSheetShown = false;
      })
  }

  @Builder
  private historyActionsSheet() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Text('历史操作')
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
        .id('p3_read_history_actions_close')
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText('关闭历史操作')
        .onClick((): void => {
          this.historyActionsSheetShown = false;
        })
      }
      .width('100%')
      Button('清空本地已读记录')
        .id('p3_read_history_clear')
        .width('100%')
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.error_text'))
        .backgroundColor($r('app.color.control_background'))
        .enabled(!this.viewState.busy && this.hasLocalItems())
        .onClick((): void => {
          this.historyActionsSheetShown = false;
          this.confirmClear = true;
        })
    }
    .width('100%')
    .padding($r('app.float.p1_page_padding'))
  }

  @Builder
  private loginBanner() {
    Row({ space: $r('app.float.p1_spacing_small') }) {
      Text('登录后可同步查看知乎账号的在线浏览历史')
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

  @Builder
  private groupSection(group: ReadHistoryGroup) {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      Text(readHistoryKindLabel(group.kind))
        .id(`p3_read_history_group_${group.kind}`)
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.brand_primary'))
        .width('100%')
      ForEach(group.items, (item: ReadHistoryItem) => {
        this.historyRow(item)
      }, (item: ReadHistoryItem): string => item.contentKey)
    }
    .width('100%')
  }

  @Builder
  private historyRow(item: ReadHistoryItem) {
    Row({ space: $r('app.float.p1_spacing_small') }) {
      Column({ space: 2 }) {
        Text(this.itemTitle(item))
          .fontSize($r('app.float.p1_body_font_size'))
          .width('100%')
        Text(`${this.displayTime(item.openedAt)} · ${readHistorySourceLabel(item)}`)
          .fontSize($r('app.float.p1_caption_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }
      .layoutWeight(1)
      Button('打开')
        .id(`p2_read_history_open_${item.contentKey}`)
        .enabled(!this.viewState.busy)
        .onClick((): void => this.onOpen(readHistoryOpenTarget(item)))
      if (item.deletable) {
        Button('删除')
          .id(`p2_read_history_delete_${item.contentKey}`)
          .enabled(!this.viewState.busy)
          .onClick((): void => {
            this.controller?.delete(item.contentKey);
          })
      }
    }
    .width('100%')
    .padding($r('app.float.p1_spacing_medium'))
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.p1_card_radius'))
  }

  @Builder
  private clearConfirmation() {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      Text('清空已读记录')
        .fontSize($r('app.float.p1_heading_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Text(this.viewState.onlineEnabled ?
        '确认清空全部本地已读记录？在线历史不会被清除。' : '确认清空全部本地已读记录？此操作无法撤销。')
        .fontSize($r('app.float.p1_body_font_size'))
        .width('100%')
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Button('取消')
          .id('p3_read_history_clear_cancel')
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
  }

  private visibleItems(): Array<ReadHistoryItem> {
    return filterReadHistoryItems(this.viewState.items, this.selectedSourceFilter);
  }

  private hasLocalItems(): boolean {
    return this.viewState.items.some((item: ReadHistoryItem): boolean => item.deletable);
  }

  private emptyHistoryMessage(): string {
    if (this.viewState.items.length === 0) {
      return this.viewState.message;
    }
    return `${readHistorySourceFilterLabel(this.selectedSourceFilter)}暂无记录`;
  }

  private itemTitle(item: ReadHistoryItem): string {
    const title = item.title?.trim() ?? '';
    return title.length > 0 ? title : `${readHistoryKindLabel(item.kind)} #${item.id}`;
  }

  private displayTime(openedAt: number): string {
    try {
      return new Date(openedAt).toISOString().replace('T', ' ').substring(0, 19);
    } catch (_error) {
      return '时间未知';
    }
  }
}
