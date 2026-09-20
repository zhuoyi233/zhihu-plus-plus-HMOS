import {
  allAnswerDoubleTapActions,
  AppearancePreferences,
  AnswerDoubleTapAction,
  answerDoubleTapActionLabel,
  AppPreferencesStore,
  AppThemeMode,
  AnswerSwitchMode,
  contentFontSizeLevels,
  decodeContentBlockSpacing,
  decodeContentFontSize,
  decodeContentLineHeight,
  DEFAULT_THEME_COLOR,
  FeedCardStyle,
  ExperiencePreferences,
  normalizeBottomBarItems,
  normalizeExperiencePreferences,
  normalizeAppearancePreferences,
  normalizeReaderTypography,
  normalizeThemeColor,
  onThemeColor,
  ReaderTypography,
  ShareActionMode
} from 'data';
import { getAbilityContext } from '../entryability/AbilityContextHolder';

/**
 * “外观与阅读体验”设置页。保留上游跨平台设置语义，但移除 Material You、
 * Material 配色和 Android popup 造型等在 HarmonyOS 上不成立的选项。
 */
/** 滑块设置项参数。@Builder 以单个对象字面量传参（按引用），状态变化才能触发 UI 刷新。 */
interface SliderSettingOptions {
  title: string;
  description: string;
  value: number;
  min: number;
  max: number;
  step: number;
  testId: string;
  showSteps: boolean;
  onChange: (value: number) => void;
}

@Component
export struct AppearanceSettingsPage {
  @Prop themeMode: AppThemeMode = AppThemeMode.SYSTEM;
  onThemeModeChange: (mode: AppThemeMode) => void = (_mode: AppThemeMode): void => {};
  onOpenThemeColorSettings: () => void = (): void => {};
  /** 主题色 seed 与当前生效色（P1Shell 启动时广播），驱动主题块入口行与强调色。 */
  @StorageProp('themeColor') private themeColorSeed: string = DEFAULT_THEME_COLOR;
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @StorageProp('contentFontSize') private contentFontSize: number = 100;
  @StorageProp('contentLineHeight') private contentLineHeight: number = 160;
  @StorageProp('contentBlockSpacing') private contentBlockSpacing: number = 100;
  @StorageProp('fabOpacity') private fabOpacity: number = 100;
  @StorageProp('showFeedThumbnail') private showFeedThumbnail: boolean = true;
  @StorageProp('showRefreshFab') private showRefreshFab: boolean = true;
  @StorageProp('feedCardStyle') private feedCardStyle: string = FeedCardStyle.DIVIDER;
  @StorageProp('answerDoubleTapAction') private answerDoubleTapAction: AnswerDoubleTapAction =
    AnswerDoubleTapAction.ASK;
  @StorageProp('titleAutoHide') private titleAutoHide: boolean = false;
  @StorageProp('autoHideArticleBottomBar') private autoHideArticleBottomBar: boolean = false;
  @StorageProp('buttonSkipAnswer') private buttonSkipAnswer: boolean = true;
  @StorageProp('autoHideSkipAnswerButton') private autoHideSkipAnswerButton: boolean = true;
  @StorageProp('pinAnswerDate') private pinAnswerDate: boolean = false;
  @StorageProp('answerSwitchMode') private answerSwitchMode: string = AnswerSwitchMode.VERTICAL;
  @StorageProp('answerSwitchSensitivity') private answerSwitchSensitivity: number = 1;
  @StorageProp('startDestination') private startDestination: string = 'Home';
  @StorageProp('bottomBarItems') private bottomBarItems: string = 'Home,Following,Hot,Daily,Settings';
  @StorageProp('tapToRefresh') private tapToRefresh: boolean = true;
  @StorageProp('autoHideBottomBar') private autoHideBottomBar: boolean = false;
  @StorageProp('volumeKeyPageTurn') private volumeKeyPageTurn: boolean = false;
  @StorageProp('pageTurnSwitchAnswer') private pageTurnSwitchAnswer: boolean = true;
  @StorageProp('showPageTurnFab') private showPageTurnFab: boolean = false;
  @StorageProp('pageTurnPercent') private pageTurnPercent: number = 90;
  @StorageProp('showPageTurnGuide') private showPageTurnGuide: boolean = false;
  @StorageProp('showContentEndMarker') private showContentEndMarker: boolean = false;
  @StorageProp('shareActionMode') private shareActionMode: string = ShareActionMode.ASK;
  @StorageProp('showSearchHotSearch') private showSearchHotSearch: boolean = true;
  @StorageProp('showSearchHistory') private showSearchHistory: boolean = true;
  @State private statusMessage: string = '';
  private store: AppPreferencesStore | undefined = undefined;

