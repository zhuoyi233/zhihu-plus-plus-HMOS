import { P1Destination, P1DestinationName } from 'core';
import { FeedTargetKind, SearchRepository, SearchResultItem, searchResultIdentity } from 'data';
import { SearchController, SearchPhase, SearchViewState } from './SearchState';

interface EmphasisPart {
  text: string;
  emphasized: boolean;
}

/** 当前搜索接口稳定返回内容实体，结果页按实体类型在端侧切换。 */
export enum SearchResultFilter {
  ALL = 0,
  QUESTION = 1,
  ANSWER = 2,
  ARTICLE = 3
}

/** 把搜索接口返回的 `<em>关键词</em>` 拆成高亮片段（无标签时整段普通文本）。 */
function splitEmphasis(text: string): Array<EmphasisPart> {
  const parts: Array<EmphasisPart> = [];
  const pattern = /<em>([\s\S]*?)<\/em>/gi;
  let lastIndex = 0;
  let match = pattern.exec(text);
  while (match !== null) {
    if (match.index > lastIndex) {
      parts.push({ text: text.substring(lastIndex, match.index), emphasized: false });
    }
    const emphasized = match[1];
    if (emphasized !== undefined && emphasized.length > 0) {
      parts.push({ text: emphasized, emphasized: true });
    }
    lastIndex = match.index + match[0].length;
    match = pattern.exec(text);
  }
  if (lastIndex < text.length) {
    parts.push({ text: text.substring(lastIndex), emphasized: false });
  }
  if (parts.length === 0) {
    parts.push({ text: text, emphasized: false });
  }
  return parts;
}

@Component
export struct SearchPage {
  initialQuery: string = '';
  repository: SearchRepository | undefined = undefined;
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {
  };
  onBack: () => void = (): void => {
  };
  @State private input: string = '';
  @State private phase: SearchPhase = SearchPhase.IDLE;
  @State private query: string = '';
  @State private items: Array<SearchResultItem> = [];
  @State private loadingMore: boolean = false;
  @State private canLoadMore: boolean = false;
  @State private requiresLogin: boolean = false;
  @State private errorMessage: string = '';
  @State private selectedResultFilter: number = SearchResultFilter.ALL;
  private controller?: SearchController;

  aboutToAppear(): void {
    if (this.controller !== undefined) {
      this.controller.activate();
      return;
    }
    this.input = this.initialQuery;
    if (this.repository === undefined) {
      return;
    }
    this.controller = new SearchController(this.repository, (state: SearchViewState): void => {
      this.applyState(state);
    });
    this.controller.activate();
    if (this.initialQuery.trim().length > 0) {
      this.controller.submit(this.initialQuery);
    }
  }

  aboutToDisappear(): void {
    this.controller?.deactivate();
  }

  build() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
        .id('p2_search_back')
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText('返回')
        .onClick((): void => this.onBack())

        Row({ space: $r('app.float.p1_spacing_xsmall') }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(18)
            .fontColor([$r('app.color.secondary_text')])
          TextInput({ text: this.input, placeholder: '搜索知乎内容' })
            .id('p2_search_input')
            .layoutWeight(1)
            .fontSize($r('app.float.p1_body_font_size'))
            .maxLength(200)
            .enterKeyType(EnterKeyType.Search)
            .backgroundColor(Color.Transparent)
            .onChange((value: string): void => {
              this.input = value;
            })
            .onSubmit((): void => {
              this.submitInput();
            })

          if (this.input.length > 0) {
            Button({ type: ButtonType.Normal, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(16)
                .fontColor([$r('app.color.secondary_text')])
            }
            .id('p2_search_clear')
            .width(32)
            .height(32)
            .padding(0)
            .backgroundColor(Color.Transparent)
            .accessibilityText('清除搜索内容')
            .onClick((): void => {
              this.input = '';
              this.controller?.submit('');
            })
          }
        }
        .id('p2_search_input_container')
          .layoutWeight(1)
        .height(40)
        .padding({ left: $r('app.float.p1_spacing_small'), right: $r('app.float.p1_spacing_xsmall') })
        .backgroundColor($r('app.color.control_background'))
        .borderRadius($r('app.float.p1_card_radius'))
        .alignItems(VerticalAlign.Center)

        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.line_3_horizontal'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
        .id('p2_search_filter')
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText(`筛选搜索结果，当前${searchResultFilterLabel(this.selectedResultFilter)}`)
        .bindMenu(this.filterMenu())

      }
      .id('p2_search_input_row')
      .width('100%')

      if (this.query.length > 0) {
        this.resultTabs();
      }

