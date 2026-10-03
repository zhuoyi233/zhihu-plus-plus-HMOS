import { AbilityConstant, abilityAccessCtrl, Configuration, ConfigurationConstant, Permissions,
  PermissionRequestResult, UIAbility, Want } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { resourceManager } from '@kit.LocalizationKit';
import { AppSessionOwner, AppThemeMode, closeAppDatabase, ContentDraftStore, DEFAULT_THEME_COLOR,
  formulaForegroundColorForColorMode, getAppDatabase, getAppSessionOwner, normalizeThemeColor,
  resolveThemeColorForDark } from 'data';
import { clearAbilityContext, setAbilityContext } from './AbilityContextHolder';
import { maintainControlledImageCaches } from '../platform/ControlledImageCacheMaintenance';
import { purgeExpiredShareTemporaryFiles } from '../platform/SystemShareTemporaryCleaner';
import {
  appDestinationIdentity,
  AppLogEvent,
  AppLogger,
  AppStartup,
  extractZhihuLinkFromText,
  LatestOperationGuard,
  resolveZhihuLink,
  startupDestinationChannel,
  SystemStartupClock,
  toAppDestination,
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
  // 上游语义（MainActivity.onWindowFocusChanged）：intent 携带链接时不做剪切板识别，
  // 且剪切板目的地与上次相同（含经深链跳转标记的）不重复导航。
  private wantHasUriLink: boolean = false;
  private lastClipboardDestinationIdentity: string | undefined = undefined;
  private clipboardPermissionDenied: boolean = false;

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
          this.wantHasUriLink = this.routeIncomingLink(want);
          return Promise.resolve();
        }
      },
      {
        name: 'cache-maintenance',
        phase: StartupPhase.DEFERRED,
        dependencies: ['deep-link-routing'],
        run: (): Promise<void> => {
          // 先完成全账号草稿引用扫描，再回收无引用的过期受控缓存；失败不影响启动。
          return Promise.all([
            maintainControlledImageCaches(this.context.cacheDir, new ContentDraftStore(getAppDatabase(this.context))),
            purgeExpiredShareTemporaryFiles(this.context.cacheDir)
          ]).then((): void => {
          });
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
    this.wantHasUriLink = this.routeIncomingLink(want);
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
    // AppShell 主题恢复前 appThemeMode 未广播，默认按跟随系统处理（与其初始广播值一致）。
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
    mainWindow.on('windowEvent', (event: window.WindowEventType): void => {
      // 对齐上游 MainActivity.onWindowFocusChanged：窗口获得焦点（含冷启动与回前台）时
      // 识别剪切板；剪切板读取要求焦点就绪，onForeground 时系统会拒绝访问，不能挂在那里。
      if (event === window.WindowEventType.WINDOW_ACTIVE) {
        this.readClipboardForNavigation();
      }
    });
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
      // 状态栏高度存入 AppStorage，由 AppShell 根 Navigation 统一做顶部补偿。
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

  private routeIncomingLink(want: Want): boolean {
    if (want.uri === undefined || want.uri.length === 0) {
      return false;
    }
    const destination = resolveZhihuLink(want.uri);
    if (destination === undefined) {
      AppLogger.info(AppLogEvent.DEEP_LINK_UNSUPPORTED);
      return true;
    }
    // 上游 handleIntentData 同样会把 intent 命中的目的地记入剪切板去重标记。
    this.lastClipboardDestinationIdentity = appDestinationIdentity(toAppDestination(destination));
    startupDestinationChannel.publish(toAppDestination(destination));
    AppLogger.info(AppLogEvent.DEEP_LINK_RESOLVED);
    return true;
  }

  private readClipboardForNavigation(): void {
    if (this.wantHasUriLink || this.clipboardPermissionDenied) {
      return;
    }
    // READ_PASTEBOARD 是 user_grant 权限，仅声明不会自动弹窗，需显式申请；
    // 授权结果进程内记忆，避免每次窗口聚焦都触发授权请求。
    const permissions: Array<Permissions> = ['ohos.permission.READ_PASTEBOARD'];
    abilityAccessCtrl.createAtManager().requestPermissionsFromUser(this.context, permissions)
      .then((result: PermissionRequestResult): Promise<void> => {
        if (result.authResults[0] !== 0) {
          this.clipboardPermissionDenied = true;
          return Promise.resolve();
        }
        return pasteboard.getSystemPasteboard().getData().then((pasteData: pasteboard.PasteData): void => {
          const text: string = pasteData.getPrimaryText();
          if (text.length === 0) {
            return;
          }
          const destination = extractZhihuLinkFromText(text);
          if (destination === undefined) {
            return;
          }
          const identity = appDestinationIdentity(toAppDestination(destination));
          if (identity === this.lastClipboardDestinationIdentity) {
            return;
          }
          this.lastClipboardDestinationIdentity = identity;
          startupDestinationChannel.publish(toAppDestination(destination));
          AppLogger.info(AppLogEvent.CLIPBOARD_LINK_RESOLVED);
        });
      })
      .catch((error: BusinessError): void => {
        AppLogger.failure(AppLogEvent.CLIPBOARD_READ_FAILED, error.code);
      });
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
