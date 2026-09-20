import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';
import { AppSessionOwner, AppThemeMode, closeAppDatabase, DEFAULT_THEME_COLOR, formulaForegroundColorForColorMode,
  getAppDatabase, getAppSessionOwner, normalizeThemeColor, resolveThemeColorForDark } from 'data';
import { clearAbilityContext, setAbilityContext } from './AbilityContextHolder';
import {
  AppLogEvent,
  AppLogger,
  AppStartup,
  LatestOperationGuard,
  resolveZhihuLink,
  startupDestinationChannel,
  SystemStartupClock,
  toP1Destination,
  StartupPhase,
  StartupPhaseStatus,
  StartupTask
} from 'core';

export default class EntryAbility extends UIAbility {
  private startup: AppStartup | undefined = undefined;
  private sessionOwner: AppSessionOwner | undefined = undefined;
  private readonly lifecycleGuard: LatestOperationGuard = new LatestOperationGuard();
  private lifecycleGeneration: number = 0;
  private lastObservedIsDark: boolean | undefined = undefined;

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.lifecycleGeneration = this.lifecycleGuard.next();
    setAbilityContext(this.context);
    this.lastObservedIsDark = this.readSystemIsDark();
    AppLogger.info(AppLogEvent.ABILITY_CREATED);
    this.sessionOwner = getAppSessionOwner(this.context);
    const tasks: Array<StartupTask> = [
      {
        name: 'database-migration',
        phase: StartupPhase.CRITICAL,
        dependencies: [],
        run: (): Promise<void> => {
          return getAppDatabase(this.context).open().then((): void => {
          });
        }
      },
      {
        name: 'deep-link-routing',
        phase: StartupPhase.CRITICAL,
        dependencies: ['database-migration'],
        run: (): Promise<void> => {
          this.routeIncomingLink(want);
          return Promise.resolve();
        }
      },
      {
        name: 'session-restore',
        phase: StartupPhase.DEFERRED,
        dependencies: ['deep-link-routing'],
        run: (): Promise<void> => {
          return this.sessionOwner?.restoreDeferred().then((): void => {
          }) ?? Promise.resolve();
        }
      },
      {
        name: 'app-ready-diagnostic',
        phase: StartupPhase.DEFERRED,
        dependencies: ['deep-link-routing'],
        run: (): Promise<void> => {
          AppLogger.info(AppLogEvent.APP_READY);
          return Promise.resolve();
        }
      }
    ];
    this.startup = new AppStartup(tasks, new SystemStartupClock(), (summary) => {
      AppLogger.startupSummary(summary);
    });
    this.startup.runCritical();
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.routeIncomingLink(want);
  }

  /**
   * 系统深浅色切换联动：应用为“跟随系统”时，按新的 colorMode 刷新公式前景色并递增主题 tick，
   * 让已栅格化的公式（currentColor 已固化，无法随主题自动变色）重新解码。
   * 刚 setColorMode(COLOR_MODE_NOT_SET) 后同步读配置可能读到切换前状态，因此颜色一律取
   * 回调携带的新配置，而不是再查一次当前配置。
   */
  onConfigurationUpdate(newConfig: Configuration): void {
    // resourceManager.ColorMode 与 ConfigurationConstant.ColorMode 取值不同，统一归一为 boolean。
    const isDark = newConfig.colorMode !== undefined
      ? newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      : this.readSystemIsDark();
    if (isDark === undefined || isDark === this.lastObservedIsDark) {
      return;
    }
    this.lastObservedIsDark = isDark;
    // P1Shell 主题恢复前 appThemeMode 未广播，默认按跟随系统处理（与其初始广播值一致）。
    const themeMode = AppStorage.get<AppThemeMode>('appThemeMode') ?? AppThemeMode.SYSTEM;
    if (themeMode !== AppThemeMode.SYSTEM) {
      return;
    }
    AppStorage.setOrCreate('formulaForegroundColor', formulaForegroundColorForColorMode(isDark));
    // 跟随系统时，系统深浅色切换联动主题色生效值（seed 不变，仅重算解析色）。
    const themeColorSeed = normalizeThemeColor(AppStorage.get<string>('themeColor') ?? DEFAULT_THEME_COLOR);
    AppStorage.setOrCreate('resolvedThemeColor',
      isDark ? resolveThemeColorForDark(themeColorSeed) : themeColorSeed);
    AppStorage.setOrCreate('appearanceThemeTick',
      (AppStorage.get<number>('appearanceThemeTick') ?? 0) + 1);
  }

  private readSystemIsDark(): boolean | undefined {
    try {
      return this.context.resourceManager.getConfigurationSync().colorMode ===
        resourceManager.ColorMode.DARK;
    } catch (_error) {
      return undefined;
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    const mainWindow = windowStage.getMainWindowSync();
    this.configureImmersiveWindow(mainWindow);
    mainWindow.on('windowSizeChange', (): void => this.configureImmersiveWindow(mainWindow));
    mainWindow.on('avoidAreaChange', (data: window.AvoidAreaOptions): void => {
      if (data.type === window.AvoidAreaType.TYPE_SYSTEM ||
        data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
        this.publishAvoidArea(data.type, data.area);
      }
    });
    this.loadContentAfterCriticalStartup(windowStage, this.lifecycleGeneration);
  }

  onDestroy(): void {
    this.lifecycleGuard.invalidate();
    clearAbilityContext();
    this.sessionOwner?.cancelInFlightVerification();
    closeAppDatabase().catch((_error: Error): void => {
    });
  }

  private async loadContentAfterCriticalStartup(windowStage: window.WindowStage,
    lifecycleGeneration: number): Promise<void> {
    if (this.startup === undefined) {
      AppLogger.failure(AppLogEvent.STARTUP_NOT_READY);
      return;
    }
    const criticalSummary = await this.startup.runCritical();
    if (!this.lifecycleGuard.isCurrent(lifecycleGeneration)) {
      return;
    }
    if (criticalSummary.status !== StartupPhaseStatus.SUCCEEDED) {
      AppLogger.failure(AppLogEvent.STARTUP_NOT_READY);
      return;
    }

    windowStage.loadContent('pages/Index', (error) => {
      if (!this.lifecycleGuard.isCurrent(lifecycleGeneration)) {
        return;
      }
      if (error.code) {
        AppLogger.failure(AppLogEvent.CONTENT_LOAD_FAILED, error.code);
        return;
      }
      // 完全沉浸：窗口全屏布局，彻底移除状态栏/导航条避让区（布局直达物理底边）；
      // 状态栏高度存入 AppStorage，由 P1Shell 根 Navigation 统一做顶部补偿。
      try {
        const mainWindow = windowStage.getMainWindowSync();
        mainWindow.setWindowLayoutFullScreen(true).catch((_error: Error): void => {
        });
        mainWindow.setWindowSystemBarProperties({
          navigationBarColor: '#00000000'
        }).catch((_error: Error): void => {
        });
        const statusArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        const density = display.getDefaultDisplaySync().densityPixels;
        if (density > 0) {
          AppStorage.setOrCreate('statusBarHeightVp', statusArea.topRect.height / density);
        }
      } catch (_error) {
      }
      this.startup?.runDeferred();
    });
  }

  private routeIncomingLink(want: Want): void {
    if (want.uri === undefined || want.uri.length === 0) {
      return;
    }
    const destination = resolveZhihuLink(want.uri);
    if (destination === undefined) {
      AppLogger.info(AppLogEvent.DEEP_LINK_UNSUPPORTED);
      return;
    }
    startupDestinationChannel.publish(toP1Destination(destination));
    AppLogger.info(AppLogEvent.DEEP_LINK_RESOLVED);
  }

  private configureImmersiveWindow(mainWindow: window.Window): void {
    mainWindow.setImmersiveModeEnabledState(true);
    void mainWindow.setWindowSystemBarProperties({
      navigationBarColor: '#00000000',
      statusBarColor: '#00000000',
      statusBarContentColor: '#000000',
      isStatusBarLightIcon: true
    });
    this.publishAvoidAreas(mainWindow);
  }

  private publishAvoidAreas(mainWindow: window.Window): void {
    const systemArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    const navigationArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    this.publishAvoidArea(window.AvoidAreaType.TYPE_SYSTEM, systemArea);
    this.publishAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR, navigationArea);
  }

  private publishAvoidArea(type: window.AvoidAreaType, area: window.AvoidArea): void {
    const density = display.getDefaultDisplaySync().densityPixels;
    const safeDensity = density > 0 ? density : 1;
    if (type === window.AvoidAreaType.TYPE_SYSTEM) {
      const top = area.topRect.height / safeDensity;
      AppStorage.setOrCreate('statusBarHeight', top);
      AppStorage.setOrCreate('topRectHeight', top);
      return;
    }
    AppStorage.setOrCreate('bottomRectHeight', area.bottomRect.height / safeDensity);
  }
}
