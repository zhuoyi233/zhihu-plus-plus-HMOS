/**
 * 正文右缘可拖动阅读进度条，行为对齐上游 `VerticalReadingProgressBar.kt`：
 * 拇指高度 = 视口² / 内容高（下限 24vp），拇指位移 = (视口 − 拇指高) × 进度，
 * 轨道区 12vp 宽内 2vp 轨道 + 4vp 拇指，滚动/拖动停止 1200ms 后淡出
 * （出现 120ms / 消失 260ms 动画）。
 *
 * 与上游的差异：
 * - ArkUI 的 `Scroller` 没有读取最大滚动距离的 API（SDK 核查结论见
 *   `docs/upstream-typography-settings-implementation.md` §4），内容总高由宿主
 *   `NativeContentDocument` 估算并在触底时校准后经 `contentHeightVp` 传入。
 * - 上游 `alpha == 0` 时整棵子树不参与渲染;此处节点常驻,视觉靠 `opacity`、
 *   命中测试靠 `hitTestBehavior`(隐藏时 `HitTestMode.None`,右缘手势完整交回正文)。
 *   不按可见性把节点摘出渲染树:实测用 `Visibility.None` 隐藏后,再次显示时右缘触摸
 *   仍收不到(`onTouch` 全程无回调、事件全部落到正文列表),轨道区拖动因此失效。
 * - 判定"是否在场"须用非动画量: `animateTo` 起始帧 `@State alpha` 即已归零,
 *   直接拿它判定会让 260ms 淡出瞬间消失,故单独用 `mounted` 记录。
 *
 * 拖动：整个 12vp 轨道区挂 `PanGesture`，累加位移换算进度后直接 `scrollTo` 回写正文滚动；
 * ArkUI 无 Compose 的 `startDragImmediately`，PanGesture 的 5vp 起手距离等价于"按下即算"。
 */
const FADE_OUT_DELAY_MS = 1200;
/** 出现/消失动画时长（对齐上游 tween 120ms / 260ms）。 */
const APPEAR_DURATION_MS = 120;
const DISAPPEAR_DURATION_MS = 260;
/** 拇指高度下限（对齐上游 minThumbHeight = 24.dp）。 */
const MIN_THUMB_HEIGHT_VP = 24;
/** 轨道命中区宽度（上游 12.dp）、轨道条宽与拇指宽（上游 2.dp / 4.dp）。 */
export const READING_PROGRESS_BAR_HIT_WIDTH_VP = 12;
/** 轨道右侧留白（vp）：宿主按此宽度把进度条置于正文右缘。 */
export const READING_PROGRESS_BAR_RIGHT_INSET_VP = 2;
const TRACK_BAR_WIDTH_VP = 2;
const THUMB_WIDTH_VP = 4;
/** 低于该可滚动量视为无滚动，避免亚像素抖动把进度条闪出来。 */
const MIN_SCROLLABLE_VP = 1;

function clampUnit(value: number): number {
  return Math.min(1, Math.max(0, value));
}

@Component
export struct ReadingProgressBar {
  /** 与正文 List 共享的滚动控制器：拖动时直接回写滚动位置。 */
  scroller: Scroller = new Scroller();
  /** 正文视口高度（vp）：宿主 List 的 onAreaChange 回填。 */
  @Prop @Watch('onBarInputChanged') viewportHeightVp: number = 0;
  /** 正文内容总高（vp）：宿主估算值 + 触底校准值。 */
  @Prop @Watch('onBarInputChanged') contentHeightVp: number = 0;
  /** 正文当前滚动偏移（vp）：宿主 onDidScroll 每帧回填。 */
  @Prop @Watch('onBarInputChanged') scrollYVp: number = 0;
  /** 轨道上下留白：避开页顶栏与底部悬浮操作栏，由宿主按页面布局给定。 */
  @Prop topInsetVp: number = 4;
  @Prop bottomInsetVp: number = 96;
  /**
   * 拖动开始/结束通知宿主：拖动期间正文改由 `scrollTo` 驱动，宿主需屏蔽贴边过滑
   * （回答页贴底时向上拖滚动条会被误判为"下一答"过滑）。
   */
  onSeekStateChange?: (dragging: boolean) => void;
  /** 是否在场（非动画量）：false 时轨道区 `HitTestMode.None`，右缘手势交给正文列表。 */
  @State private mounted: boolean = false;
  /** 透明度（动画量）：出现 120ms / 消失 260ms。 */
  @State private alpha: number = 0;
  @State private dragging: boolean = false;
  /** 拖动期间的进度：不以宿主回推的滚动偏移为准，保证拇指严格跟随手指。 */
  @State private dragProgress: number = 0;
  private fadeTimerId: number = -1;
  private unmountTimerId: number = -1;
  private dragAnchorProgress: number = 0;
  private seekNotified: boolean = false;

