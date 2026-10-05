import {
  AppPreferencesStore,
  DEFAULT_THEME_COLOR,
  hexToRgb,
  HsvColor,
  hsvToRgb,
  normalizeThemeColor,
  parseHexThemeColorInput,
  parseRgbThemeColorInput,
  rgbToHex,
  rgbToHsv,
  RgbColor
} from 'data';
import { getAbilityContext } from '../entryability/AbilityContextHolder';

/**
 * 主题颜色配置页：13 个预设色（2 排 × 7 列）+ 自定义取色（色盘 + 亮度条）。
 * 选择写入 AppStorage 'themeColor' 并持久化；全局生效色由 AppShell 解析为
 * 'resolvedThemeColor' 广播，深浅色模式自动适配。
 */
interface PresetColorItem {
  name: string;
  /** 空串表示“自定义”格子（彩虹圆）。 */
  hex: string;
}

const CUSTOM_COLOR_NAME = '自定义';

const PRESET_COLORS: PresetColorItem[] = [
  { name: '知乎', hex: '#0066FF' },
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
  { name: '初音', hex: '#39C5BB' },
  { name: '天依', hex: '#66CCFF' }
];

/** 网格数据源：13 预设 + 末尾自定义格。 */
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
  /** 16 进制输入框内容，随当前色同步；用户聚焦编辑期间不回写。 */
  @State private hexInput: string = '';
  /** RGB 输入框内容（r,g,b 逗号分隔），随当前色同步；聚焦编辑期间不回写。 */
  @State private rgbInput: string = '';
  /** 输入框聚焦标记：聚焦期间程序不回写文本，避免打字时内容被覆盖。 */
  private hexFieldEditing: boolean = false;
  private rgbFieldEditing: boolean = false;
  /** 色盘拖动中标记：true 期间外层 Scroll 拦截滚动，避免拖色盘带动页面。 */
  private paletteDragging: boolean = false;
  /** 非法输入 toast 去重标记：每次聚焦只提示一次（回车与失焦可能连续触发提交）。 */
  private hexInputToastShown: boolean = false;
  private rgbInputToastShown: boolean = false;
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
      Column({ space: $r('app.float.spacing_large') }) {
        if (this.statusMessage.length > 0) {
          Text(this.statusMessage)
            .id('themecolor_status')
            .fontSize($r('app.float.secondary_font_size'))
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
          .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
          .rowsGap($r('app.float.spacing_medium'))
          .width('100%')
          .padding($r('app.float.card_padding'))
        }
        .width('100%')
        .borderRadius($r('app.float.card_radius'))
        .backgroundColor($r('app.color.surface_background'))

        this.hexRgbCard()

        Column({ space: $r('app.float.spacing_medium') }) {
          Text('自定义颜色')
            .fontSize($r('app.float.body_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .width('100%')
          Text('拖动色盘调整色相与饱和度，拖动亮度条调整明暗')
            .fontSize($r('app.float.secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
          this.colorPalette()
          this.colorValueSlider()
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding($r('app.float.card_padding'))
        .borderRadius($r('app.float.card_radius'))
        .backgroundColor($r('app.color.surface_background'))
      }
      .width('100%')
      .padding({
        left: $r('app.float.page_padding'),
        right: $r('app.float.page_padding'),
        top: 94,
        bottom: $r('app.float.page_padding')
      })
    }
    .id('themecolor_settings_page')
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .onScrollFrameBegin((offset: number, _state: ScrollState): OnScrollFrameBeginHandlerResult => {
      if (this.paletteDragging) {
        return { offsetRemain: 0 };
      }
      return { offsetRemain: offset };
    })
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private colorCell(item: PresetColorItem) {
    Column({ space: $r('app.float.spacing_xsmall') }) {
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
  private hexRgbCard() {
    Row({ space: $r('app.float.spacing_xsmall') }) {
      Text('16进制:')
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
      TextInput({ text: this.hexInput, placeholder: '#0066FF' })
        .id('themecolor_hex_input')
        .layoutWeight(1.05)
        .height(40)
        .fontSize($r('app.float.secondary_font_size'))
        .padding({ left: 4, right: 4 })
        .maxLength(7)
        .textAlign(TextAlign.Center)
        .enterKeyType(EnterKeyType.Done)
        .caretColor(this.resolvedThemeColor)
        .onChange((value: string): void => this.onHexInputChange(value))
        .onSubmit((_enterKey: EnterKeyType, _event: SubmitEvent): void => this.commitHexField())
        .onFocus((): void => {
          this.hexFieldEditing = true;
          this.hexInputToastShown = false;
        })
        .onBlur((): void => this.commitHexField())
      Text('RGB:')
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
      TextInput({ text: this.rgbInput, placeholder: '210,34,34' })
        .id('themecolor_rgb_input')
        .layoutWeight(1.25)
        .height(40)
        .fontSize($r('app.float.secondary_font_size'))
        .padding({ left: 6, right: 6 })
        .maxLength(12)
        .textAlign(TextAlign.Center)
        .enterKeyType(EnterKeyType.Done)
        .caretColor(this.resolvedThemeColor)
        .onChange((value: string): void => this.onRgbInputChange(value))
        .onSubmit((_enterKey: EnterKeyType, _event: SubmitEvent): void => this.commitRgbField())
        .onFocus((): void => {
          this.rgbFieldEditing = true;
          this.rgbInputToastShown = false;
        })
        .onBlur((): void => this.commitRgbField())
    }
    .width('100%')
    .padding($r('app.float.card_padding'))
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.surface_background'))
  }

  @Builder
  private colorPalette() {
    Stack() {
      // 底层：横向色相渐变（满饱和满亮度）
      Row()
        .width('100%')
        .height('100%')
        .borderRadius($r('app.float.card_radius'))
        .linearGradient({ angle: 90, colors: HUE_GRADIENT_COLORS })
      // 上层：纵向 白→透明（顶部饱和度 0，底部饱和度 1）
      Row()
        .width('100%')
        .height('100%')
        .borderRadius($r('app.float.card_radius'))
        .linearGradient({ angle: 180, colors: [['#FFFFFFFF', 0], ['#00FFFFFF', 1]] })
      // 亮度遮罩：随亮度条变暗（不拦截触摸）
      Row()
        .width('100%')
        .height('100%')
        .borderRadius($r('app.float.card_radius'))
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
    .id('themecolor_palette')
    .width('100%')
    .height(180)
    .onAreaChange((_oldValue: Area, newValue: Area): void => {
      this.paletteWidth = Number(newValue.width);
      this.paletteHeight = Number(newValue.height);
    })
    .onTouch((event: TouchEvent): void => this.handlePaletteTouch(event))
    .gesture(PanGesture({ direction: PanDirection.All, fingers: 1, distance: 5 })
      .onActionStart((_event: GestureEvent): void => {
        this.paletteDragging = true;
      })
      .onActionEnd((_event: GestureEvent): void => {
        this.paletteDragging = false;
      })
      .onActionCancel((): void => {
        this.paletteDragging = false;
      }))
  }

  @Builder
  private colorValueSlider() {
    Stack({ alignContent: Alignment.Center }) {
      // 渐变轨道：左黑 → 右当前色相满亮度色
      Row()
        .width('calc(100% - 4vp)')
        .height($r('app.float.settings_slider_track_thickness'))
        .borderRadius($r('app.float.settings_slider_track_radius'))
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
            .height($r('app.float.settings_slider_track_thickness'))
            .backgroundColor($r('app.color.surface_background'))
          Row()
            .width($r('app.float.settings_slider_thumb_width'))
            .height($r('app.float.settings_slider_thumb_height'))
            .borderRadius($r('app.float.settings_slider_thumb_radius'))
            .backgroundColor(this.currentHex())
        }
        .width($r('app.float.settings_slider_thumb_gap_width'))
        .height($r('app.float.settings_slider_height'))
        Blank().layoutWeight(Math.max(0, (1 - this.colorValue) * 100))
      }
      .width('calc(100% + 12vp)')
      .height($r('app.float.settings_slider_height'))
      .translate({ x: '-6vp' })
      .hitTestBehavior(HitTestMode.None)

      Slider({ value: this.colorValue * 100, min: 0, max: 100, step: 1, style: SliderStyle.OutSet })
        .id('themecolor_brightness')
        .width('100%')
        .height($r('app.float.settings_slider_height'))
        .trackColor(Color.Transparent)
        .selectedColor(Color.Transparent)
        .blockColor(Color.Transparent)
        .blockSize({
          width: $r('app.float.settings_slider_thumb_width'),
          height: $r('app.float.settings_slider_thumb_height')
        })
        .blockStyle({
          type: SliderBlockType.SHAPE,
          shape: new Rect({
            width: $r('app.float.settings_slider_thumb_width'),
            height: $r('app.float.settings_slider_thumb_height')
          }).radius($r('app.float.settings_slider_thumb_radius'))
        })
        .onChange((next: number, mode: SliderChangeMode): void => {
          this.colorValue = Math.min(1, Math.max(0, next / 100));
          this.selectedPresetHex = '';
          this.syncInputsFromColor(true);
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            this.persistCurrentColor();
          } else {
            this.broadcastCurrentColor();
          }
        })
    }
    .width('100%')
    .height($r('app.float.settings_slider_height'))
  }

  /** 当前编辑色（HSV 合成），同时也是持久化/广播的值。 */
  private currentHex(): string {
    return rgbToHex(hsvToRgb(this.currentHsv()));
  }

  private currentHsv(): HsvColor {
    const hsv: HsvColor = { h: this.hue, s: this.saturation, v: this.colorValue };
    return hsv;
  }

  private presetHexOf(hex: string): string {
    const preset = this.presetOf(hex);
    return preset === undefined ? '' : preset.hex;
  }

  /** 16 进制输入实时预览：合法即应用（不落盘，等提交/失焦再落盘）。 */
  private onHexInputChange(value: string): void {
    this.hexInput = value;
    const parsed = parseHexThemeColorInput(value);
    if (parsed === undefined) {
      return;
    }
    this.selectedPresetHex = this.presetHexOf(parsed);
    this.syncHsvFromHex(parsed);
    this.broadcastCurrentColor();
  }

  private commitHexField(): void {
    this.hexFieldEditing = false;
    const parsed = parseHexThemeColorInput(this.hexInput);
    if (parsed === undefined) {
      if (!this.hexInputToastShown) {
        this.hexInputToastShown = true;
        this.getUIContext().getPromptAction().showToast({
          message: '16 进制色值格式不正确，应为 6 位十六进制（如 #0066FF）',
          duration: 2500
        });
      }
      this.syncInputsFromColor(false);
      return;
    }
    this.selectedPresetHex = this.presetHexOf(parsed);
    this.syncHsvFromHex(parsed);
    this.persistCurrentColor();
    this.syncInputsFromColor(false);
  }

  /** RGB 输入实时预览：三个通道均合法才应用。 */
  private onRgbInputChange(value: string): void {
    this.rgbInput = value;
    const parsed = parseRgbThemeColorInput(value);
    if (parsed === undefined) {
      return;
    }
    const hex = rgbToHex(parsed);
    this.selectedPresetHex = this.presetHexOf(hex);
    this.syncHsvFromHex(hex);
    this.broadcastCurrentColor();
  }

  private commitRgbField(): void {
    this.rgbFieldEditing = false;
    const parsed = parseRgbThemeColorInput(this.rgbInput);
    if (parsed === undefined) {
      if (!this.rgbInputToastShown) {
        this.rgbInputToastShown = true;
        this.getUIContext().getPromptAction().showToast({
          message: 'RGB 色值格式不正确，应为 r,g,b（0–255，如 210,34,34）',
          duration: 2500
        });
      }
      this.syncInputsFromColor(false);
      return;
    }
    const hex = rgbToHex(parsed);
    this.selectedPresetHex = this.presetHexOf(hex);
    this.syncHsvFromHex(hex);
    this.persistCurrentColor();
    this.syncInputsFromColor(false);
  }

  /** 将当前色回写输入框；force 为 true 时无视聚焦标记（外部手势接管时防脏数据提交）。 */
  private syncInputsFromColor(force: boolean): void {
    const hex = this.currentHex();
    const rgb: RgbColor = hexToRgb(hex);
    if (force || !this.hexFieldEditing) {
      this.hexInput = hex;
    }
    if (force || !this.rgbFieldEditing) {
      this.rgbInput = `${rgb.r},${rgb.g},${rgb.b}`;
    }
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
    // 预设点击是外部接管：即使输入框仍持有焦点也强制回写，避免失焦提交脏数据。
    this.syncInputsFromColor(true);
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
    if (event.type === TouchType.Down) {
      this.paletteDragging = true;
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
      this.syncInputsFromColor(true);
      this.broadcastCurrentColor();
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.paletteDragging = false;
      if (event.type === TouchType.Up) {
        this.persistCurrentColor();
      }
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
    this.syncInputsFromColor(false);
  }
}
