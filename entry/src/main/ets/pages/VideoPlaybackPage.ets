import {
  UnavailableVideoSourceResolver,
  VideoPlaybackController,
  VideoPlaybackPageViewState,
  VideoPlayerAdapter,
  VideoSourceResolver
} from './VideoPlaybackController';
import { Api26VideoPlayerAdapter } from './Api26VideoPlayerAdapter';
import { VideoPlaybackPhase } from './VideoPlaybackState';
import { VideoRepository } from 'data';
import { RepositoryVideoSourceResolver } from './RepositoryVideoSourceResolver';
import { takeVideoPlaybackContext, VideoPlaybackContext } from './VideoPlaybackHandoff';
import { window } from '@kit.ArkUI';
import { getAbilityContext } from '../entryability/AbilityContextHolder';

const CONTROLS_HIDE_DELAY_MS: number = 3000;

@Component
export struct VideoPlaybackPage {
  contentId: string = '';
  sourceResolver: VideoSourceResolver | undefined = undefined;
  player: VideoPlayerAdapter | undefined = undefined;
  repository: VideoRepository | undefined = undefined;
  onBack: () => void = (): void => {};
  @State private viewState: VideoPlaybackPageViewState = {
    playback: { phase: VideoPlaybackPhase.IDLE, generation: 0, positionMs: 0, durationMs: 0 },
    message: '正在准备视频…'
  };
  @State private surfaceReady: boolean = false;
  @State private controlsVisible: boolean = true;
  @State private landscapeFullScreen: boolean = false;
  @StorageProp('statusBarHeight') private statusBarHeightVp: number = 0;
  private readonly surfaceController: XComponentController = new XComponentController();
  private controller: VideoPlaybackController | undefined = undefined;
  private appeared: boolean = false;
  private surfaceId: string = '';
  private playbackContext: VideoPlaybackContext | undefined = undefined;
  private controlsHideTimerId: number = -1;

  aboutToAppear(): void {
    this.appeared = true;
    if (this.playbackContext === undefined) {
      this.playbackContext = takeVideoPlaybackContext(this.contentId);
    }
    this.activateWhenSurfaceReady();
  }

  aboutToDisappear(): void {
    this.appeared = false;
    this.clearControlsHideTimer();
    this.restorePortraitDisplay();
    this.releaseController();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      XComponent({ id: 'p4_video_surface', type: XComponentType.SURFACE, controller: this.surfaceController })
        .id('p4_video_surface')
        .width('100%')
        .height('100%')
        .onLoad((): void => this.onSurfaceReady())
        .onDestroy((): void => this.onSurfaceDestroyed())
        .onClick((): void => this.toggleControls())
      if (!this.surfaceReady) {
        Text('正在初始化视频画面')
          .id('p4_video_surface_placeholder')
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
          .padding($r('app.float.p1_card_padding'))
          .align(Alignment.Center)
      }

      if (this.controlsVisible) {
        Column() {
          Row({ space: $r('app.float.p1_spacing_small') }) {
            Blank()
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph(this.landscapeFullScreen
                ? $r('sys.symbol.arrow_down_right_and_arrow_up_left')
                : $r('sys.symbol.arrow_up_left_and_arrow_down_right'))
                .fontSize(21)
                .fontColor([Color.White])
            }
              .id('p4_video_fullscreen')
              .width(44)
              .height(44)
              .padding(0)
              .backgroundColor('#80000000')
              .accessibilityText(this.landscapeFullScreen ? '退出横屏全屏' : '横屏全屏')
              .onClick((): void => this.toggleLandscapeFullScreen())
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(21)
                .fontColor([Color.White])
            }
              .id('p4_video_back')
              .width(44)
              .height(44)
              .padding(0)
              .backgroundColor('#80000000')
              .accessibilityText('退出播放')
              .onClick((): void => this.closePlayer())
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: Math.max(this.statusBarHeightVp, 0) + 12 })

          Blank()

