import { Want } from '@kit.AbilityKit';
import { P1Destination, P1DestinationName, isSafePeopleIdentifier } from 'core';
import {
  AppPreferencesStore,
  SEARCH_HISTORY_MAX_SIZE,
  FeedTargetKind,
  SearchEntity,
  SearchEntityKind,
  SearchHotItem,
  SearchPersonItem,
  SearchRepository,
  isContentSearchTab,
  SearchSortOption,
  SearchTab,
  SearchTimeRange,
  SearchTopicItem,
  SearchResultItem
} from 'data';
import { getAbilityContext } from '../entryability/AbilityContextHolder';
import { SearchController, SearchPhase, SearchViewState } from './SearchState';
import {
  SEARCH_FILTER_ENABLED_KEY,
  SEARCH_FILTER_TICK_KEY,
  SEARCH_INPUT_ENTRY_TICK_KEY,
  SEARCH_INPUT_VALUE_KEY,
  SEARCH_SORT_OPTION_KEY,
  SEARCH_SUBMIT_QUERY_KEY,
  SEARCH_SUBMIT_TICK_KEY,
  SEARCH_TIME_RANGE_KEY
} from './SearchTitleBar';

interface EmphasisPart {
  text: string;
  emphasized: boolean;
}

const SEARCH_TABS: Array<SearchTab> = [
  SearchTab.GENERAL,
  SearchTab.PEOPLE,
  SearchTab.ANSWER,
  SearchTab.ARTICLE,
  SearchTab.TOPIC
];

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

function stripEmphasis(text: string): string {
  return splitEmphasis(text).map((part: EmphasisPart): string => part.text).join('');
}

export function searchTabLabel(tab: SearchTab): string {
  if (tab === SearchTab.PEOPLE) {
    return '用户';
  }
  if (tab === SearchTab.ANSWER) {
    return '回答';
  }
  if (tab === SearchTab.ARTICLE) {
    return '文章';
  }
  if (tab === SearchTab.TOPIC) {
    return '话题';
  }
  return '综合';
}

@Component
export struct SearchPage {
  initialQuery: string = '';
  repository: SearchRepository | undefined = undefined;
  preferences: AppPreferencesStore | undefined = undefined;
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {
  };
  onBack: () => void = (): void => {
  };
  @State private phase: SearchPhase = SearchPhase.IDLE;
  @State private query: string = '';
  @State private entities: Array<SearchEntity> = [];
  @State private activeTabIndex: number = 0;
  @State private loadingMore: boolean = false;
  @State private canLoadMore: boolean = false;
  @State private requiresLogin: boolean = false;
  @State private errorMessage: string = '';
  @State private history: Array<string> = [];
  @State private hotItems: Array<SearchHotItem> = [];
  // @StorageProp 键用字面量（装饰器要求编译期常量），值与 SearchTitleBar 导出的常量一一对应。
  @StorageProp('searchSubmitTick') @Watch('onSubmitTick') private submitTick: number = 0;
  @StorageProp('searchFilterTick') @Watch('onFilterTick') private filterTick: number = 0;
  private controller?: SearchController;
  private lastSubmitTick: number = -1;
  private lastFilterTick: number = -1;

  aboutToAppear(): void {
    this.lastSubmitTick = AppStorage.get<number>(SEARCH_SUBMIT_TICK_KEY) ?? 0;
    this.lastFilterTick = AppStorage.get<number>(SEARCH_FILTER_TICK_KEY) ?? 0;
    AppStorage.setOrCreate(SEARCH_INPUT_VALUE_KEY, this.initialQuery);
    // 每次进入递增 entryTick，标题栏据此强制清空输入框（TextInput 内部状态不随外部 text 更新）。
    AppStorage.setOrCreate(SEARCH_INPUT_ENTRY_TICK_KEY,
      (AppStorage.get<number>(SEARCH_INPUT_ENTRY_TICK_KEY) ?? 0) + 1);
    AppStorage.setOrCreate(SEARCH_FILTER_ENABLED_KEY, false);
    AppStorage.setOrCreate(SEARCH_SORT_OPTION_KEY, SearchSortOption.DEFAULT);
    AppStorage.setOrCreate(SEARCH_TIME_RANGE_KEY, SearchTimeRange.ALL);
    if (this.repository === undefined) {
      return;
    }
    this.controller = new SearchController(this.repository, (state: SearchViewState): void => {
      this.applyState(state);
    });
    this.controller.activate();
    if (this.initialQuery.trim().length > 0) {
      this.controller.submit(this.initialQuery);
    } else {
      void this.loadHistory();
      void this.loadHotSearch();
    }
  }

