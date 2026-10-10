import { display } from '@kit.ArkUI';
import { ReaderBlock, ReaderBlockKind } from './ReaderDocument';
import { ImageDisplaySize, computeImageDisplaySize } from './ReaderImageSizing';

/** 加载完成前的占位宽高比（加载后按源图比例覆盖）。 */
const IMAGE_PLACEHOLDER_ASPECT_RATIO = 4 / 3;

/** 屏幕视口（vp）与密度：像素原大小折算 vp、屏幕占比计算共用。 */
interface ScreenViewport {
  width: number;
  height: number;
  density: number;
}

/** 读取当前屏幕视口尺寸（vp）与密度；异常或非法值时返回 undefined，由占位样式兜底。 */
function screenViewport(): ScreenViewport | undefined {
  try {
    const displaySync = display.getDefaultDisplaySync();
    const density = displaySync.densityPixels > 0 ? displaySync.densityPixels : 1;
    if (displaySync.width > 0 && displaySync.height > 0) {
      return {
        width: displaySync.width / density,
        height: displaySync.height / density,
        density: density
      };
    }
  } catch (_error) {
    // 无显示环境（如单测）时回退占位样式。
  }
  return undefined;
}

@Component
export struct ReaderImageBlock {
  item: ReaderBlock = { id: '', kind: ReaderBlockKind.IMAGE, text: '', sourceUrl: '', inlineRuns: [] };
  onPreview: (url: string) => void = () => {};
  secondaryTextColor: ResourceColor = Color.Gray;
  @State private failed: boolean = false;
  @State private retryRevision: number = 0;
  @State private imageAspectRatio: number = IMAGE_PLACEHOLDER_ASPECT_RATIO;
  /** 加载完成后的显示宽度（vp）；0 表示尚未加载，沿用占位宽度。 */
  @State private displayWidthVp: number = 0;

  /** 源图像素尺寸（加载完成后记录，屏幕/容器变化时重算显示尺寸）。 */
  private naturalPixelSize: ImageDisplaySize = { width: 0, height: 0 };
  /** 正文容器可用宽度（vp）：显示宽度上限，避免超出排版宽度溢出。 */
  private availableWidthVp: number = 0;

  private imageSource(): string {
    if (this.retryRevision === 0) {
      return this.item.sourceUrl;
    }
    const separator = this.item.sourceUrl.includes('?') ? '&' : '?';
    return `${this.item.sourceUrl}${separator}zhplus_retry=${this.retryRevision}`;
  }

  /**
   * 按"原大小 + 占比钳制"策略计算显示宽度（高度经 aspectRatio 跟随）：
   * 原始像素按密度折算为 vp 后与屏幕比较占比，规则见 ReaderImageSizing.ets；
   * 结果再钳制到正文容器宽度，防止整屏宽图片溢出左右留白。
   */
  private applyDisplaySize(): void {
    const screen = screenViewport();
    if (screen === undefined || this.naturalPixelSize.width <= 0 || this.naturalPixelSize.height <= 0) {
      return;
    }
    const naturalWidth = this.naturalPixelSize.width / screen.density;
    const naturalHeight = this.naturalPixelSize.height / screen.density;
    const size = computeImageDisplaySize(naturalWidth, naturalHeight, screen.width, screen.height);
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    let width = size.width;
    if (this.availableWidthVp > 0 && width > this.availableWidthVp) {
      width = this.availableWidthVp;
    }
    this.displayWidthVp = width;
  }

  build() {
    Column({ space: 8 }) {
      Image(this.imageSource())
        .id(`reader_image_${this.item.id}`)
        // 加载后按"原大小 + 占比钳制"定宽（30%~80%/100% 屏占比，见 ReaderImageSizing），
        // 高度经 aspectRatio 按源图比例自适应，不再固定为内容宽 80%。
        .width(this.displayWidthVp > 0 ? this.displayWidthVp : '80%')
        .aspectRatio(this.imageAspectRatio)
        .objectFit(ImageFit.Contain)
        .onComplete((event) => {
          this.failed = false;
          if (event !== undefined && event.width > 0 && event.height > 0) {
            this.imageAspectRatio = event.width / event.height;
            this.naturalPixelSize = { width: event.width, height: event.height };
            this.applyDisplaySize();
          }
        })
        .onError(() => {
          this.failed = true;
        })
        .onClick(() => {
          if (!this.failed) {
            this.onPreview(this.item.sourceUrl);
          }
        })

      if (this.item.text.length > 0) {
        Text(this.item.text)
          .fontSize(14)
          .fontColor(this.secondaryTextColor)
          .textAlign(TextAlign.Center)
          .width('100%')
      }

      // 加载成功/加载中不显示状态小字；仅失败时展示错误与重试。
      if (this.failed) {
        Row({ space: 12 }) {
          Text('图片加载失败')
            .id(`reader_image_status_${this.item.id}`)
            .fontSize(13)
            .fontColor(this.secondaryTextColor)
          Button('重试')
            .id(`reader_image_retry_${this.item.id}`)
            .onClick(() => {
              this.failed = false;
              this.retryRevision += 1;
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      const width = Number(newArea.width);
      if (width > 0 && Math.abs(width - this.availableWidthVp) > 0.5) {
        this.availableWidthVp = width;
        // 屏幕旋转/窗口变化导致容器宽度变化时，按最新约束重算显示尺寸。
        this.applyDisplaySize();
      }
    })
  }
}