          Row({ space: $r('app.float.p1_spacing_small') }) {
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph(this.viewState.playback.phase === VideoPlaybackPhase.PLAYING
                ? $r('sys.symbol.pause') : $r('sys.symbol.play_fill'))
                .fontSize(24)
                .fontColor([Color.White])
            }
              .id('p4_video_playback_toggle')
              .width(44)
              .height(44)
              .padding(0)
              .backgroundColor(Color.Transparent)
              .enabled(this.canTogglePlayback())
              .accessibilityText(this.playButtonLabel())
              .onClick((): void => this.togglePlayback())
            if (this.viewState.playback.durationMs > 0) {
              Slider({
                value: this.viewState.playback.positionMs,
                min: 0,
                max: this.viewState.playback.durationMs,
                step: 1000
              })
                .id('p4_video_playback_seek')
                .layoutWeight(1)
                .enabled(this.canSeek())
                .onChange((value: number): void => this.controller?.seek(Math.floor(value)))
              Text(`${this.formatDuration(this.viewState.playback.positionMs)} / ${this.formatDuration(this.viewState.playback.durationMs)}`)
                .id('p4_video_playback_progress')
                .fontSize($r('app.float.p1_secondary_font_size'))
                .fontColor(Color.White)
                .maxLines(1)
            }
          }
          .alignItems(VerticalAlign.Center)
          .width('100%')
          .padding({ left: 12, right: 16, top: 6, bottom: 6 })
          .margin({ left: 12, right: 12, bottom: 12 })
          .backgroundColor('#80000000')
          .borderRadius(24)
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }

      if (this.showPlaybackMessage()) {
        Text(this.viewState.message)
          .id('p4_video_playback_status')
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
          .padding({ left: 20, right: 20, top: 10, bottom: 10 })
          .backgroundColor('#80000000')
          .borderRadius(10)
          .align(Alignment.Center)
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }

  private togglePlayback(): void {
    if (this.viewState.playback.phase === VideoPlaybackPhase.PLAYING) {
      this.controller?.pause();
      return;
    }
    this.controller?.play();
  }

  private toggleControls(): void {
    this.controlsVisible = !this.controlsVisible;
    if (this.controlsVisible) {
      this.scheduleControlsHide();
    } else {
      this.clearControlsHideTimer();
    }
  }

  private showControls(): void {
    this.controlsVisible = true;
    this.scheduleControlsHide();
  }

  private scheduleControlsHide(): void {
    this.clearControlsHideTimer();
    if (this.viewState.playback.phase !== VideoPlaybackPhase.PLAYING) {
      return;
    }
    this.controlsHideTimerId = setTimeout((): void => {
      this.controlsHideTimerId = -1;
      if (this.viewState.playback.phase === VideoPlaybackPhase.PLAYING) {
        this.controlsVisible = false;
      }
    }, CONTROLS_HIDE_DELAY_MS);
  }

  private clearControlsHideTimer(): void {
    if (this.controlsHideTimerId >= 0) {
      clearTimeout(this.controlsHideTimerId);
      this.controlsHideTimerId = -1;
    }
  }

  private toggleLandscapeFullScreen(): void {
    this.applyLandscapeFullScreen(!this.landscapeFullScreen);
    this.showControls();
  }

  private applyLandscapeFullScreen(enabled: boolean): void {
    const mainWindow = getAbilityContext()?.windowStage?.getMainWindowSync();
    if (mainWindow === undefined) {
      return;
    }
    const orientation = enabled ? window.Orientation.LANDSCAPE : window.Orientation.PORTRAIT;
    mainWindow.setPreferredOrientation(orientation)
      .then((): Promise<void> => mainWindow.setWindowSystemBarEnable(
        enabled ? [] : ['status', 'navigation']))
      .then((): void => {
        this.landscapeFullScreen = enabled;
      })
      .catch((_error: Object): void => {
      });
  }

  private restorePortraitDisplay(): void {
    this.applyLandscapeFullScreen(false);
  }

  private closePlayer(): void {
    const mainWindow = getAbilityContext()?.windowStage?.getMainWindowSync();
    if (mainWindow === undefined) {
      this.onBack();
      return;
    }
    mainWindow.setPreferredOrientation(window.Orientation.PORTRAIT)
      .then((): Promise<void> => mainWindow.setWindowSystemBarEnable(['status', 'navigation']))
      .then((): void => this.onBack())
      .catch((_error: Object): void => this.onBack());
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
    const sourceResolver = this.resolveSourceResolver();
    const player = this.player ?? new Api26VideoPlayerAdapter(this.surfaceId);
    this.controller = new VideoPlaybackController(sourceResolver, player, (state: VideoPlaybackPageViewState): void => {
      const previousPhase = this.viewState.playback.phase;
      this.viewState = state;
      if (state.playback.phase === VideoPlaybackPhase.PLAYING) {
        if (previousPhase !== VideoPlaybackPhase.PLAYING) {
          this.scheduleControlsHide();
        }
      } else {
        this.clearControlsHideTimer();
        this.controlsVisible = true;
      }
    });
    this.controller.activate(this.contentId);
  }

  private resolveSourceResolver(): VideoSourceResolver {
    if (this.sourceResolver !== undefined) {
      return this.sourceResolver;
    }
    if (this.repository !== undefined && this.playbackContext !== undefined) {
      return new RepositoryVideoSourceResolver(this.repository, this.playbackContext);
    }
    return new UnavailableVideoSourceResolver();
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

  private showPlaybackMessage(): boolean {
    return this.viewState.playback.phase === VideoPlaybackPhase.IDLE ||
      this.viewState.playback.phase === VideoPlaybackPhase.PREPARING ||
      this.viewState.playback.phase === VideoPlaybackPhase.ERROR;
  }

  private formatDuration(value: number): string {
    const totalSeconds = Math.floor(value / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes}:${seconds < 10 ? '0' : ''}${seconds}`;
  }
}