  aboutToDisappear(): void {
    this.controller?.deactivate();
  }

  private onSubmitTick(): void {
    const tick = AppStorage.get<number>(SEARCH_SUBMIT_TICK_KEY) ?? 0;
    if (tick === this.lastSubmitTick) {
      return;
    }
    this.lastSubmitTick = tick;
    const query = AppStorage.get<string>(SEARCH_SUBMIT_QUERY_KEY) ?? '';
    this.performSubmit(query);
  }

  private onFilterTick(): void {
    const tick = AppStorage.get<number>(SEARCH_FILTER_TICK_KEY) ?? 0;
    if (tick === this.lastFilterTick) {
      return;
    }
    this.lastFilterTick = tick;
    const sort = AppStorage.get<string>(SEARCH_SORT_OPTION_KEY) ?? SearchSortOption.DEFAULT;
    const timeRange = AppStorage.get<string>(SEARCH_TIME_RANGE_KEY) ?? SearchTimeRange.ALL;
    void this.controller?.updateFilters(sort as SearchSortOption, timeRange as SearchTimeRange);
  }

  private async loadHistory(): Promise<void> {
    if (this.preferences === undefined) {
      return;
    }
    try {
      this.history = await this.preferences.loadSearchHistory();
    } catch (_error) {
      // 历史读取失败按空历史展示，不阻塞搜索主流程。
    }
  }

  private async loadHotSearch(): Promise<void> {
    if (this.repository === undefined) {
      return;
    }
    try {
      this.hotItems = (await this.repository.hotSearch()).slice(0, 15);
    } catch (_error) {
      this.hotItems = [];
    }
  }

  private recordHistory(query: string): void {
    if (this.preferences === undefined) {
      return;
    }
    const next: Array<string> = [query].concat(
      this.history.filter((item: string): boolean => item !== query)).slice(0, SEARCH_HISTORY_MAX_SIZE);
    this.history = next;
    this.preferences.saveSearchHistory(next).catch((_error: Object): void => {
    });
  }

  private performSubmit(rawQuery: string): void {
    const query = rawQuery.trim();
    if (query.length === 0) {
      this.controller?.submit('');
      return;
    }
    AppStorage.setOrCreate(SEARCH_INPUT_VALUE_KEY, query);
    this.recordHistory(query);
    this.activeTabIndex = 0;
    void this.controller?.submit(query);
  }

  private clearHistory(): void {
    this.history = [];
    this.preferences?.saveSearchHistory([]).catch((_error: Object): void => {
    });
  }

  private applyState(state: SearchViewState): void {
    this.phase = state.phase;
    this.query = state.query;
    this.entities = state.entities;
    this.loadingMore = state.loadingMore;
    this.canLoadMore = state.canLoadMore;
    this.requiresLogin = state.requiresLogin;
    this.errorMessage = state.errorMessage ?? '';
    const tabIndex = SEARCH_TABS.indexOf(state.activeTab);
    if (tabIndex >= 0) {
      this.activeTabIndex = tabIndex;
    }
    // 排序菜单只在有结果时可用（含加载更多失败回退的 READY 态）。
    AppStorage.setOrCreate(SEARCH_FILTER_ENABLED_KEY, state.phase === SearchPhase.READY && isContentSearchTab(state.activeTab));
    AppStorage.setOrCreate(SEARCH_SORT_OPTION_KEY, state.sort);
    AppStorage.setOrCreate(SEARCH_TIME_RANGE_KEY, state.timeRange);
  }

