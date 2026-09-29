import { onThemeColor, DailyStoryRepository, DEFAULT_THEME_COLOR, DefaultDailyStoryRepository } from 'data';
import { AppDestination } from 'core';
import {
  DailyStoryDetailController,
  DailyStoryDetailPhase,
  DailyStoryDetailViewState
} from './DailyStoryDetailState';

@Component
export struct DailyStoryDetailPage {
  storyId: string = '';
  repository: DailyStoryRepository | undefined = new DefaultDailyStoryRepository();
  navigate: (destination: AppDestination) => void = (_destination: AppDestination): void => {
  };
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @State private phase: DailyStoryDetailPhase = DailyStoryDetailPhase.IDLE;
  @State private errorMessage: string = '';
  private destination?: AppDestination;
  private controller?: DailyStoryDetailController;
  private navigated: boolean = false;

  aboutToAppear(): void {
    // P3-7：返回栈重显（页面实例与状态保留）时 aboutToAppear 可能再次触发；
    // 控制器仍存活时直接复用，避免重建控制器并重载正文导致滚动位置丢失。
    if (this.controller !== undefined) {
      this.controller.activate();
      return;
    }
    const repository = this.repository;
    if (repository === undefined) {
      this.phase = DailyStoryDetailPhase.ERROR;
      this.errorMessage = '日报正文数据源未配置';
      return;
    }
    this.navigated = false;
    this.controller = new DailyStoryDetailController(repository,
      (state: DailyStoryDetailViewState): void => this.applyState(state));
    this.controller.activate();
    this.controller.load(this.storyId);
  }

  aboutToDisappear(): void {
    this.controller?.deactivate();
    this.controller = undefined;
  }

  build() {
    Column({ space: $r('app.float.spacing_medium') }) {
      if (this.phase === DailyStoryDetailPhase.IDLE || this.phase === DailyStoryDetailPhase.LOADING) {
        LoadingProgress()
          .id('daily_story_loading_progress')
          .width(40)
          .height(40)
          .color(this.resolvedThemeColor)
        Text('正在打开日报原文…')
          .id('daily_story_loading_status')
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.secondary_text'))
      } else if (this.phase === DailyStoryDetailPhase.READY) {
        Text('正在进入知乎正文…')
          .id('daily_story_ready_status')
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.secondary_text'))
      } else {
        Text(this.errorMessage)
          .id('daily_story_error_status')
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .textAlign(TextAlign.Center)
        Button('重新加载')
          .backgroundColor(this.resolvedThemeColor)
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .id('daily_story_retry')
          .onClick((): void => {
            this.controller?.load(this.storyId);
          })
      }
    }
    .id('daily_story_detail_page')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .height('100%')
    .padding($r('app.float.page_padding'))
    .backgroundColor($r('app.color.page_background'))
  }

  private applyState(state: DailyStoryDetailViewState): void {
    this.phase = state.phase;
    this.errorMessage = state.errorMessage ?? '';
    this.destination = state.destination;
    if (!this.navigated && this.destination !== undefined) {
      this.navigated = true;
      this.navigate(this.destination);
    }
  }
}
