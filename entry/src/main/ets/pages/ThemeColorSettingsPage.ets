import {
  AppPreferencesStore,
  DEFAULT_THEME_COLOR,
  hexToRgb,
  HsvColor,
  hsvToRgb,
  normalizeThemeColor,
  rgbToHex,
  rgbToHsv,
  RgbColor
} from 'data';
import { getAbilityContext } from '../entryability/AbilityContextHolder';

/**
 * 主题颜色配置页：12 个预设色（2 排 × 6 列）+ 自定义取色（色盘 + 亮度条）。
 * 选择写入 AppStorage 'themeColor' 并持久化；全局生效色由 P1Shell 解析为
 * 'resolvedThemeColor' 广播，深浅色模式自动适配。
 */
interface PresetColorItem {
  name: string;
  /** 空串表示“自定义”格子（彩虹圆）。 */
  hex: string;
}

const CUSTOM_COLOR_NAME = '自定义';

const PRESET_COLORS: PresetColorItem[] = [
  { name: '知乎蓝', hex: '#0066FF' },
  { name: 'IT红', hex: '#D22222' },
  { name: '橘红', hex: '#F44836' },
  { name: '橘黄', hex: '#F2821E' },
  { name: '草绿', hex: '#7BB736' },
  { name: '翠绿', hex: '#16C24B' },
  { name: '青色', hex: '#16A8C2' },
  { name: '天蓝', hex: '#29B6F6' },
  { name: '蓝色', hex: '#3F51B5' },
  { name: '青紫', hex: '#5538E9' },
  { name: '紫色', hex: '#9C27B0' },
  { name: '初音', hex: '#39C5BB' }
];

/** 网格数据源：12 预设 + 末尾自定义格。 */
const GRID_ITEMS: PresetColorItem[] = [...PRESET_COLORS, { name: CUSTOM_COLOR_NAME, hex: '' }];

/** 色盘横向色相渐变（左→右，满饱和满亮度）。 */
const HUE_GRADIENT_COLORS: [ResourceColor, number][] = [
  ['#FFFF0000', 0],
  ['#FFFFFF00', 0.167],
  ['#FF00FF00', 0.333],
  ['#FF00FFFF', 0.5],
  ['#FF0000FF', 0.667],
  ['#FFFF00FF', 0.833],
  ['#FFFF0000', 1]
];

/** 自定义格的彩虹圆扫掠渐变。 */
const CUSTOM_SWATCH_COLORS: [ResourceColor, number][] = [
  ['#FFFF0000', 0],
  ['#FFFFFF00', 0.167],
  ['#FF00FF00', 0.333],
  ['#FF00FFFF', 0.5],
  ['#FF0000FF', 0.667],
  ['#FFFF00FF', 0.833],
  ['#FFFF0000', 1]
];

@Component
export struct ThemeColorSettingsPage {
  /** 用户所选 seed 色（#RRGGBB），全局唯一真相。 */
  @StorageProp('themeColor') private storedThemeColor: string = DEFAULT_THEME_COLOR;
  /** 当前生效主色（深浅色已解析），用于本页强调元素即时预览。 */
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @State private hue: number = 221;
  @State private saturation: number = 1;
  @State private colorValue: number = 1;
  /** 选中标记：预设 hex；空串表示“自定义”选中。与持久化色解耦，允许自定义编辑恰好等于预设色。 */
  @State private selectedPresetHex: string = '';
  @State private paletteWidth: number = 1;
  @State private paletteHeight: number = 1;
  @State private statusMessage: string = '';
  private store: AppPreferencesStore | undefined = undefined;