  build() {
    Column() {
      if (this.repository === undefined) {
        this.statusPanel('搜索数据源未配置', false, 'p2_search_unconfigured');
      } else if (this.query.length === 0 && this.phase === SearchPhase.IDLE) {
        this.idlePanel();
      } else {
        if (this.query.length > 0) {
          this.resultTabs();
        }
        if (this.phase === SearchPhase.LOADING) {
          this.statusPanel('正在搜索…', false, 'p2_search_loading');
        } else if (this.phase === SearchPhase.ERROR) {
          this.statusPanel(this.errorMessage, true, 'p2_search_error');
        } else if (this.phase === SearchPhase.EMPTY) {
          this.statusPanel('没有找到可显示的相关结果', false, 'p2_search_empty');
        } else {
          this.resultList();
        }
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .padding({
      left: $r('app.float.p1_page_padding'),
      right: $r('app.float.p1_page_padding'),
      // 94vp 为标题栏（stackBuilder 注入的搜索框行）叠加预留，对齐详情页约定。
      top: 94,
      bottom: $r('app.float.p1_page_padding')
    })
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private idlePanel() {
    Scroll() {
      Column() {
        if (this.history.length > 0) {
          Row() {
            Text('搜索历史')
              .fontSize($r('app.float.p1_body_font_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.secondary_text'))
            Blank()
            Button({ type: ButtonType.Normal, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.ellipsis_circle'))
                .fontSize(18)
                .fontColor([$r('app.color.secondary_text')])
            }
            .id('p2_search_history_more')
            .width(36)
            .height(36)
            .padding(0)
            .backgroundColor(Color.Transparent)
            .accessibilityText('搜索历史选项')
            .bindMenu([{
              value: '清空搜索历史',
              action: (): void => {
                this.clearHistory();
              }
            } as MenuElement])
          }
          .width('100%')
          .margin({ top: 8 })

          ForEach(this.history, (item: string) => {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.magnifyingglass'))
                .fontSize(16)
                .fontColor([$r('app.color.secondary_text')])
              Text(item)
                .fontSize($r('app.float.p1_body_font_size'))
                .fontColor($r('app.color.primary_text'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .id(`p2_search_history_${item}`)
            .width('100%')
            .height(40)
            .onClick((): void => this.performSubmit(item))
          }, (item: string): string => item)

          Divider()
            .color($r('app.color.control_background'))
            .margin({ top: 12, bottom: 12 })
        }

        Row() {
          Text('热搜')
            .fontSize($r('app.float.p1_body_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.secondary_text'))
          Blank()
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(18)
              .fontColor([$r('app.color.secondary_text')])
          }
          .id('p2_search_hot_refresh')
          .width(36)
          .height(36)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText('刷新热搜')
          .onClick((): void => {
            void this.loadHotSearch();
          })
        }
        .width('100%')

        if (this.hotItems.length === 0) {
          Text('暂无热搜内容')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
            .padding(12)
        } else {
          ForEach(this.hotItems, (item: SearchHotItem, index: number) => {
            Row({ space: 8 }) {
              Text(`${index + 1}`)
                .fontSize($r('app.float.p1_body_font_size'))
                .fontColor(index < 3 ? $r('app.color.error_text') : $r('app.color.secondary_text'))
                .width(24)
              Text(item.query)
                .fontSize($r('app.float.p1_body_font_size'))
                .fontColor($r('app.color.primary_text'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              if (item.hotShow.length > 0) {
                Text(item.hotShow)
                  .fontSize($r('app.float.p1_secondary_font_size'))
                  .fontColor($r('app.color.secondary_text'))
              }
            }
            .id(`p2_search_hot_${index}`)
            .width('100%')
            .height(40)
            .onClick((): void => this.performSubmit(item.query))
          }, (item: SearchHotItem, index: number): string => `${index}:${item.query}`)
        }

        if (this.history.length === 0 && this.hotItems.length === 0) {
          Text('暂无搜索历史，输入关键词搜索后会保存在这里')
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
            .padding(12)
        }
      }
      .width('100%')
    }
    .id('p2_search_idle_panel')
    .width('100%')
    .layoutWeight(1)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }

  @Builder
  private resultTabs() {
    Tabs({ barPosition: BarPosition.Start, index: this.activeTabIndex }) {
      ForEach(SEARCH_TABS, (tab: SearchTab) => {
        TabContent() {
          Column() {
            Blank();
          }
        }
        .tabBar(searchTabLabel(tab))
      }, (tab: SearchTab): string => tab)
    }
    .id('p2_search_result_tabs')
    .width('100%')
    .height(44)
    .barHeight(44)
    .barMode(BarMode.Scrollable)
    .scrollable(false)
    .onChange((index: number): void => {
      if (index >= 0 && index < SEARCH_TABS.length) {
        this.activeTabIndex = index;
        void this.controller?.selectTab(SEARCH_TABS[index]);
      }
    })
  }

  @Builder
  private resultList() {
    List() {
      ForEach(this.entities, (entity: SearchEntity) => {
        ListItem() {
          if (entity.kind === SearchEntityKind.CONTENT && entity.content !== undefined) {
            this.resultCard(entity.content);
          } else if (entity.kind === SearchEntityKind.PERSON && entity.person !== undefined) {
            this.personRow(entity.person);
          } else if (entity.kind === SearchEntityKind.TOPIC && entity.topic !== undefined) {
            this.topicRow(entity.topic);
          }
        }
        .margin({ top: $r('app.float.p1_spacing_medium') })
      }, (entity: SearchEntity): string => entity.id)

      if (this.loadingMore || this.canLoadMore) {
        ListItem() {
          Button(this.loadingMore ? '正在加载更多…' : '加载更多')
            .id('p2_search_load_more')
            .width('100%')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .enabled(!this.loadingMore)
            .onClick(() => this.controller?.loadMore())
        }
        .margin({ top: $r('app.float.p1_spacing_medium') })
      }
    }
    .id('p2_search_result_list')
    .width('100%')
    .scrollBar(BarState.Off)
    .layoutWeight(1)
    .edgeEffect(EdgeEffect.Spring)
    .onReachEnd(() => this.controller?.loadMore())
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
            Text(stripEmphasis(item.authorName))
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
    .accessibilityText(`打开${searchKindLabel(item.kind)}：${stripEmphasis(item.title)}`)
    .onClick(() => this.navigate(searchResultDestination(item)))
  }

  @Builder
  private personRow(item: SearchPersonItem) {
    Row({ space: 12 }) {
      if (item.avatarUrl !== undefined && item.avatarUrl.length > 0) {
        Image(item.avatarUrl)
          .width(48)
          .height(48)
          .borderRadius(24)
          .objectFit(ImageFit.Cover)
      }
      Column({ space: 4 }) {
        this.highlightedText(item.name, $r('app.float.p1_heading_font_size'),
          $r('app.color.primary_text'), FontWeight.Medium)
        if (item.headline.length > 0) {
          Text(item.headline)
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        Text(`${item.followerCount} 粉丝 · ${item.answerCount} 回答`)
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .id(`p2_search_person_${item.id}`)
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .accessibilityText(`打开用户主页：${stripEmphasis(item.name)}`)
    .onClick(() => this.openPerson(item))
  }

  @Builder
  private topicRow(item: SearchTopicItem) {
    Row({ space: 12 }) {
      if (item.avatarUrl !== undefined && item.avatarUrl.length > 0) {
        Image(item.avatarUrl)
          .width(48)
          .height(48)
          .borderRadius(24)
          .objectFit(ImageFit.Cover)
      }
      Column({ space: 4 }) {
        this.highlightedText(item.name, $r('app.float.p1_heading_font_size'),
          $r('app.color.primary_text'), FontWeight.Medium)
        if (item.excerpt.length > 0) {
          Text(stripEmphasis(item.excerpt))
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        Text(`${formatSearchCount(item.visitCount)} 浏览 · ${formatSearchCount(item.discussCount)} 讨论`)
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .id(`p2_search_topic_${item.id}`)
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .accessibilityText(`在浏览器打开话题：${stripEmphasis(item.name)}`)
    .onClick(() => this.openTopicInBrowser(item))
  }

  private openPerson(item: SearchPersonItem): void {
    const identifier = isSafePeopleIdentifier(item.id) ? item.id :
      (item.urlToken !== undefined && isSafePeopleIdentifier(item.urlToken) ? item.urlToken : undefined);
    if (identifier === undefined) {
      return;
    }
    this.navigate({ name: P1DestinationName.PEOPLE, id: identifier });
  }

  private async openTopicInBrowser(item: SearchTopicItem): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined || !/^[A-Za-z0-9_-]{1,64}$/.test(item.id)) {
      return;
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: `https://www.zhihu.com/topic/${item.id}`
    };
    try {
      await context.startAbility(want);
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: '暂时无法打开话题页面' });
    }
  }

  private openLogin(): void {
    this.navigate({ name: P1DestinationName.LOGIN });
  }
}

function formatSearchCount(value: number): string {
  if (value >= 100000000) {
    return `${(value / 100000000).toFixed(1)} 亿`;
  }
  if (value >= 10000) {
    return `${(value / 10000).toFixed(1)} 万`;
  }
  return `${value}`;
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