  aboutToDisappear(): void {
    this.clearFadeTimer();
    this.clearUnmountTimer();
    if (this.seekNotified) {
      this.seekNotified = false;
      const callback = this.onSeekStateChange;
      if (callback !== undefined) {
        callback(false);
      }
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column()
        .width(TRACK_BAR_WIDTH_VP)
        .height('100%')
        .borderRadius(TRACK_BAR_WIDTH_VP / 2)
        .backgroundColor($r('app.color.divider_color'))
        .opacity(0.45)
      Column()
        .id('p2_reading_progress_thumb')
        .width(THUMB_WIDTH_VP)
        .height(this.thumbHeightVp())
        .borderRadius(THUMB_WIDTH_VP / 2)
        .backgroundColor($r('app.color.brand_primary'))
        .opacity(0.88)
        .translate({ y: this.thumbOffsetVp() })
    }
    .id('p2_reading_progress_bar')
    .width(READING_PROGRESS_BAR_HIT_WIDTH_VP)
    .height('100%')
    .padding({ top: this.topInsetVp, bottom: this.bottomInsetVp })
    .opacity(this.alpha)
    // 命中开关与透明度分离：`alpha` 归零时节点仍在树上（不遮挡、不响应），
    // 避免"隐藏期间把手势吃掉"，也不会因节点反复进出渲染树而丢掉命中能力。
    .hitTestBehavior(this.mounted && this.scrollable() ? HitTestMode.Default : HitTestMode.None)
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.Vertical })
        .onActionStart((): void => {
          this.clearFadeTimer();
          this.clearUnmountTimer();
          this.dragging = true;
          this.mounted = true;
          this.dragAnchorProgress = this.scrollProgress();
          this.dragProgress = this.dragAnchorProgress;
          this.showBar();
          if (!this.seekNotified) {
            this.seekNotified = true;
            const callback = this.onSeekStateChange;
            if (callback !== undefined) {
              callback(true);
            }
          }
        })
        .onActionUpdate((event: GestureEvent): void => {
          const travel = this.thumbTravelVp();
          const next = travel > 0
            ? clampUnit(this.dragAnchorProgress + event.offsetY / travel)
            : this.dragAnchorProgress;
          this.dragProgress = next;
          this.scroller.scrollTo({ xOffset: 0, yOffset: next * this.maxScrollVp(), animation: false });
        })
        .onActionEnd((): void => {
          this.dragging = false;
          this.notifySeekEnd();
          this.scheduleFadeOut();
        })
        .onActionCancel((): void => {
          this.dragging = false;
          this.notifySeekEnd();
          this.scheduleFadeOut();
        })
    )
  }

  /** 视口高与可滚动量都已就绪时，任何输入变化都视为"活动中"：显示并重置淡出计时。 */
  private onBarInputChanged(): void {
    if (!this.scrollable()) {
      return;
    }
    this.showBar();
    this.scheduleFadeOut();
  }

  private maxScrollVp(): number {
    return Math.max(0, this.contentHeightVp - this.viewportHeightVp);
  }

  private scrollable(): boolean {
    return this.viewportHeightVp > 0 && this.maxScrollVp() > MIN_SCROLLABLE_VP;
  }

  /** 拇指高度 = 视口高 × (视口高 / 内容总高)，下限 24vp、上限一整个视口。 */
  private thumbHeightVp(): number {
    const viewport = this.viewportHeightVp;
    if (viewport <= 0) {
      return 0;
    }
    const content = Math.max(viewport, this.contentHeightVp);
    return Math.min(viewport, Math.max(MIN_THUMB_HEIGHT_VP, viewport * (viewport / content)));
  }

  /** 拇指可移动行程：视口高 − 拇指高（上游 calculateScrollbarThumbOffsetPx 的 trackRange）。 */
  private thumbTravelVp(): number {
    return Math.max(0, this.viewportHeightVp - this.thumbHeightVp());
  }

  private scrollProgress(): number {
    const max = this.maxScrollVp();
    if (max <= 0) {
      return 0;
    }
    return clampUnit(this.scrollYVp / max);
  }

  private displayProgress(): number {
    return this.dragging ? this.dragProgress : this.scrollProgress();
  }

  private thumbOffsetVp(): number {
    return this.thumbTravelVp() * this.displayProgress();
  }

  private showBar(): void {
    if (!this.scrollable()) {
      return;
    }
    this.clearUnmountTimer();
    this.mounted = true;
    if (this.alpha >= 1) {
      return;
    }
    this.getUIContext().animateTo({
      duration: APPEAR_DURATION_MS,
      curve: Curve.FastOutSlowIn
    }, (): void => {
      this.alpha = 1;
    });
  }

  private hideBar(): void {
    if (this.alpha <= 0) {
      this.mounted = false;
      return;
    }
    this.getUIContext().animateTo({
      duration: DISAPPEAR_DURATION_MS,
      curve: Curve.FastOutSlowIn
    }, (): void => {
      this.alpha = 0;
    });
    // 淡出播完再关命中：`alpha` 在动画起始帧即为 0，立刻关掉会让 260ms 淡出期间
    // 已无命中能力（拖动尾段丢失）。
    this.clearUnmountTimer();
    this.unmountTimerId = setTimeout((): void => {
      this.unmountTimerId = -1;
      if (!this.dragging) {
        this.mounted = false;
      }
    }, DISAPPEAR_DURATION_MS);
  }

  private scheduleFadeOut(): void {
    this.clearFadeTimer();
    if (this.dragging) {
      return;
    }
    this.fadeTimerId = setTimeout((): void => {
      this.fadeTimerId = -1;
      if (!this.dragging) {
        this.hideBar();
      }
    }, FADE_OUT_DELAY_MS);
  }

  /** 拖动结束通知宿主恢复贴边过滑判定。 */
  private notifySeekEnd(): void {
    if (this.seekNotified) {
      this.seekNotified = false;
      const callback = this.onSeekStateChange;
      if (callback !== undefined) {
        callback(false);
      }
    }
  }

  private clearFadeTimer(): void {
    if (this.fadeTimerId >= 0) {
      clearTimeout(this.fadeTimerId);
      this.fadeTimerId = -1;
    }
  }

  private clearUnmountTimer(): void {
    if (this.unmountTimerId >= 0) {
      clearTimeout(this.unmountTimerId);
      this.unmountTimerId = -1;
    }
  }
}
