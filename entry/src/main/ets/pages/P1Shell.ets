import { common } from '@kit.AbilityKit';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import { AppPreferencesStore, AppThemeMode } from 'data';
import {
  ContentDestination,
  decodeP1Destination,
  isInfrastructureDestination,
  LatestOperationGuard,
  P1Destination,
  P1DestinationName,
  shouldPushP1Destination,
  startupDestinationChannel,
  StartupDestinationListener
} from 'core';

@Component
export struct P1Shell {
  @BuilderParam technicalLabContent: (navigate: (destination: P1Destination) => void) => void =
    this.emptyTechnicalLab;
  @BuilderParam readerProbeContent: (onBack: () => void) => void = this.emptyProbe;
  @BuilderParam imageProbeContent: (onBack: () => void) => void = this.emptyProbe;
  @BuilderParam databaseProbeContent: (onBack: () => void) => void = this.emptyProbe;
  @BuilderParam deepLinkProbeContent: (onBack: () => void) => void = this.emptyProbe;
  @BuilderParam qrScanProbeContent: (onBack: () => void) => void = this.emptyProbe;
  @BuilderParam backgroundTaskProbeContent: (onBack: () => void) => void = this.emptyProbe;
  @BuilderParam domainFixtureProbeContent: (onBack: () => void) => void = this.emptyProbe;
  @State private themeMode: AppThemeMode = AppThemeMode.SYSTEM;
  @State private themePersistenceStatus: string = '正在读取主题设置…';
  @Provide('p1PathStack') pathStack: NavPathStack = new NavPathStack();
  private unsubscribeStartupDestination: (() => void) | undefined = undefined;
  private readonly themeOperationGuard: LatestOperationGuard = new LatestOperationGuard();
  private themeMounted: boolean = false;
  private themeSaveQueue: Promise<void> = Promise.resolve();

  aboutToAppear(): void {
    this.themeMounted = true;
    this.themePersistenceStatus = '正在读取主题设置…';
    this.restoreThemeMode();
    this.unsubscribeStartupDestination?.();
    const listener: StartupDestinationListener = (destination: P1Destination): void => {
      this.navigate(destination);
    };
    this.unsubscribeStartupDestination = startupDestinationChannel.subscribe(listener);
  }

  aboutToDisappear(): void {
    this.themeMounted = false;
    this.themeOperationGuard.invalidate();
    this.unsubscribeStartupDestination?.();
    this.unsubscribeStartupDestination = undefined;
  }

  @Builder
  emptyTechnicalLab(_navigate: (destination: P1Destination) => void) {
    Blank();
  }

  @Builder
  emptyProbe(_onBack: () => void) {
    Blank();
  }

