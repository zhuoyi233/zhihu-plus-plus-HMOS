import { common } from '@kit.AbilityKit';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import {
  P1DestinationName,
  ShellDestination
} from 'core';

enum P1ThemeMode {
  SYSTEM = 'system',
  LIGHT = 'light',
  DARK = 'dark'
}

@Component
export struct P1Shell {
  @BuilderParam technicalLabContent: () => void = this.emptyTechnicalLab;
  @State private themeMode: P1ThemeMode = P1ThemeMode.SYSTEM;
  @Provide('p1PathStack') pathStack: NavPathStack = new NavPathStack();

  @Builder
  emptyTechnicalLab() {
    Blank();
  }

  @Builder
  destinationBuilder(name: string, _param: Object) {
    if (name === P1DestinationName.SETTINGS) {
      NavDestination() {
        this.settingsPage();
      }
      .title('显示与阅读')
      .backgroundColor($r('app.color.page_background'))
    } else if (name === P1DestinationName.TECHNICAL_LAB) {
      NavDestination() {
        this.technicalLabContent();
      }
      .title('技术实验室')
      .backgroundColor($r('app.color.page_background'))
    }
  }

  build() {
    Navigation(this.pathStack) {
      Scroll() {
        Column({ space: $r('app.float.p1_spacing_large') }) {
          Column({ space: $r('app.float.p1_spacing_small') }) {
            Text('轻量、原生、尊重隐私')
              .id('p1_home_title')
              .fontSize($r('app.float.p1_display_font_size'))
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))

            Text('P1 正在建立 HarmonyOS 原生基础设施，不包含端侧 AI。')
              .id('p1_home_description')
              .fontSize($r('app.float.p1_body_font_size'))
              .fontColor($r('app.color.secondary_text'))
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          Column({ space: $r('app.float.p1_spacing_medium') }) {
            Button({ type: ButtonType.Normal, stateEffect: true }) {
              Column({ space: $r('app.float.p1_spacing_xsmall') }) {
                Text('显示与阅读')
                  .fontSize($r('app.float.p1_heading_font_size'))
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.primary_text'))
                Text('主题、深浅色与系统字体缩放')
                  .fontSize($r('app.float.p1_secondary_font_size'))
                  .fontColor($r('app.color.secondary_text'))
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
            }
            .id('p1_open_display_settings')
            .width('100%')
            .padding($r('app.float.p1_card_padding'))
            .borderRadius($r('app.float.p1_card_radius'))
            .backgroundColor($r('app.color.surface_background'))
            .onClick(() => {
              const destination: ShellDestination = { name: P1DestinationName.SETTINGS };
              this.navigate(destination);
            })

            Button({ type: ButtonType.Normal, stateEffect: true }) {
              Column({ space: $r('app.float.p1_spacing_xsmall') }) {
                Text('技术实验室')
                  .fontSize($r('app.float.p1_heading_font_size'))
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.primary_text'))
                Text('保留 P0 网络、登录、正文、图片与数据原型')
                  .fontSize($r('app.float.p1_secondary_font_size'))
                  .fontColor($r('app.color.secondary_text'))
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
            }
            .id('p1_open_technical_lab')
            .width('100%')
            .padding($r('app.float.p1_card_padding'))
            .borderRadius($r('app.float.p1_card_radius'))
            .backgroundColor($r('app.color.surface_background'))
            .onClick(() => {
              const destination: ShellDestination = { name: P1DestinationName.TECHNICAL_LAB };
              this.navigate(destination);
            })
          }
          .width('100%')
        }
        .width('100%')
        .padding({
          left: $r('app.float.p1_page_padding'),
          right: $r('app.float.p1_page_padding'),
          top: $r('app.float.p1_page_padding'),
          bottom: $r('app.float.p1_page_padding')
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
    }
    .title('Zhihu++')
    .titleMode(NavigationTitleMode.Mini)
    .mode(NavigationMode.Stack)
    .navDestination(this.destinationBuilder)
    .backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  settingsPage() {
    Scroll() {
      Column({ space: $r('app.float.p1_spacing_large') }) {
        Column({ space: $r('app.float.p1_spacing_small') }) {
          Text('主题模式')
            .fontSize($r('app.float.p1_heading_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))

          Text('切换会立即更新颜色资源；“跟随系统”会响应系统深浅色。')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))

          Column({ space: $r('app.float.p1_spacing_small') }) {
            this.themeButton('跟随系统', P1ThemeMode.SYSTEM, 'p1_theme_system');
            this.themeButton('浅色', P1ThemeMode.LIGHT, 'p1_theme_light');
            this.themeButton('深色', P1ThemeMode.DARK, 'p1_theme_dark');
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding($r('app.float.p1_card_padding'))
        .borderRadius($r('app.float.p1_card_radius'))
        .backgroundColor($r('app.color.surface_background'))

        Column({ space: $r('app.float.p1_spacing_small') }) {
          Text('字体缩放预览')
            .fontSize($r('app.float.p1_heading_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))

          Text('标题文字会跟随系统字体大小')
            .id('p1_font_scale_heading')
            .fontSize($r('app.float.p1_heading_font_size'))
            .fontColor($r('app.color.primary_text'))

          Text('正文使用 fp 字体单位，支持换行且不限制最大行数。')
            .id('p1_font_scale_body')
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.secondary_text'))
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding($r('app.float.p1_card_padding'))
        .borderRadius($r('app.float.p1_card_radius'))
        .backgroundColor($r('app.color.surface_background'))

        Text('页面内容由 Navigation 约束在系统安全区内，背景延伸覆盖状态栏和底部系统区域。')
          .id('p1_safe_area_description')
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
      }
      .width('100%')
      .padding($r('app.float.p1_page_padding'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  themeButton(label: string, mode: P1ThemeMode, testId: string) {
    Button(label)
      .id(testId)
      .width('100%')
      .fontSize($r('app.float.p1_secondary_font_size'))
      .fontColor(this.themeMode === mode ? $r('app.color.on_brand') : $r('app.color.primary_text'))
      .backgroundColor(this.themeMode === mode ? $r('app.color.brand_primary') : $r('app.color.control_background'))
      .onClick(() => {
        this.applyThemeMode(mode);
      })
  }

  private navigate(destination: ShellDestination): void {
    this.pathStack.pushPath(
      { name: destination.name, param: destination },
      { launchMode: LaunchMode.MOVE_TO_TOP_SINGLETON }
    );
  }

  private applyThemeMode(mode: P1ThemeMode): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.themeMode = mode;
    if (mode === P1ThemeMode.DARK) {
      context.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } else if (mode === P1ThemeMode.LIGHT) {
      context.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } else {
      context.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    }
  }
}
