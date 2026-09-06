import { SearchSortOption, SearchTimeRange } from 'data';

/**
 * 搜索页 HDS 标题栏注入内容：返回键 + 搜索框 + 排序方式菜单。
 * 与 SearchPage 分属 HdsNavDestination 的 stackBuilder 与内容两棵子树，经 AppStorage 键通信
 * （同 questionTitleStates 模式）；键在 SearchPage aboutToAppear 初始化，仅一个搜索页活跃。
 */
export const SEARCH_INPUT_VALUE_KEY = 'searchInputValue';
export const SEARCH_SUBMIT_QUERY_KEY = 'searchSubmitQuery';
export const SEARCH_SUBMIT_TICK_KEY = 'searchSubmitTick';
export const SEARCH_FILTER_ENABLED_KEY = 'searchFilterEnabled';
export const SEARCH_SORT_OPTION_KEY = 'searchSortOption';
export const SEARCH_TIME_RANGE_KEY = 'searchTimeRange';
export const SEARCH_FILTER_TICK_KEY = 'searchFilterTick';
/** SearchPage 每次进入递增此键，标题栏据此强制清空输入框（TextInput 内部状态优先，外部 text 绑定不生效）。 */
export const SEARCH_INPUT_ENTRY_TICK_KEY = 'searchInputEntryTick';

export function publishSearchInputValue(value: string): void {
  AppStorage.setOrCreate(SEARCH_INPUT_VALUE_KEY, value);
}

export function publishSearchSubmit(query: string): void {
  AppStorage.setOrCreate(SEARCH_SUBMIT_QUERY_KEY, query);
  AppStorage.setOrCreate(SEARCH_SUBMIT_TICK_KEY, (AppStorage.get<number>(SEARCH_SUBMIT_TICK_KEY) ?? 0) + 1);
}

interface SearchMenuOption {
  readonly label: string;
  readonly value: string;
}

const SORT_OPTIONS: Array<SearchMenuOption> = [
  { label: '综合排序', value: SearchSortOption.DEFAULT },
  { label: '最新发布', value: SearchSortOption.LATEST },
  { label: '最多赞同', value: SearchSortOption.MOST_VOTED }
];

const TIME_RANGE_OPTIONS: Array<SearchMenuOption> = [
  { label: '不限时间', value: SearchTimeRange.ALL },
  { label: '一天内', value: SearchTimeRange.DAY },
  { label: '一周内', value: SearchTimeRange.WEEK },
  { label: '一个月内', value: SearchTimeRange.MONTH },
  { label: '三个月内', value: SearchTimeRange.THREE_MONTHS },
  { label: '半年内', value: SearchTimeRange.HALF_YEAR },
  { label: '一年内', value: SearchTimeRange.YEAR }
];

@Component
export struct SearchTitleBar {
  // @StorageProp 键用字面量（装饰器要求编译期常量），值与上方导出的常量一一对应。
  // TextInput 组件状态为内部优先，外部 text 绑定对已挂载实例（标题栏节点复用）不强制更新；
  // 重进页面时用 controller.deleteText() 强制清空旧输入。
  private readonly textController: TextInputController = new TextInputController();
  @StorageProp('searchInputValue') private inputValue: string = '';
  @StorageProp('searchInputEntryTick') @Watch('onEntryTick') private entryTick: number = 0;
  @StorageProp('searchFilterEnabled') private filterEnabled: boolean = false;
  @State private menuVisible: boolean = false;
  @StorageProp('searchSortOption') private sortOption: string = SearchSortOption.DEFAULT;
  @StorageProp('searchTimeRange') private timeRange: string = SearchTimeRange.ALL;
  private lastEntryTick: number = -1;

  private onEntryTick(): void {
    this.resetForEntry();
  }

  private writeInput(value: string): void {
    publishSearchInputValue(value);
  }

  /** 页面重进（SearchPage 递增 entryTick）时强制清空输入框，防止上次搜索内容残留。 */
  private resetForEntry(): void {
    if (this.entryTick === this.lastEntryTick) {
      return;
    }
    this.lastEntryTick = this.entryTick;
    this.textController.deleteText();
    publishSearchInputValue('');
  }