  aboutToAppear(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusMessage = '设置服务暂不可用';
      return;
    }
    this.store = new AppPreferencesStore(context);
    this.syncHsvFromHex(this.storedThemeColor);
    const preset = this.presetOf(normalizeThemeColor(this.storedThemeColor));
    this.selectedPresetHex = preset === undefined ? '' : preset.hex;
  }

  build() {
    Scroll() {
      Column({ space: $r('app.float.p1_spacing_large') }) {
        if (this.statusMessage.length > 0) {
          Text(this.statusMessage)
            .id('p3_themecolor_status')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
        }

        Column() {
          Grid() {
            ForEach(GRID_ITEMS, (item: PresetColorItem): void => {
              GridItem() {
                this.colorCell(item)
              }
            }, (item: PresetColorItem): string => item.name)
          }
          .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr')
          .rowsGap($r('app.float.p1_spacing_medium'))
          .width('100%')
          .padding($r('app.float.p1_card_padding'))
        }
        .width('100%')
        .borderRadius($r('app.float.p1_card_radius'))
        .backgroundColor($r('app.color.surface_background'))

        Column() {
          Row() {
            Text('16进制')
              .fontSize($r('app.float.p1_body_font_size'))
              .fontColor($r('app.color.primary_text'))
            Text(this.currentHex())
              .id('p3_themecolor_hex')
              .fontSize($r('app.float.p1_body_font_size'))
              .fontColor(this.resolvedThemeColor)
              .fontWeight(FontWeight.Medium)
            Blank().layoutWeight(1)
            Text('RGB')
              .fontSize($r('app.float.p1_body_font_size'))
              .fontColor($r('app.color.primary_text'))
            Text(this.currentRgbLabel())
              .id('p3_themecolor_rgb')
              .fontSize($r('app.float.p1_body_font_size'))
              .fontColor(this.resolvedThemeColor)
              .fontWeight(FontWeight.Medium)
          }
          .width('100%')
          .padding($r('app.float.p1_card_padding'))
        }
        .width('100%')
        .borderRadius($r('app.float.p1_card_radius'))
        .backgroundColor($r('app.color.surface_background'))

        Column({ space: $r('app.float.p1_spacing_medium') }) {
          Text('自定义颜色')
            .fontSize($r('app.float.p1_body_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .width('100%')
          Text('拖动色盘调整色相与饱和度，拖动亮度条调整明暗')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
          this.colorPalette()
          this.colorValueSlider()
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding($r('app.float.p1_card_padding'))
        .borderRadius($r('app.float.p1_card_radius'))
        .backgroundColor($r('app.color.surface_background'))
      }
      .width('100%')
      .padding({
        left: $r('app.float.p1_page_padding'),
        right: $r('app.float.p1_page_padding'),
        top: 94,
        bottom: $r('app.float.p1_page_padding')
      })
    }
    .id('p3_themecolor_settings_page')
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private colorCell(item: PresetColorItem) {
    Column({ space: $r('app.float.p1_spacing_xsmall') }) {
      Stack() {
        if (item.hex.length === 0) {
          Row()
            .width(36)
            .height(36)
            .borderRadius(18)
            .sweepGradient({
              center: ['50%', '50%'],
              colors: CUSTOM_SWATCH_COLORS
            })
        } else {
          Row()
            .width(36)
            .height(36)
            .borderRadius(18)
            .backgroundColor(item.hex)
        }
        if (this.isItemSelected(item)) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(18)
            .fontColor([Color.White])
        }
      }
      .width(36)
      .height(36)
      Text(item.name)
        .fontSize(11)
        .fontColor($r('app.color.secondary_text'))
        .maxLines(1)
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .onClick((): void => {
      if (item.hex.length === 0) {
        this.selectCustom();
      } else {
        this.selectPreset(item.hex);
      }
    })
  }

  @Builder
  private colorPalette() {
    Stack() {
      // 底层：横向色相渐变（满饱和满亮度）
      Row()
        .width('100%')
        .height('100%')
        .borderRadius($r('app.float.p1_card_radius'))
        .linearGradient({ angle: 90, colors: HUE_GRADIENT_COLORS })
      // 上层：纵向 白→透明（顶部饱和度 0，底部饱和度 1）
      Row()
        .width('100%')
        .height('100%')
        .borderRadius($r('app.float.p1_card_radius'))
        .linearGradient({ angle: 180, colors: [['#FFFFFFFF', 0], ['#00FFFFFF', 1]] })
      // 亮度遮罩：随亮度条变暗（不拦截触摸）
      Row()
        .width('100%')
        .height('100%')
        .borderRadius($r('app.float.p1_card_radius'))
        .backgroundColor(Color.Black)
        .opacity(1 - this.colorValue)
        .hitTestBehavior(HitTestMode.None)
      // 当前位置指示环（不拦截触摸）
      Row()
        .width(22)
        .height(22)
        .borderRadius(11)
        .border({ width: 3, color: Color.White })
        .backgroundColor(this.currentHex())
        .shadow({ radius: 4, color: '#66000000' })
        .position({
          x: `${(this.hue / 360) * 100}%`,
          y: `${this.saturation * 100}%`
        })
        .translate({ x: '-50%', y: '-50%' })
        .hitTestBehavior(HitTestMode.None)
    }
    .id('p3_themecolor_palette')
    .width('100%')
    .height(180)
    .onAreaChange((_oldValue: Area, newValue: Area): void => {
      this.paletteWidth = Number(newValue.width);
      this.paletteHeight = Number(newValue.height);
    })
    .onTouch((event: TouchEvent): void => this.handlePaletteTouch(event))
  }

  @Builder
  private colorValueSlider() {
    Stack({ alignContent: Alignment.Center }) {
      // 渐变轨道：左黑 → 右当前色相满亮度色
      Row()
        .width('calc(100% - 4vp)')
        .height($r('app.float.p3_settings_slider_track_thickness'))
        .borderRadius($r('app.float.p3_settings_slider_track_radius'))
        .linearGradient({
          angle: 90,
          colors: [['#FF000000', 0], [this.fullBrightnessHex(), 1]]
        })
        .hitTestBehavior(HitTestMode.None)

      Row() {
        Blank().layoutWeight(Math.max(0, this.colorValue * 100))
        Stack({ alignContent: Alignment.Center }) {
          Row()
            .width('100%')
            .height($r('app.float.p3_settings_slider_track_thickness'))
            .backgroundColor($r('app.color.surface_background'))
          Row()
            .width($r('app.float.p3_settings_slider_thumb_width'))
            .height($r('app.float.p3_settings_slider_thumb_height'))
            .borderRadius($r('app.float.p3_settings_slider_thumb_radius'))
            .backgroundColor(this.currentHex())
        }
        .width($r('app.float.p3_settings_slider_thumb_gap_width'))
        .height($r('app.float.p3_settings_slider_height'))
        Blank().layoutWeight(Math.max(0, (1 - this.colorValue) * 100))
      }
      .width('calc(100% + 12vp)')
      .height($r('app.float.p3_settings_slider_height'))
      .translate({ x: '-6vp' })
      .hitTestBehavior(HitTestMode.None)

      Slider({ value: this.colorValue * 100, min: 0, max: 100, step: 1, style: SliderStyle.OutSet })
        .id('p3_themecolor_brightness')
        .width('100%')
        .height($r('app.float.p3_settings_slider_height'))
        .trackColor(Color.Transparent)
        .selectedColor(Color.Transparent)
        .blockColor(Color.Transparent)
        .blockSize({
          width: $r('app.float.p3_settings_slider_thumb_width'),
          height: $r('app.float.p3_settings_slider_thumb_height')
        })
        .blockStyle({
          type: SliderBlockType.SHAPE,
          shape: new Rect({
            width: $r('app.float.p3_settings_slider_thumb_width'),
            height: $r('app.float.p3_settings_slider_thumb_height')
          }).radius($r('app.float.p3_settings_slider_thumb_radius'))
        })
        .onChange((next: number, mode: SliderChangeMode): void => {
          this.colorValue = Math.min(1, Math.max(0, next / 100));
          this.selectedPresetHex = '';
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            this.persistCurrentColor();
          } else {
            this.broadcastCurrentColor();
          }
        })
    }
    .width('100%')
    .height($r('app.float.p3_settings_slider_height'))
  }

  /** 当前编辑色（HSV 合成），同时也是持久化/广播的值。 */
  private currentHex(): string {
    return rgbToHex(hsvToRgb(this.currentHsv()));
  }

  private currentHsv(): HsvColor {
    const hsv: HsvColor = { h: this.hue, s: this.saturation, v: this.colorValue };
    return hsv;
  }

  private currentRgbLabel(): string {
    const rgb: RgbColor = hexToRgb(this.currentHex());
    return `${rgb.r}, ${rgb.g}, ${rgb.b}`;
  }

  /** 当前色相/饱和度在满亮度下的颜色（亮度条渐变右端）。 */
  private fullBrightnessHex(): string {
    const hsv: HsvColor = { h: this.hue, s: this.saturation, v: 1 };
    return rgbToHex(hsvToRgb(hsv));
  }

  private isItemSelected(item: PresetColorItem): boolean {
    if (item.hex.length === 0) {
      return this.selectedPresetHex.length === 0;
    }
    return this.selectedPresetHex === item.hex;
  }

  private presetOf(hex: string): PresetColorItem | undefined {
    for (const item of PRESET_COLORS) {
      if (item.hex === hex) {
        return item;
      }
    }
    return undefined;
  }

  private selectPreset(hex: string): void {
    this.selectedPresetHex = hex;
    this.syncHsvFromHex(hex);
    AppStorage.setOrCreate('themeColor', hex);
    void this.store?.saveThemeColor(hex).then((): void => {
      this.statusMessage = '';
    }).catch((_error: Object): void => {
      this.statusMessage = '主题颜色保存失败，本次调整仍已生效';
    });
  }

  /** 点选“自定义”格：以当前色为起点进入自定义编辑。 */
  private selectCustom(): void {
    this.selectedPresetHex = '';
    this.syncHsvFromHex(this.currentHex());
  }

  private handlePaletteTouch(event: TouchEvent): void {
    const touch = event.touches[0];
    if (touch === undefined) {
      return;
    }
    if (event.type === TouchType.Down || event.type === TouchType.Move) {
      const x = Math.min(Math.max(touch.x, 0), this.paletteWidth);
      const y = Math.min(Math.max(touch.y, 0), this.paletteHeight);
      if (this.paletteWidth > 0) {
        this.hue = (x / this.paletteWidth) * 360;
      }
      if (this.paletteHeight > 0) {
        this.saturation = y / this.paletteHeight;
      }
      this.selectedPresetHex = '';
      this.broadcastCurrentColor();
    } else if (event.type === TouchType.Up) {
      this.persistCurrentColor();
    }
  }

  /** 实时广播编辑色（拖动跟手预览），不写持久化。 */
  private broadcastCurrentColor(): void {
    AppStorage.setOrCreate('themeColor', this.currentHex());
  }

  /** 手势结束时落盘。 */
  private persistCurrentColor(): void {
    const hex = this.currentHex();
    AppStorage.setOrCreate('themeColor', hex);
    void this.store?.saveThemeColor(hex).then((): void => {
      this.statusMessage = '';
    }).catch((_error: Object): void => {
      this.statusMessage = '主题颜色保存失败，本次调整仍已生效';
    });
  }

  private syncHsvFromHex(hex: string): void {
    const hsv = rgbToHsv(hexToRgb(hex));
    // 无色相信息的颜色（纯灰/黑/白）保留当前色相，避免指示环跳变。
    if (hsv.s > 0 && hsv.v > 0) {
      this.hue = hsv.h;
      this.saturation = hsv.s;
    }
    this.colorValue = hsv.v;
  }
}