  aboutToAppear(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusMessage = '设置服务暂不可用';
      return;
    }
    this.store = new AppPreferencesStore(context);
  }

  build() {
    Scroll() {
      Column({ space: $r('app.float.p1_spacing_large') }) {
        if (this.statusMessage.length > 0) {
          Text(this.statusMessage)
            .id('p3_appearance_status')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
        }

        this.sectionTitle('主题')
        Column() {
          this.themeModeSetting()
          Divider().color($r('app.color.divider_color'))
          this.themeColorSetting()
          Divider().color($r('app.color.divider_color'))
          this.sliderSetting({
            title: '悬浮按钮透明度',
            description: `控制页面悬浮操作的透明度（${this.fabOpacity}%）`,
            value: this.fabOpacity, min: 10, max: 100, step: 5,
            testId: 'p3_appearance_fab_opacity', showSteps: false,
            onChange: (value: number): void => {
              this.updateAppearance(value, this.showFeedThumbnail, this.showRefreshFab, this.feedCardStyleValue());
            }
          })
        }
        .width('100%')
        .borderRadius($r('app.float.p1_card_radius'))
        .backgroundColor($r('app.color.surface_background'))

        this.sectionTitle('阅读')
        Column() {
          this.fontSizeSetting()
          Divider().color($r('app.color.divider_color'))
          this.sliderSetting({
            title: '行高',
            description: `调整内容行间距（${this.contentLineHeight}%）`,
            value: this.contentLineHeight, min: 100, max: 300, step: 10,
            testId: 'p3_appearance_line_height', showSteps: false,
            onChange: (value: number): void => {
              this.updateTypography(this.contentFontSize, decodeContentLineHeight(value), this.contentBlockSpacing);
            }
          })
          Divider().color($r('app.color.divider_color'))
          this.sliderSetting({
            title: '段间距',
            description: `调整正文段落和块级内容间距（${this.contentBlockSpacing}%）`,
            value: this.contentBlockSpacing, min: 0, max: 300, step: 10,
            testId: 'p3_appearance_block_spacing', showSteps: false,
            onChange: (value: number): void => {
              this.updateTypography(this.contentFontSize, this.contentLineHeight, decodeContentBlockSpacing(value));
            }
          })
        }
        .width('100%')
        .borderRadius($r('app.float.p1_card_radius'))
        .backgroundColor($r('app.color.surface_background'))

        this.sectionTitle('信息流')
        Column() {
          this.switchSetting('显示信息流缩略图', '在有封面信息时显示内容缩略图', this.showFeedThumbnail,
            'p3_appearance_feed_thumbnail', (value: boolean): void => {
              this.updateAppearance(this.fabOpacity, value, this.showRefreshFab, this.feedCardStyleValue());
            })
          Divider().color($r('app.color.divider_color'))
          this.switchSetting('显示刷新悬浮按钮', '在信息流右下角显示快捷刷新按钮', this.showRefreshFab,
            'p3_appearance_refresh_fab', (value: boolean): void => {
              this.updateAppearance(this.fabOpacity, this.showFeedThumbnail, value, this.feedCardStyleValue());
            })
          Divider().color($r('app.color.divider_color'))
          this.selectSetting('信息流样式', '卡片样式使用圆角卡片展示，分割线样式使用细线分隔条目。',
            this.feedCardStyleLabel(), this.feedCardStyleOptions(), this.feedCardStyleIndex(),
            'p3_appearance_feed_style', (index: number): void => this.updateFeedCardStyle(index))
        }
        .width('100%')
        .borderRadius($r('app.float.p1_card_radius'))
        .backgroundColor($r('app.color.surface_background'))

        this.sectionTitle('回答页')
        Column() {
          this.switchSetting('自动隐藏回答标题', '滚动时自动隐藏回答标题栏', this.titleAutoHide,
            'p3_appearance_title_auto_hide', (value: boolean): void => this.updateExperienceBoolean('titleAutoHide', value))
          Divider().color($r('app.color.divider_color'))
          this.switchSetting('自动隐藏回答底部按钮', '上划时隐藏底部操作，下划时重新显示', this.autoHideArticleBottomBar,
            'p3_appearance_bottom_bar_auto_hide', (value: boolean): void => this.updateExperienceBoolean('autoHideArticleBottomBar', value))
          Divider().color($r('app.color.divider_color'))
          this.switchSetting('显示跳转下一个回答按钮', '在回答页显示可拖动的快速跳转按钮', this.buttonSkipAnswer,
            'p3_appearance_skip_answer', (value: boolean): void => this.updateExperienceBoolean('buttonSkipAnswer', value))
          if (this.buttonSkipAnswer) {
            Divider().color($r('app.color.divider_color'))
            this.switchSetting('滚动时自动隐藏跳转按钮', '上划时淡出，下划时淡入', this.autoHideSkipAnswerButton,
              'p3_appearance_skip_answer_auto_hide', (value: boolean): void => this.updateExperienceBoolean('autoHideSkipAnswerButton', value))
          }
          Divider().color($r('app.color.divider_color'))
          this.switchSetting('置顶回答日期', '将发布和编辑日期移到内容最前面', this.pinAnswerDate,
            'p3_appearance_pin_answer_date', (value: boolean): void => this.updateExperienceBoolean('pinAnswerDate', value))
          Divider().color($r('app.color.divider_color'))
          this.selectSetting('回答切换手势', '在同一问题的回答之间切换', this.answerSwitchModeLabel(),
            this.answerSwitchModeOptions(), this.answerSwitchModeIndex(), 'p3_appearance_answer_switch_mode',
            (index: number): void => this.updateAnswerSwitchMode(index))
          if (this.answerSwitchMode !== AnswerSwitchMode.OFF) {
            Divider().color($r('app.color.divider_color'))
            this.sliderSetting({
              title: '回答切换灵敏度',
              description: `当前 ${this.answerSwitchSensitivity.toFixed(1)}x，数值越高滑动越短`,
              value: this.answerSwitchSensitivity, min: 0.5, max: 3, step: 0.1,
              testId: 'p3_appearance_answer_switch_sensitivity', showSteps: false,
              onChange: (value: number): void => this.updateExperienceNumber('answerSwitchSensitivity', value)
            })
          }
          Divider().color($r('app.color.divider_color'))
          this.selectSetting('双击回答动作', '双击回答正文时执行的动作，默认弹窗询问',
            answerDoubleTapActionLabel(this.answerDoubleTapAction), this.answerDoubleTapSelectOptions(),
            this.answerDoubleTapIndex(), 'p3_appearance_answer_double_tap',
            (index: number): void => {
              const actions = allAnswerDoubleTapActions();
              if (index >= 0 && index < actions.length) {
                this.updateAnswerDoubleTapAction(actions[index]);
              }
            })
        }
        .width('100%')
        .borderRadius($r('app.float.p1_card_radius'))
        .backgroundColor($r('app.color.surface_background'))

        this.sectionTitle('底部导航栏')
        Column() {
          // 不能走 selectSetting：其 options/selected/value 是 @Builder 按值传参，
          // 首渲染后固化，底部栏项目实时增删时下拉列表不会更新（builder 体内直读状态才可刷新）。
          this.startDestinationSetting()
          Divider().color($r('app.color.divider_color'))
          Column({ space: $r('app.float.p1_spacing_small') }) {
            Text('底部栏项目与顺序')
              .fontSize($r('app.float.p1_body_font_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.primary_text'))
              .width('100%')
            Text('选择 3–5 个项目并调整顺序；“我的”固定保留')
              .fontSize($r('app.float.p1_secondary_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .width('100%')
            ForEach(this.allBottomBarKeys(), (key: string): void => {
              this.bottomBarItemSetting(key)
            }, (key: string): string => key)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding($r('app.float.p1_card_padding'))
          Divider().color($r('app.color.divider_color'))
          this.switchSetting('点击底部导航栏回到顶部/刷新', '点击当前页签回到顶部，已在顶部时刷新；双击直接刷新', this.tapToRefresh,
            'p3_appearance_tap_to_refresh', (value: boolean): void => this.updateExperienceBoolean('tapToRefresh', value))
          Divider().color($r('app.color.divider_color'))
          this.switchSetting('滚动时自动隐藏底部导航栏', '上划时隐藏，下划时重新显示', this.autoHideBottomBar,
            'p3_appearance_nav_auto_hide', (value: boolean): void => this.updateExperienceBoolean('autoHideBottomBar', value))
        }
        .width('100%')
        .borderRadius($r('app.float.p1_card_radius'))
        .backgroundColor($r('app.color.surface_background'))

        this.sectionTitle('电纸书翻页')
        Text('在内容列表、正文、评论区和设置等可滚动页面生效，私聊除外。')
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
        Column() {
          this.switchSetting('音量键翻页', '短按翻页，长按跳到顶部或底部', this.volumeKeyPageTurn,
            'p3_appearance_volume_page_turn', (value: boolean): void => this.updateExperienceBoolean('volumeKeyPageTurn', value))
          Divider().color($r('app.color.divider_color'))
          this.switchSetting('翻页切换回答', '在回答顶部或底部继续翻页时切换回答', this.pageTurnSwitchAnswer,
            'p3_appearance_page_turn_answer', (value: boolean): void => this.updateExperienceBoolean('pageTurnSwitchAnswer', value))
          Divider().color($r('app.color.divider_color'))
          this.switchSetting('显示翻页悬浮按钮', '只在支持翻页的可滚动页面显示', this.showPageTurnFab,
            'p3_appearance_page_turn_fab', (value: boolean): void => this.updateExperienceBoolean('showPageTurnFab', value))
          Divider().color($r('app.color.divider_color'))
          this.sliderSetting({
            title: '翻页距离',
            description: `每次滚动可见区域的 ${this.pageTurnPercent}%`,
            value: this.pageTurnPercent, min: 50, max: 100, step: 5,
            testId: 'p3_appearance_page_turn_percent', showSteps: false,
            onChange: (value: number): void => this.updateExperienceNumber('pageTurnPercent', value)
          })
          Divider().color($r('app.color.divider_color'))
          this.switchSetting('显示翻页位置线', '翻页后标记上一页与下一页的重叠位置', this.showPageTurnGuide,
            'p3_appearance_page_turn_guide', (value: boolean): void => this.updateExperienceBoolean('showPageTurnGuide', value))
          Divider().color($r('app.color.divider_color'))
          this.switchSetting('显示内容结束标记', '方便电纸书用户确定内容已结束', this.showContentEndMarker,
            'p3_appearance_content_end_marker', (value: boolean): void => this.updateExperienceBoolean('showContentEndMarker', value))
        }
        .width('100%')
        .borderRadius($r('app.float.p1_card_radius'))
        .backgroundColor($r('app.color.surface_background'))

        this.sectionTitle('交互')
        Column() {
          this.selectSetting('分享操作', '点击分享按钮时的默认行为', this.shareActionModeLabel(),
            this.shareActionModeOptions(), this.shareActionModeIndex(), 'p3_appearance_share_action',
            (index: number): void => this.updateShareActionMode(index))
        }
        .width('100%')
        .borderRadius($r('app.float.p1_card_radius'))
        .backgroundColor($r('app.color.surface_background'))

        this.sectionTitle('搜索')
        Column() {
          this.switchSetting('搜索界面显示热搜', '在搜索界面空白时显示知乎热搜关键词', this.showSearchHotSearch,
            'p3_appearance_search_hot', (value: boolean): void => this.updateExperienceBoolean('showSearchHotSearch', value))
          Divider().color($r('app.color.divider_color'))
          this.switchSetting('记录并显示搜索历史', '关闭后不再记录新的搜索关键词', this.showSearchHistory,
            'p3_appearance_search_history', (value: boolean): void => this.updateExperienceBoolean('showSearchHistory', value))
        }
        .width('100%')
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
    .id('p3_appearance_settings_page')
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private sectionTitle(title: string) {
    Text(title)
      .fontSize($r('app.float.p1_secondary_font_size'))
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.secondary_text'))
      .width('100%')
      .padding({ left: $r('app.float.p1_spacing_xsmall') })
  }

  @Builder
  private themeModeSetting() {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      Text('主题模式')
        .fontSize($r('app.float.p1_body_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Text('跟随系统会自动响应 HarmonyOS 深浅色设置')
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      Row({ space: $r('app.float.p1_spacing_small') }) {
        this.themeModeButton('跟随系统', AppThemeMode.SYSTEM, 'p3_appearance_theme_system')
        this.themeModeButton('浅色', AppThemeMode.LIGHT, 'p3_appearance_theme_light')
        this.themeModeButton('深色', AppThemeMode.DARK, 'p3_appearance_theme_dark')
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
  }

  @Builder
  private themeModeButton(label: string, mode: AppThemeMode, testId: string) {
    Button(label, { type: ButtonType.ROUNDED_RECTANGLE, stateEffect: true })
      .id(testId)
      .layoutWeight(1)
      .fontSize($r('app.float.p1_secondary_font_size'))
      .fontColor(this.themeMode === mode ? onThemeColor(this.resolvedThemeColor) : $r('app.color.primary_text'))
      .backgroundColor(this.themeMode === mode ? this.resolvedThemeColor : $r('app.color.control_background'))
      .onClick((): void => this.onThemeModeChange(mode))
  }

  /** 主题颜色入口行：当前色圆点 + 名称 + hex，点击进入主题颜色配置页。 */
  @Builder
  private themeColorSetting() {
    Row({ space: $r('app.float.p1_spacing_medium') }) {
      Column({ space: $r('app.float.p1_spacing_xsmall') }) {
        Text('主题颜色')
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.primary_text'))
          .width('100%')
        Text('信息流、正文与按钮等强调元素使用的颜色')
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(normalizeThemeColor(this.themeColorSeed))
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
      Row()
        .width(24)
        .height(24)
        .borderRadius(12)
        .backgroundColor(this.resolvedThemeColor)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('app.color.secondary_text')])
    }
    .id('p3_appearance_theme_color')
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
    .alignItems(VerticalAlign.Center)
    .onClick((): void => this.onOpenThemeColorSettings())
  }

  @Builder
  private fontSizeSetting() {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      Text('字号')
        .fontSize($r('app.float.p1_body_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Text(`调整内容文字大小（${this.contentFontSize}%）`)
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      this.sliderControl({
        title: '字号',
        description: `调整内容文字大小（${this.contentFontSize}%）`,
        value: this.fontSizeLevelIndex(), min: 0, max: contentFontSizeLevels().length - 1, step: 1,
        testId: 'p3_appearance_font_size', showSteps: true,
        onChange: (value: number): void => {
          const levels = contentFontSizeLevels();
          const index = Math.min(levels.length - 1, Math.max(0, Math.round(value)));
          this.updateTypography(levels[index], this.contentLineHeight, this.contentBlockSpacing);
        }
      })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
  }

  @Builder
  private sliderSetting($$: SliderSettingOptions) {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      Text($$.title)
        .fontSize($r('app.float.p1_body_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Text($$.description)
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      this.sliderControl($$)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
  }

  private sliderProgressPercent(value: number, min: number, max: number): number {
    if (max <= min) {
      return 0;
    }
    return Math.min(100, Math.max(0, (value - min) / (max - min) * 100));
  }

  @Builder
  private sliderControl($$: SliderSettingOptions) {
    Stack({ alignContent: Alignment.Center }) {
      Row() {
        Row()
          .width(`${this.sliderProgressPercent($$.value, $$.min, $$.max)}%`)
          .height('100%')
          .backgroundColor(this.resolvedThemeColor)
        Row()
          .width(`${100 - this.sliderProgressPercent($$.value, $$.min, $$.max)}%`)
          .height('100%')
          .backgroundColor($r('app.color.control_background'))
      }
      .width('calc(100% - 4vp)')
      .height($r('app.float.p3_settings_slider_track_thickness'))
      .borderRadius($r('app.float.p3_settings_slider_track_radius'))
      .clip(true)
      .hitTestBehavior(HitTestMode.None)

      Row() {
        Blank().layoutWeight(Math.max(0, $$.value - $$.min))
        Stack({ alignContent: Alignment.Center }) {
          Row()
            .width('100%')
            .height($r('app.float.p3_settings_slider_track_thickness'))
            .backgroundColor($r('app.color.surface_background'))
          Row()
            .width($r('app.float.p3_settings_slider_thumb_width'))
            .height($r('app.float.p3_settings_slider_thumb_height'))
            .borderRadius($r('app.float.p3_settings_slider_thumb_radius'))
            .backgroundColor(this.resolvedThemeColor)
        }
        .width($r('app.float.p3_settings_slider_thumb_gap_width'))
        .height($r('app.float.p3_settings_slider_height'))
        Blank().layoutWeight(Math.max(0, $$.max - $$.value))
      }
      .width('calc(100% + 12vp)')
      .height($r('app.float.p3_settings_slider_height'))
      .translate({ x: '-6vp' })
      .hitTestBehavior(HitTestMode.None)

      Slider({ value: $$.value, min: $$.min, max: $$.max, step: $$.step, style: SliderStyle.OutSet })
        .id($$.testId)
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
        .showSteps($$.showSteps)
        .onChange((next: number, _mode: SliderChangeMode): void => $$.onChange(next))
    }
    .width('100%')
    .height($r('app.float.p3_settings_slider_height'))
  }

  @Builder
  private switchSetting(title: string, description: string, checked: boolean, testId: string,
    onChange: (value: boolean) => void) {
    Row({ space: $r('app.float.p1_spacing_medium') }) {
      Column({ space: $r('app.float.p1_spacing_xsmall') }) {
        Text(title)
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.primary_text'))
          .width('100%')
        Text(description)
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: checked })
        .id(testId)
        .selectedColor(this.resolvedThemeColor)
        .onChange((value: boolean): void => onChange(value))
    }
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private selectSetting(title: string, description: string, value: string, options: SelectOption[], selected: number,
    testId: string, onSelect: (index: number) => void) {
    Row({ space: $r('app.float.p1_spacing_medium') }) {
      Column({ space: $r('app.float.p1_spacing_xsmall') }) {
        Text(title)
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.primary_text'))
          .width('100%')
        Text(description)
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Select(options)
        .id(testId)
        .selected(selected)
        .value(value)
        .fontColor($r('app.color.primary_text'))
        .constraintSize({ maxWidth: 160 })
        .onSelect((index: number): void => onSelect(index))
    }
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private bottomBarItemSetting(key: string) {
    Row({ space: $r('app.float.p1_spacing_small') }) {
      // 点击区只包住勾选框和文字（ClickEvent 无 stopPropagation，按钮区须放在点击区外）
      Row({ space: $r('app.float.p1_spacing_small') }) {
        // 展示型勾选框（对齐上游 onCheckedChange=null 的 Checkbox）：不持有内部状态，
        // 避免 Toggle 在点击被拒绝后视觉翻转无法回弹导致与实际选中态脱节
        SymbolGlyph(this.bottomBarKeys().includes(key) ? $r('sys.symbol.checkmark_circle_fill')
          : $r('sys.symbol.circle'))
            .fontSize(22)
            .fontColor([this.bottomBarKeys().includes(key) ? this.resolvedThemeColor
              : $r('app.color.secondary_text')])
            .id(`p3_appearance_bottom_item_${key}`)
        Text(this.bottomBarItemLabel(key))
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor(key === 'Settings' ? $r('app.color.secondary_text') : $r('app.color.primary_text'))
          .layoutWeight(1)
      }
      .alignItems(VerticalAlign.Center)
      .layoutWeight(1)
      .onClick((): void => {
        const keys = this.bottomBarKeys();
        const selected = keys.includes(key);
        if (key === 'Settings') {
          return; // “我的”固定保留，不可取消
        }
        if (selected && keys.length <= 3) {
          this.showToast('底部栏至少保留 3 个项目');
          return;
        }
        if (!selected && keys.length >= 5) {
          this.showToast('底部栏最多显示 5 个项目');
          return;
        }
        this.toggleBottomBarItem(key, !selected);
      })
      // 常驻定宽定高容器（对齐上游 96dp 固定宽右列）：勾选态切换时行高不变，不再引起上下边距跳动
      Row({ space: 4 }) {
        if (this.bottomBarKeys().includes(key)) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.chevron_up'))
              .fontSize(18)
              .fontColor([$r('app.color.primary_text')])
          }
            .id(`p3_appearance_bottom_item_up_${key}`)
            .width(44)
            .height(44)
            .backgroundColor($r('app.color.control_background'))
            .enabled(this.bottomBarKeys().indexOf(key) > 0)
            .accessibilityText(`上移${this.bottomBarItemLabel(key)}`)
            .onClick((): void => this.moveBottomBarItem(key, -1))
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(18)
              .fontColor([$r('app.color.primary_text')])
          }
            .id(`p3_appearance_bottom_item_down_${key}`)
            .width(44)
            .height(44)
            .backgroundColor($r('app.color.control_background'))
            .enabled(this.bottomBarKeys().indexOf(key) < this.bottomBarKeys().length - 1)
            .accessibilityText(`下移${this.bottomBarItemLabel(key)}`)
            .onClick((): void => this.moveBottomBarItem(key, 1))
        }
      }
      .width(92)
      .height(44)
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /** 启动默认页选择：独立 @Builder，选项/选中项在体内直读状态，随底部栏项目变更实时刷新。 */
  @Builder
  private startDestinationSetting() {
    Row({ space: $r('app.float.p1_spacing_medium') }) {
      Column({ space: $r('app.float.p1_spacing_xsmall') }) {
        Text('应用启动默认页面')
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.primary_text'))
          .width('100%')
        Text('启动后默认打开的底部页签')
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Select(this.startDestinationOptions())
        .id('p3_appearance_start_destination')
        .selected(this.startDestinationIndex())
        .value(this.startDestinationLabel())
        .fontColor($r('app.color.primary_text'))
        .constraintSize({ maxWidth: 160 })
        .onSelect((index: number): void => this.updateStartDestination(index))
    }
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
    .alignItems(VerticalAlign.Center)
  }

  private feedCardStyleOptions(): SelectOption[] {
    return [{ value: '卡片样式' }, { value: '分割线样式' }];
  }

  private feedCardStyleIndex(): number {
    return this.feedCardStyleValue() === FeedCardStyle.CARD ? 0 : 1;
  }

  private feedCardStyleLabel(): string {
    return this.feedCardStyleValue() === FeedCardStyle.CARD ? '卡片样式' : '分割线样式';
  }

  private updateFeedCardStyle(index: number): void {
    if (index === 0) {
      this.updateAppearance(this.fabOpacity, this.showFeedThumbnail, this.showRefreshFab, FeedCardStyle.CARD);
    } else if (index === 1) {
      this.updateAppearance(this.fabOpacity, this.showFeedThumbnail, this.showRefreshFab, FeedCardStyle.DIVIDER);
    }
  }

  private fontSizeLevelIndex(): number {
    const index = contentFontSizeLevels().indexOf(decodeContentFontSize(this.contentFontSize));
    return index >= 0 ? index : 0;
  }

  private feedCardStyleValue(): FeedCardStyle {
    return this.feedCardStyle === FeedCardStyle.CARD ? FeedCardStyle.CARD : FeedCardStyle.DIVIDER;
  }

  private answerDoubleTapSelectOptions(): SelectOption[] {
    return allAnswerDoubleTapActions().map((action: AnswerDoubleTapAction): SelectOption => {
      return { value: answerDoubleTapActionLabel(action) } as SelectOption;
    });
  }

  private answerDoubleTapIndex(): number {
    const index = allAnswerDoubleTapActions().indexOf(this.answerDoubleTapAction);
    return index >= 0 ? index : 0;
  }

  private answerSwitchModeValue(): AnswerSwitchMode {
    if (this.answerSwitchMode === AnswerSwitchMode.OFF) {
      return AnswerSwitchMode.OFF;
    }
    if (this.answerSwitchMode === AnswerSwitchMode.HORIZONTAL) {
      return AnswerSwitchMode.HORIZONTAL;
    }
    return AnswerSwitchMode.VERTICAL;
  }

  private answerSwitchModeOptions(): SelectOption[] {
    return [{ value: '关闭' }, { value: '上下滑动' }, { value: '左右滑动' }];
  }

  private answerSwitchModeIndex(): number {
    if (this.answerSwitchMode === AnswerSwitchMode.OFF) {
      return 0;
    }
    return this.answerSwitchMode === AnswerSwitchMode.HORIZONTAL ? 2 : 1;
  }

  private answerSwitchModeLabel(): string {
    if (this.answerSwitchMode === AnswerSwitchMode.OFF) return '关闭';
    return this.answerSwitchMode === AnswerSwitchMode.HORIZONTAL ? '左右滑动' : '上下滑动';
  }

  private updateAnswerSwitchMode(index: number): void {
    const values: AnswerSwitchMode[] = [AnswerSwitchMode.OFF, AnswerSwitchMode.VERTICAL, AnswerSwitchMode.HORIZONTAL];
    if (index >= 0 && index < values.length) {
      this.updateExperienceString('answerSwitchMode', values[index]);
    }
  }

  private startDestinationOptions(): SelectOption[] {
    return this.startDestinationValues().map((key: string): SelectOption => {
      return { value: this.bottomBarItemLabel(key) } as SelectOption;
    });
  }

  private startDestinationValues(): string[] {
    return this.bottomBarKeys();
  }

  private startDestinationIndex(): number {
    const index = this.startDestinationValues().indexOf(this.startDestination);
    return index >= 0 ? index : 0;
  }

  private startDestinationLabel(): string {
    return this.bottomBarItemLabel(this.startDestination);
  }

  private updateStartDestination(index: number): void {
    const values = this.startDestinationValues();
    if (index >= 0 && index < values.length) {
      this.updateExperienceString('startDestination', values[index]);
    }
  }

  private allBottomBarKeys(): string[] {
    return ['Home', 'Following', 'Hot', 'Daily', 'ReadHistory', 'Collections', 'Settings'];
  }

  private bottomBarKeys(): string[] {
    return normalizeBottomBarItems(this.bottomBarItems).split(',');
  }

  private bottomBarItemLabel(key: string): string {
    if (key === 'Following') return '关注';
    if (key === 'Hot') return '热榜';
    if (key === 'Daily') return '日报';
    if (key === 'ReadHistory') return '浏览记录';
    if (key === 'Collections') return '收藏夹';
    if (key === 'Settings') return '我的';
    return '首页';
  }

  private toggleBottomBarItem(key: string, selected: boolean): void {
    const keys = this.bottomBarKeys();
    const existingIndex = keys.indexOf(key);
    if (selected && existingIndex < 0) {
      if (keys.length >= 5) {
        this.showToast('底部栏最多显示 5 个项目');
        return;
      }
      const settingsIndex = keys.indexOf('Settings');
      keys.splice(settingsIndex >= 0 ? settingsIndex : keys.length, 0, key);
    } else if (!selected && existingIndex >= 0 && key !== 'Settings') {
      if (keys.length <= 3) {
        this.showToast('底部栏至少保留 3 个项目');
        return;
      }
      keys.splice(existingIndex, 1);
    } else {
      return;
    }
    const next = this.experiencePreferences();
    next.bottomBarItems = keys.join(',');
    if (!keys.includes(next.startDestination)) {
      next.startDestination = keys[0];
    }
    this.persistExperience(next);
  }

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
  }

  private moveBottomBarItem(key: string, offset: number): void {
    const keys = this.bottomBarKeys();
    const from = keys.indexOf(key);
    const to = from + offset;
    if (from < 0 || to < 0 || to >= keys.length) {
      return;
    }
    const target = keys[to];
    keys[to] = keys[from];
    keys[from] = target;
    const next = this.experiencePreferences();
    next.bottomBarItems = keys.join(',');
    this.persistExperience(next);
  }

  private shareActionModeValue(): ShareActionMode {
    if (this.shareActionMode === ShareActionMode.COPY) {
      return ShareActionMode.COPY;
    }
    return this.shareActionMode === ShareActionMode.SHARE ? ShareActionMode.SHARE : ShareActionMode.ASK;
  }

  private shareActionModeOptions(): SelectOption[] {
    return [{ value: '询问' }, { value: '复制链接' }, { value: '系统分享' }];
  }

  private shareActionModeIndex(): number {
    if (this.shareActionMode === ShareActionMode.COPY) {
      return 1;
    }
    return this.shareActionMode === ShareActionMode.SHARE ? 2 : 0;
  }

  private shareActionModeLabel(): string {
    if (this.shareActionMode === ShareActionMode.COPY) return '复制链接';
    return this.shareActionMode === ShareActionMode.SHARE ? '系统分享' : '询问';
  }

  private updateShareActionMode(index: number): void {
    const values: ShareActionMode[] = [ShareActionMode.ASK, ShareActionMode.COPY, ShareActionMode.SHARE];
    if (index >= 0 && index < values.length) {
      this.updateExperienceString('shareActionMode', values[index]);
    }
  }

  private experiencePreferences(): ExperiencePreferences {
    return normalizeExperiencePreferences({
      titleAutoHide: this.titleAutoHide,
      autoHideArticleBottomBar: this.autoHideArticleBottomBar,
      buttonSkipAnswer: this.buttonSkipAnswer,
      autoHideSkipAnswerButton: this.autoHideSkipAnswerButton,
      pinAnswerDate: this.pinAnswerDate,
      answerSwitchMode: this.answerSwitchModeValue(),
      answerSwitchSensitivity: this.answerSwitchSensitivity,
      startDestination: this.startDestination,
      bottomBarItems: this.bottomBarItems,
      tapToRefresh: this.tapToRefresh,
      autoHideBottomBar: this.autoHideBottomBar,
      volumeKeyPageTurn: this.volumeKeyPageTurn,
      pageTurnSwitchAnswer: this.pageTurnSwitchAnswer,
      showPageTurnFab: this.showPageTurnFab,
      pageTurnPercent: this.pageTurnPercent,
      showPageTurnGuide: this.showPageTurnGuide,
      showContentEndMarker: this.showContentEndMarker,
      shareActionMode: this.shareActionModeValue(),
      showSearchHotSearch: this.showSearchHotSearch,
      showSearchHistory: this.showSearchHistory
    });
  }

  private updateExperienceBoolean(key: string, value: boolean): void {
    const next = this.experiencePreferences();
    if (key === 'titleAutoHide') next.titleAutoHide = value;
    else if (key === 'autoHideArticleBottomBar') next.autoHideArticleBottomBar = value;
    else if (key === 'buttonSkipAnswer') next.buttonSkipAnswer = value;
    else if (key === 'autoHideSkipAnswerButton') next.autoHideSkipAnswerButton = value;
    else if (key === 'pinAnswerDate') next.pinAnswerDate = value;
    else if (key === 'tapToRefresh') next.tapToRefresh = value;
    else if (key === 'autoHideBottomBar') next.autoHideBottomBar = value;
    else if (key === 'volumeKeyPageTurn') next.volumeKeyPageTurn = value;
    else if (key === 'pageTurnSwitchAnswer') next.pageTurnSwitchAnswer = value;
    else if (key === 'showPageTurnFab') next.showPageTurnFab = value;
    else if (key === 'showPageTurnGuide') next.showPageTurnGuide = value;
    else if (key === 'showContentEndMarker') next.showContentEndMarker = value;
    else if (key === 'showSearchHotSearch') next.showSearchHotSearch = value;
    else if (key === 'showSearchHistory') next.showSearchHistory = value;
    this.persistExperience(next);
  }

  private updateExperienceNumber(key: string, value: number): void {
    const next = this.experiencePreferences();
    if (key === 'answerSwitchSensitivity') next.answerSwitchSensitivity = value;
    else if (key === 'pageTurnPercent') next.pageTurnPercent = value;
    this.persistExperience(next);
  }

  private updateExperienceString(key: string, value: string): void {
    const next = this.experiencePreferences();
    if (key === 'answerSwitchMode') next.answerSwitchMode = value as AnswerSwitchMode;
    else if (key === 'startDestination') next.startDestination = value;
    else if (key === 'shareActionMode') next.shareActionMode = value as ShareActionMode;
    this.persistExperience(next);
  }

  private persistExperience(raw: ExperiencePreferences): void {
    const value = normalizeExperiencePreferences(raw);
    AppStorage.setOrCreate('titleAutoHide', value.titleAutoHide);
    AppStorage.setOrCreate('autoHideArticleBottomBar', value.autoHideArticleBottomBar);
    AppStorage.setOrCreate('buttonSkipAnswer', value.buttonSkipAnswer);
    AppStorage.setOrCreate('autoHideSkipAnswerButton', value.autoHideSkipAnswerButton);
    AppStorage.setOrCreate('pinAnswerDate', value.pinAnswerDate);
    AppStorage.setOrCreate('answerSwitchMode', value.answerSwitchMode);
    AppStorage.setOrCreate('answerSwitchSensitivity', value.answerSwitchSensitivity);
    AppStorage.setOrCreate('startDestination', value.startDestination);
    AppStorage.setOrCreate('bottomBarItems', value.bottomBarItems);
    AppStorage.setOrCreate('tapToRefresh', value.tapToRefresh);
    AppStorage.setOrCreate('autoHideBottomBar', value.autoHideBottomBar);
    AppStorage.setOrCreate('volumeKeyPageTurn', value.volumeKeyPageTurn);
    AppStorage.setOrCreate('pageTurnSwitchAnswer', value.pageTurnSwitchAnswer);
    AppStorage.setOrCreate('showPageTurnFab', value.showPageTurnFab);
    AppStorage.setOrCreate('pageTurnPercent', value.pageTurnPercent);
    AppStorage.setOrCreate('showPageTurnGuide', value.showPageTurnGuide);
    AppStorage.setOrCreate('showContentEndMarker', value.showContentEndMarker);
    AppStorage.setOrCreate('shareActionMode', value.shareActionMode);
    AppStorage.setOrCreate('showSearchHotSearch', value.showSearchHotSearch);
    AppStorage.setOrCreate('showSearchHistory', value.showSearchHistory);
    void this.store?.saveExperiencePreferences(value).then((): void => {
      this.statusMessage = '';
    }).catch((_error: Object): void => {
      this.statusMessage = '设置保存失败，本次调整仍已生效';
    });
  }

  private updateAnswerDoubleTapAction(action: AnswerDoubleTapAction): void {
    AppStorage.setOrCreate('answerDoubleTapAction', action);
    void this.store?.saveAnswerDoubleTapAction(action).then((): void => {
      this.statusMessage = '';
    }).catch((_error: Object): void => {
      this.statusMessage = '回答设置保存失败，本次调整仍已生效';
    });
  }

  private updateTypography(fontSize: number, lineHeight: number, blockSpacing: number): void {
    const value: ReaderTypography = normalizeReaderTypography({
      fontSize: fontSize,
      lineHeight: lineHeight,
      blockSpacing: blockSpacing
    });
    AppStorage.setOrCreate('contentFontSize', value.fontSize);
    AppStorage.setOrCreate('contentLineHeight', value.lineHeight);
    AppStorage.setOrCreate('contentBlockSpacing', value.blockSpacing);
    void this.store?.saveReaderTypography(value).catch((_error: Object): void => {
      this.statusMessage = '阅读设置保存失败，本次调整仍已生效';
    });
  }

  private updateAppearance(fabOpacity: number, showFeedThumbnail: boolean, showRefreshFab: boolean,
    feedCardStyle: FeedCardStyle): void {
    const value: AppearancePreferences = normalizeAppearancePreferences({
      fabOpacity: fabOpacity,
      showFeedThumbnail: showFeedThumbnail,
      showRefreshFab: showRefreshFab,
      feedCardStyle: feedCardStyle
    });
    AppStorage.setOrCreate('fabOpacity', value.fabOpacity);
    AppStorage.setOrCreate('showFeedThumbnail', value.showFeedThumbnail);
    AppStorage.setOrCreate('showRefreshFab', value.showRefreshFab);
    AppStorage.setOrCreate('feedCardStyle', value.feedCardStyle);
    void this.store?.saveAppearancePreferences(value).then((): void => {
      this.statusMessage = '';
    }).catch((_error: Object): void => {
      this.statusMessage = '外观设置保存失败，本次调整仍已生效';
    });
  }
}
