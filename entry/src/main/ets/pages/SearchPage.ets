import { P1Destination, P1DestinationName } from 'core';
import { FeedTargetKind, SearchRepository, SearchResultItem, searchResultIdentity } from 'data';
import { SearchController, SearchPhase, SearchViewState } from './SearchState';

@Component
export struct SearchPage {
  initialQuery: string = '';
  repository: SearchRepository | undefined = undefined;
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {
  };
  @State private input: string = '';
  @State private phase: SearchPhase = SearchPhase.IDLE;
  @State private query: string = '';
  @State private items: Array<SearchResultItem> = [];
  @State private loadingMore: boolean = false;
  @State private canLoadMore: boolean = false;
  @State private requiresLogin: boolean = false;
  @State private errorMessage: string = '';
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
        TextInput({ text: this.input, placeholder: '搜索知乎内容' })
          .id('p2_search_input')
          .layoutWeight(1)
          .fontSize($r('app.float.p1_body_font_size'))
          .maxLength(200)
          .enterKeyType(EnterKeyType.Search)
          .onChange((value: string) => {
            this.input = value;
          })
          .onSubmit(() => {
            this.submitInput();
          })

        if (this.input.length > 0) {
          Button('清除')
            .id('p2_search_clear')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .onClick(() => {
              this.input = '';
              this.controller?.submit('');
            })
        }

      }
      .id('p2_search_input_row')
      .width('100%')

      Button('搜索')
        .id('p2_search_submit')
        .width('100%')
        .fontSize($r('app.float.p1_body_font_size'))
        .enabled(this.input.trim().length > 0 &&
          (this.phase !== SearchPhase.LOADING || this.input.trim() !== this.query))
        .onClick(() => {
          this.submitInput();
        })

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

        List() {
          ForEach(this.items, (item: SearchResultItem) => {
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

        Text(item.title)
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .width('100%')

        if (item.excerpt.trim().length > 0) {
          Text(item.excerpt)
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
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