      if (this.repository === undefined) {
        this.statusPanel('搜索数据源未配置', false, 'p2_search_unconfigured');
      } else if (this.phase === SearchPhase.IDLE) {
        this.statusPanel('输入关键词开始搜索', false, 'p2_search_idle');
      } else if (this.phase === SearchPhase.LOADING) {
        this.statusPanel('正在搜索…', false, 'p2_search_loading');
      } else if (this.phase === SearchPhase.ERROR) {
        this.statusPanel(this.errorMessage, true, 'p2_search_error');
      } else if (this.phase === SearchPhase.EMPTY) {
        this.statusPanel('没有找到可显示的相关结果', true, 'p2_search_empty');
      } else {
        if (this.errorMessage.length > 0) {
          Column({ space: $r('app.float.p1_spacing_small') }) {
            Text(this.errorMessage)
              .id('p2_search_recoverable_error_text')
              .fontSize($r('app.float.p1_secondary_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .width('100%')
            Row({ space: $r('app.float.p1_spacing_small') }) {
              Button('重试')
                .id('p2_search_recoverable_error_retry')
                .layoutWeight(1)
                .onClick(() => this.controller?.retry())
              if (this.requiresLogin) {
                Button('去登录')
                  .id('p2_search_recoverable_error_login')
                  .layoutWeight(1)
                  .onClick(() => this.openLogin())
              }
            }
            .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding($r('app.float.p1_spacing_small'))
          .borderRadius($r('app.float.p1_card_radius'))
          .backgroundColor($r('app.color.surface_background'))
        }

        if (this.filteredItems().length === 0) {
          Text(`${searchResultFilterLabel(this.selectedResultFilter)}分类下暂无结果`)
            .id('p2_search_filtered_empty')
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .textAlign(TextAlign.Center)
            .width('100%')
            .padding($r('app.float.p1_spacing_large'))
        }

        List() {
          ForEach(this.filteredItems(), (item: SearchResultItem) => {
            ListItem() {
              this.resultCard(item);
            }
            .margin({ bottom: $r('app.float.p1_spacing_medium') })
          }, (item: SearchResultItem): string => searchResultIdentity(item))

          if (this.loadingMore || this.canLoadMore) {
            ListItem() {
              Button(this.loadingMore ? '正在加载更多…' : '加载更多')
                .id('p2_search_load_more')
                .width('100%')
                .fontSize($r('app.float.p1_secondary_font_size'))
                .enabled(!this.loadingMore)
                .onClick(() => this.controller?.loadMore())
            }
          }
        }
        .id('p2_search_result_list')
        .width('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
        .onReachEnd(() => this.controller?.loadMore())
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .padding({
      left: $r('app.float.p1_page_padding'),
      right: $r('app.float.p1_page_padding'),
      top: $r('app.float.p1_spacing_medium'),
      bottom: $r('app.float.p1_page_padding')
    })
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private resultTabs() {
    Tabs({ barPosition: BarPosition.Start, index: $$this.selectedResultFilter }) {
      TabContent() {
        Column() {
          Blank();
        }
      }
      .tabBar(searchResultFilterLabel(SearchResultFilter.ALL))
      TabContent() {
        Column() {
          Blank();
        }
      }
      .tabBar(searchResultFilterLabel(SearchResultFilter.QUESTION))
      TabContent() {
        Column() {
          Blank();
        }
      }
      .tabBar(searchResultFilterLabel(SearchResultFilter.ANSWER))
      TabContent() {
        Column() {
          Blank();
        }
      }
      .tabBar(searchResultFilterLabel(SearchResultFilter.ARTICLE))
    }
    .id('p2_search_result_tabs')
    .width('100%')
    .height(44)
    .barHeight(44)
    .barMode(BarMode.Fixed)
    .scrollable(false)
    .onChange((index: number): void => {
      if (isSearchResultFilter(index)) {
        this.selectedResultFilter = index;
      }
    })
  }

  private filteredItems(): Array<SearchResultItem> {
    return filterSearchResults(this.items, this.selectedResultFilter);
  }

  private filterMenu(): Array<MenuElement> {
    const menu: Array<MenuElement> = [];
    const filters: Array<SearchResultFilter> = [
      SearchResultFilter.ALL,
      SearchResultFilter.QUESTION,
      SearchResultFilter.ANSWER,
      SearchResultFilter.ARTICLE
    ];
    filters.forEach((filter: SearchResultFilter): void => {
      menu.push({
        value: searchResultFilterLabel(filter),
        action: (): void => {
          this.selectedResultFilter = filter;
        }
      });
    });
    return menu;
  }

  @Builder
  private statusPanel(message: string, retry: boolean, testId: string) {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      if (testId === 'p2_search_loading') {
        LoadingProgress()
          .id('p2_search_loading_progress')
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
        Button('重试')
          .id(`${testId}_retry`)
          .fontSize($r('app.float.p1_body_font_size'))
          .onClick(() => this.controller?.retry())
      }
      if (this.requiresLogin) {
        Button('去登录')
          .id('p2_search_error_login')
          .fontSize($r('app.float.p1_body_font_size'))
          .onClick(() => this.openLogin())
      }
    }
    .id(testId)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private highlightedText(text: string, fontSize: Resource, baseColor: Resource, baseWeight: FontWeight) {
    Text() {
      ForEach(splitEmphasis(text), (part: EmphasisPart, index: number) => {
        if (part.emphasized) {
          Span(part.text)
            .fontColor($r('app.color.brand_primary'))
            .fontWeight(FontWeight.Bold)
        } else {
          Span(part.text)
        }
      }, (part: EmphasisPart, index: number): string => `${index}:${part.emphasized}:${part.text}`)
    }
    .fontSize(fontSize)
    .fontColor(baseColor)
    .fontWeight(baseWeight)
    .width('100%')
  }

  @Builder
  private resultCard(item: SearchResultItem) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Column({ space: $r('app.float.p1_spacing_small') }) {
        Row({ space: $r('app.float.p1_spacing_small') }) {
          Text(searchKindLabel(item.kind))
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.brand_primary'))
          if (item.authorName !== undefined) {
            Text(item.authorName)
              .fontSize($r('app.float.p1_secondary_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .layoutWeight(1)
          } else {
            Blank().layoutWeight(1)
          }
        }
        .width('100%')

        this.highlightedText(item.title, $r('app.float.p1_heading_font_size'),
          $r('app.color.primary_text'), FontWeight.Medium)

        if (item.excerpt.trim().length > 0) {
          this.highlightedText(item.excerpt, $r('app.float.p1_body_font_size'),
            $r('app.color.secondary_text'), FontWeight.Regular)
        }

        Text(`${item.voteupCount} 赞同 · ${item.commentCount} 评论`)
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .id(`p2_search_result_${item.kind}_${item.contentId}`)
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
    .borderRadius($r('app.float.p1_card_radius'))
    .backgroundColor($r('app.color.surface_background'))
    .accessibilityText(`打开${searchKindLabel(item.kind)}：${item.title}`)
    .onClick(() => this.navigate(searchResultDestination(item)))
  }

  private submitInput(): void {
    const query = this.input.trim();
    if (query.length === 0) {
      this.controller?.submit('');
      return;
    }
    this.input = query;
    this.controller?.submit(query);
  }

  private applyState(state: SearchViewState): void {
    this.phase = state.phase;
    this.query = state.query;
    this.items = state.items;
    this.loadingMore = state.loadingMore;
    this.canLoadMore = state.canLoadMore;
    this.requiresLogin = state.requiresLogin;
    this.errorMessage = state.errorMessage ?? '';
  }

  private openLogin(): void {
    this.navigate({ name: P1DestinationName.LOGIN });
  }
}

export function searchResultDestination(item: SearchResultItem): P1Destination {
  if (item.kind === FeedTargetKind.QUESTION) {
    return { name: P1DestinationName.QUESTION, id: item.contentId };
  }
  if (item.kind === FeedTargetKind.ANSWER) {
    return { name: P1DestinationName.ANSWER, id: item.contentId };
  }
  return { name: P1DestinationName.ARTICLE, id: item.contentId };
}

export function searchKindLabel(kind: FeedTargetKind): string {
  if (kind === FeedTargetKind.QUESTION) {
    return '问题';
  }
  if (kind === FeedTargetKind.ANSWER) {
    return '回答';
  }
  return '文章';
}

export function isSearchResultFilter(value: number): boolean {
  return value === SearchResultFilter.ALL || value === SearchResultFilter.QUESTION ||
    value === SearchResultFilter.ANSWER || value === SearchResultFilter.ARTICLE;
}

export function searchResultFilterLabel(filter: number): string {
  if (filter === SearchResultFilter.QUESTION) {
    return '问题';
  }
  if (filter === SearchResultFilter.ANSWER) {
    return '回答';
  }
  if (filter === SearchResultFilter.ARTICLE) {
    return '文章';
  }
  return '综合';
}

export function filterSearchResults(items: Array<SearchResultItem>, filter: number): Array<SearchResultItem> {
  if (filter === SearchResultFilter.QUESTION) {
    return items.filter((item: SearchResultItem): boolean => item.kind === FeedTargetKind.QUESTION);
  }
  if (filter === SearchResultFilter.ANSWER) {
    return items.filter((item: SearchResultItem): boolean => item.kind === FeedTargetKind.ANSWER);
  }
  if (filter === SearchResultFilter.ARTICLE) {
    return items.filter((item: SearchResultItem): boolean => item.kind === FeedTargetKind.ARTICLE);
  }
  return items.slice();
}