  private selectOption(key: string, value: string): void {
    AppStorage.setOrCreate(key, value);
    AppStorage.setOrCreate(SEARCH_FILTER_TICK_KEY,
      (AppStorage.get<number>(SEARCH_FILTER_TICK_KEY) ?? 0) + 1);
    this.menuVisible = false;
  }

  private submitInput(): void {
    const query = this.inputValue.trim();
    if (query.length === 0) {
      return;
    }
    publishSearchSubmit(query);
  }

  @Builder
  private menuSection(title: string, options: Array<SearchMenuOption>, selected: string, key: string) {
    Text(title)
      .fontSize(12)
      .fontColor($r('app.color.secondary_text'))
      .padding({ left: 16, right: 16, top: 8, bottom: 4 })
    ForEach(options, (option: SearchMenuOption) => {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([$r('app.color.brand_primary')])
          .opacity(option.value === selected ? 1 : 0)
        Text(option.label)
          .fontSize(14)
          .fontColor($r('app.color.primary_text'))
      }
      .width('100%')
      .padding({ left: 16, right: 24, top: 10, bottom: 10 })
      .onClick((): void => this.selectOption(key, option.value))
    }, (option: SearchMenuOption): string => `${option.value}`)
  }

  @Builder
  private filterMenu() {
    Column() {
      this.menuSection('排序', SORT_OPTIONS, this.sortOption, SEARCH_SORT_OPTION_KEY)
      Divider().color($r('app.color.control_background')).margin({ top: 4, bottom: 4 })
      this.menuSection('时间范围', TIME_RANGE_OPTIONS, this.timeRange, SEARCH_TIME_RANGE_KEY)
    }
    .width(180)
    .backgroundColor($r('app.color.surface_background'))
    .borderRadius($r('app.float.p1_card_radius'))
  }

  build() {
    Row({ space: 8 }) {
      // 返回键由 HDS 标题栏默认 backIcon 承载（P1Shell 传入 action），这里从其右侧起排，
      // 避免自绘返回键与默认返回键重叠（28vp 错位的双箭头）。
      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(18)
          .fontColor([$r('app.color.secondary_text')])
        TextInput({ text: this.inputValue, placeholder: '搜索知乎内容', controller: this.textController })
          .id('p2_search_input')
          .layoutWeight(1)
          .fontSize($r('app.float.p1_body_font_size'))
          .maxLength(200)
          .enterKeyType(EnterKeyType.Search)
          .backgroundColor(Color.Transparent)
          .padding(0)
          .onChange((value: string): void => {
            this.writeInput(value);
          })
          .onSubmit((): void => {
            this.submitInput();
          })

        if (this.inputValue.length > 0) {
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(14)
              .fontColor([$r('app.color.secondary_text')])
          }
          .id('p2_search_clear')
          .width(28)
          .height(28)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText('清除搜索内容')
          .onClick((): void => {
            this.writeInput('');
          })
        }
      }
      .id('p2_search_input_container')
      .layoutWeight(1)
      .height(40)
      .padding({ left: 12, right: 6 })
      .backgroundColor($r('app.color.control_background'))
      .borderRadius(20)
      .alignItems(VerticalAlign.Center)

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.line_3_horizontal'))
          .fontSize(20)
          .fontColor([$r('app.color.primary_text')])
          .opacity(this.filterEnabled ? 1 : 0.35)
      }
      .id('p2_search_filter')
      .width(40)
      .height(40)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .enabled(this.filterEnabled)
      .accessibilityText('排序方式')
      .onClick((): void => {
        this.menuVisible = !this.menuVisible;
      })
      .bindMenu(this.menuVisible, this.filterMenu())
    }
    .id('p2_search_title_bar')
    .width('100%')
    .height(48)
    // 左侧 64vp 让出 HDS 默认返回键的区域（实测 36/48 会压到其触摸区）。
    .padding({ left: 64, right: 8 })
    .alignItems(VerticalAlign.Center)
    .onAppear((): void => {
      this.resetForEntry();
    })
  }
}
