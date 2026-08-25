import {
  UnavailableVideoSourceResolver,
  VideoPlaybackController,
  VideoPlaybackPageViewState,
  VideoPlayerAdapter,
  VideoSourceResolver
} from './VideoPlaybackController';
import { Api26VideoPlayerAdapter } from './Api26VideoPlayerAdapter';
import { VideoPlaybackPhase } from './VideoPlaybackState';

@Component
export struct VideoPlaybackPage {
  contentId: string = '';
  sourceResolver: VideoSourceResolver | undefined = undefined;
  player: VideoPlayerAdapter | undefined = undefined;
  @State private viewState: VideoPlaybackPageViewState = {
    playback: { phase: VideoPlaybackPhase.IDLE, generation: 0, positionMs: 0, durationMs: 0 },
    message: '正在准备视频…'
  };
  @State private surfaceReady: boolean = false;
  private readonly surfaceController: XComponentController = new XComponentController();
  private controller: VideoPlaybackController | undefined = undefined;
  private appeared: boolean = false;
  private surfaceId: string = '';

  aboutToAppear(): void {
    this.appeared = true;
    this.activateWhenSurfaceReady();
  }

  aboutToDisappear(): void {
    this.appeared = false;
    this.releaseController();
  }

  build() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Stack({ alignContent: Alignment.Center }) {
        XComponent({ id: 'p4_video_surface', type: XComponentType.SURFACE, controller: this.surfaceController })
          .id('p4_video_surface')
          .width('100%')
          .height('100%')
          .onLoad((): void => this.onSurfaceReady())
          .onDestroy((): void => this.onSurfaceDestroyed())
        if (!this.surfaceReady) {
          Text('正在初始化视频画面')
            .id('p4_video_surface_placeholder')
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .textAlign(TextAlign.Center)
            .padding($r('app.float.p1_card_padding'))
        }
      }
      .width('100%')
      .height(220)
      .borderRadius($r('app.float.p1_card_radius'))
      .backgroundColor($r('app.color.surface_background'))

      Text(`视频 ID：${this.contentId}`)
        .id('p4_video_content_id')
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))

      Text(this.viewState.message)
        .id('p4_video_playback_status')
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.primary_text'))

      if (this.viewState.playback.durationMs > 0) {
        Text(`${this.formatDuration(this.viewState.playback.positionMs)} / ${this.formatDuration(this.viewState.playback.durationMs)}`)
          .id('p4_video_playback_progress')
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
        Slider({
          value: this.viewState.playback.positionMs,
          min: 0,
          max: this.viewState.playback.durationMs,
          step: 1000
        })
          .id('p4_video_playback_seek')
          .width('100%')
          .enabled(this.canSeek())
          .onChange((value: number): void => this.controller?.seek(Math.floor(value)))
      }

      Button(this.playButtonLabel())
        .id('p4_video_playback_toggle')
        .width('100%')
        .fontSize($r('app.float.p1_body_font_size'))
        .enabled(this.canTogglePlayback())
        .onClick((): void => this.togglePlayback())
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .padding($r('app.float.p1_card_padding'))
    .backgroundColor($r('app.color.page_background'))
  }

  private togglePlayback(): void {
    if (this.viewState.playback.phase === VideoPlaybackPhase.PLAYING) {
      this.controller?.pause();
      return;
    }
    this.controller?.play();
  }

  private onSurfaceReady(): void {
    const surfaceId = this.surfaceController.getXComponentSurfaceId();
    if (surfaceId.length === 0) {
      return;
    }
    this.surfaceId = surfaceId;
    this.surfaceReady = true;
    this.activateWhenSurfaceReady();
  }

  private onSurfaceDestroyed(): void {
    this.surfaceReady = false;
    this.surfaceId = '';
    this.releaseController();
  }

  private activateWhenSurfaceReady(): void {
    if (!this.appeared || !this.surfaceReady || this.controller !== undefined) {
      return;
    }
    const sourceResolver = this.sourceResolver ?? new UnavailableVideoSourceResolver();
    const player = this.player ?? new Api26VideoPlayerAdapter(this.surfaceId);
    this.controller = new VideoPlaybackController(sourceResolver, player, (state: VideoPlaybackPageViewState): void => {
      this.viewState = state;
    });
    this.controller.activate(this.contentId);
  }

  private releaseController(): void {
    this.controller?.deactivate();
    this.controller = undefined;
  }

  private playButtonLabel(): string {
    return this.viewState.playback.phase === VideoPlaybackPhase.PLAYING ? '暂停' : '播放';
  }

  private canTogglePlayback(): boolean {
    return this.viewState.playback.phase === VideoPlaybackPhase.READY ||
      this.viewState.playback.phase === VideoPlaybackPhase.PLAYING ||
      this.viewState.playback.phase === VideoPlaybackPhase.PAUSED;
  }

  private canSeek(): boolean {
    return this.viewState.playback.phase === VideoPlaybackPhase.PLAYING;
  }

  private formatDuration(value: number): string {
    const totalSeconds = Math.floor(value / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes}:${seconds < 10 ? '0' : ''}${seconds}`;
  }
}