  @Builder
  destinationBuilder(name: string, param: Object) {
    if (decodeP1Destination(name, param) === undefined) {
      NavDestination() {
        this.invalidDestinationPage();
      }
      .title('无法打开页面')
      .backgroundColor($r('app.color.page_background'))
    } else if (name === P1DestinationName.SETTINGS) {
      NavDestination() {
        this.settingsPage();
      }
      .title('显示与阅读')
      .backgroundColor($r('app.color.page_background'))
    } else if (name === P1DestinationName.TECHNICAL_LAB) {
      NavDestination() {
        this.technicalLabContent((destination: P1Destination): void => this.navigate(destination));
      }
      .title('技术实验室')
      .backgroundColor($r('app.color.page_background'))
    } else if (name === P1DestinationName.READER_PROBE) {
      NavDestination() {
        this.readerProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .backgroundColor($r('app.color.page_background'))
    } else if (name === P1DestinationName.IMAGE_PROBE) {
      NavDestination() {
        this.imageProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .backgroundColor($r('app.color.page_background'))
    } else if (name === P1DestinationName.DATABASE_PROBE) {
      NavDestination() {
        this.databaseProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .backgroundColor($r('app.color.page_background'))
    } else if (name === P1DestinationName.DEEP_LINK_PROBE) {
      NavDestination() {
        this.deepLinkProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .backgroundColor($r('app.color.page_background'))
    } else if (name === P1DestinationName.QR_SCAN_PROBE) {
      NavDestination() {
        this.qrScanProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .backgroundColor($r('app.color.page_background'))
    } else if (name === P1DestinationName.BACKGROUND_TASK_PROBE) {
      NavDestination() {
        this.backgroundTaskProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .backgroundColor($r('app.color.page_background'))
    } else if (name === P1DestinationName.DOMAIN_FIXTURE_PROBE) {
      NavDestination() {
        this.domainFixtureProbeContent((): void => {
          this.pathStack.pop();
        });
      }
      .backgroundColor($r('app.color.page_background'))
    } else {
      NavDestination() {
        this.businessPlaceholder(decodeP1Destination(name, param) as P1Destination);
      }
      .title(name)
      .backgroundColor($r('app.color.page_background'))
    }
  }

  build() {
    Navigation(this.pathStack) {
      Stack({ alignContent: Alignment.TopStart }) {
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
              const destination: P1Destination = { name: P1DestinationName.SETTINGS };
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
              const destination: P1Destination = { name: P1DestinationName.TECHNICAL_LAB };
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
        .id('p1_home_scroll')
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .backgroundColor($r('app.color.page_background'))
      }
      .id('p1_home_top_start_container')
      .width('100%')
      .height('100%')
      .alignContent(Alignment.TopStart)
      .backgroundColor($r('app.color.page_background'))
    }
    .title('Zhihu++')
    .titleMode(NavigationTitleMode.Mini)
    .hideBackButton(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.destinationBuilder)
    .backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  settingsPage() {
    Stack({ alignContent: Alignment.TopStart }) {
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
            this.themeButton('跟随系统', AppThemeMode.SYSTEM, 'p1_theme_system');
            this.themeButton('浅色', AppThemeMode.LIGHT, 'p1_theme_light');
            this.themeButton('深色', AppThemeMode.DARK, 'p1_theme_dark');
          }
          .width('100%')

          Text(this.themePersistenceStatus)
            .id('p1_theme_persistence_status')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
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
      .id('p1_settings_scroll')
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .backgroundColor($r('app.color.page_background'))
    }
    .id('p1_settings_top_start_container')
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  themeButton(label: string, mode: AppThemeMode, testId: string) {
    Button(label)
      .id(testId)
      .width('100%')
      .fontSize($r('app.float.p1_secondary_font_size'))
      .fontColor(this.themeMode === mode ? $r('app.color.on_brand') : $r('app.color.primary_text'))
      .backgroundColor(this.themeMode === mode ? $r('app.color.brand_primary') : $r('app.color.control_background'))
      .onClick(() => {
        this.selectThemeMode(mode);
      })
  }

  @Builder
  invalidDestinationPage() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: $r('app.float.p1_spacing_small') }) {
        Text('导航参数无效')
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontColor($r('app.color.primary_text'))
        Text('页面参数未通过校验，请返回后重试。')
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.secondary_text'))
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding($r('app.float.p1_page_padding'))
      .align(Alignment.TopStart)
    }
    .id('p1_invalid_destination_top_start_container')
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  businessPlaceholder(destination: P1Destination) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: $r('app.float.p1_spacing_small') }) {
        Text(destination.name)
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
        Text(this.destinationDescription(destination))
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.secondary_text'))
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding($r('app.float.p1_page_padding'))
      .align(Alignment.TopStart)
    }
    .id('p1_business_destination_top_start_container')
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
    .backgroundColor($r('app.color.page_background'))
  }

  private navigate(destination: P1Destination): void {
    if (destination.name === P1DestinationName.HOME) {
      this.pathStack.clear();
      return;
    }
    const paths: Array<NavPathInfo> | undefined = this.pathStack.getPathStack();
    if (paths !== undefined && paths.length > 0) {
      const current = paths[paths.length - 1];
      if (current.param instanceof Object) {
        const currentDestination = decodeP1Destination(current.name, current.param);
        if (!shouldPushP1Destination(currentDestination, destination)) {
          return;
        }
      }
    }
    const path: NavPathInfo = { name: destination.name, param: destination };
    if (isInfrastructureDestination(destination)) {
      this.pathStack.pushPath(path, { launchMode: LaunchMode.MOVE_TO_TOP_SINGLETON });
    } else {
      this.pathStack.pushPath(path);
    }
  }

  private destinationDescription(destination: P1Destination): string {
    if (destination.name === P1DestinationName.SEARCH) {
      return `搜索：${destination.query}`;
    }
    if (destination.name === P1DestinationName.COMMENT) {
      return `内容：${destination.contentId}`;
    }
    if (destination.name === P1DestinationName.NOTIFICATION) {
      return '通知页面将在后续业务迁移阶段接入。';
    }
    const content = destination as ContentDestination;
    return `内容 ID：${content.id}`;
  }

  private async restoreThemeMode(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const generation = this.themeOperationGuard.next();
    try {
      await this.themeSaveQueue.catch((_error: Error): void => {
      });
      if (!this.themeMounted || !this.themeOperationGuard.isCurrent(generation)) {
        return;
      }
      const mode = await new AppPreferencesStore(context).loadThemeMode();
      if (!this.themeMounted || !this.themeOperationGuard.isCurrent(generation)) {
        return;
      }
      this.themePersistenceStatus = this.applyThemeMode(context, mode)
        ? '主题设置已恢复'
        : '主题模式应用失败，请重试';
    } catch (_error) {
      if (!this.themeMounted || !this.themeOperationGuard.isCurrent(generation)) {
        return;
      }
      this.themePersistenceStatus = this.applyThemeMode(context, AppThemeMode.SYSTEM)
        ? '无法读取已保存主题，当前跟随系统'
        : '无法读取或应用主题设置，请重试';
    }
  }

  private async selectThemeMode(mode: AppThemeMode): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const generation = this.themeOperationGuard.next();
    if (!this.applyThemeMode(context, mode)) {
      this.themePersistenceStatus = '主题模式应用失败，请重试';
      return;
    }
    this.themePersistenceStatus = '正在保存主题设置…';
    const pendingSave = this.themeSaveQueue.catch((_error: Error): void => {
    }).then((): Promise<void> => {
      if (!this.themeMounted || !this.themeOperationGuard.isCurrent(generation)) {
        return Promise.resolve();
      }
      return new AppPreferencesStore(context).saveThemeMode(mode);
    });
    this.themeSaveQueue = pendingSave;
    try {
      await pendingSave;
      if (this.themeMounted && this.themeOperationGuard.isCurrent(generation)) {
        this.themePersistenceStatus = '主题设置已保存';
      }
    } catch (_error) {
      if (this.themeMounted && this.themeOperationGuard.isCurrent(generation)) {
        this.themePersistenceStatus = '主题已应用，但本次未保存；重启后可能恢复此前设置';
      }
    }
  }

  private applyThemeMode(context: common.UIAbilityContext, mode: AppThemeMode): boolean {
    try {
      if (mode === AppThemeMode.DARK) {
        context.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } else if (mode === AppThemeMode.LIGHT) {
        context.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      } else {
        context.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      }
      this.themeMode = mode;
      return true;
    } catch (_error) {
      return false;
    }
  }
}
