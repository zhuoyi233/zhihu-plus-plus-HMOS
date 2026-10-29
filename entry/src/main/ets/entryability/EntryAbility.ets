import { hilog } from '@kit.PerformanceAnalysisKit';
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
import { bindSystemBarWindow, detachSystemBarWindow, retryStatusBarVisibility, setStatusBarHidden, updateStatusBarAppearance } from '../platform/SystemBars';
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
  private windowGeneration: number = 0;
  private currentWindow: window.Window | undefined = undefined;
  private windowCleanup: Array<() => void> = [];
  private avoidAreaListening: boolean = false;
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
    if (newConfig.fontSizeScale !== undefined) {
      AppStorage.setOrCreate('systemFontSizeScale', newConfig.fontSizeScale);
    }
    // resourceManager.ColorMode 与 ConfigurationConstant.ColorMode 取值不同，统一归一为 boolean。
    const isDark = newConfig.colorMode !== undefined
      ? newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      : this.readSystemIsDark();
    updateStatusBarAppearance(isDark);
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
    AppStorage.setOrCreate('systemFontSizeScale', this.context.config.fontSizeScale ?? 1);
    const mainWindow = windowStage.getMainWindowSync();
    this.releaseWindow();
    this.currentWindow = mainWindow;
    const generation = this.windowGeneration;
    bindSystemBarWindow(mainWindow);
    this.configureImmersiveWindow(mainWindow);
    const sizeChanged = (): void => {
      if (generation === this.windowGeneration) { this.configureImmersiveWindow(mainWindow); }
    };
    const windowEvent = (event: window.WindowEventType): void => {
      if (generation !== this.windowGeneration) { return; }
      if (event === window.WindowEventType.WINDOW_ACTIVE) {
        AppStorage.setOrCreate('systemFontSizeScale', this.context.config.fontSizeScale ?? 1);
        retryStatusBarVisibility();
        this.ensureAvoidAreaListener(mainWindow, generation);
        this.publishAvoidAreas(mainWindow);
        updateStatusBarAppearance();
        this.readClipboardForNavigation();
      }
    };
    try {
      mainWindow.on('windowSizeChange', sizeChanged);
      this.windowCleanup.push((): void => mainWindow.off('windowSizeChange', sizeChanged));
    } catch (_error) { this.logWindowListenerFailure('windowSizeChange'); }
    try {
      mainWindow.on('windowEvent', windowEvent);
      this.windowCleanup.push((): void => mainWindow.off('windowEvent', windowEvent));
    } catch (_error) { this.logWindowListenerFailure('windowEvent'); }
    this.ensureAvoidAreaListener(mainWindow, generation);
    void this.loadContentAfterCriticalStartup(windowStage, this.lifecycleGeneration, generation);
  }

  private ensureAvoidAreaListener(mainWindow: window.Window, generation: number): void {
    if (this.avoidAreaListening || generation !== this.windowGeneration) { return; }
    const changed = (data: window.AvoidAreaOptions): void => {
      if (generation !== this.windowGeneration) { return; }
      if (data.type === window.AvoidAreaType.TYPE_SYSTEM ||
        data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
        this.publishAvoidArea(data.type, data.area);
      }
    };
    try {
      mainWindow.on('avoidAreaChange', changed);
      this.avoidAreaListening = true;
      this.windowCleanup.push((): void => mainWindow.off('avoidAreaChange', changed));
    } catch (_error) { this.logWindowListenerFailure('avoidAreaChange'); }
  }

  private logWindowListenerFailure(event: string): void {
    hilog.warn(0x0000, 'EntryAbility', 'window listener unavailable: %{public}s', event);
  }

  onWindowStageDestroy(): void { this.releaseWindow(); }

  private releaseWindow(): void {
    this.windowGeneration += 1;
    this.currentWindow = undefined;
    this.avoidAreaListening = false;
    detachSystemBarWindow();
    for (const cleanup of this.windowCleanup) {
      try { cleanup(); } catch (_error) { }
    }
    this.windowCleanup = [];
  }

  onDestroy(): void {
    this.lifecycleGuard.invalidate();
    this.releaseWindow();
    setStatusBarHidden(false);
    clearAbilityContext();
    this.sessionOwner?.cancelInFlightVerification();
    closeAppDatabase().catch((_error: Error): void => {
    });
  }

  private async loadContentAfterCriticalStartup(windowStage: window.WindowStage,
    lifecycleGeneration: number, windowGeneration: number): Promise<void> {
    if (this.startup === undefined) {
      AppLogger.failure(AppLogEvent.STARTUP_NOT_READY);
      return;
    }
    const criticalSummary = await this.startup.runCritical();
    if (!this.lifecycleGuard.isCurrent(lifecycleGeneration) || windowGeneration !== this.windowGeneration) {
      return;
    }
    if (criticalSummary.status !== StartupPhaseStatus.SUCCEEDED) {
      AppLogger.failure(AppLogEvent.STARTUP_NOT_READY);
      return;
    }

    windowStage.loadContent('pages/Index', (error) => {
      if (!this.lifecycleGuard.isCurrent(lifecycleGeneration) || windowGeneration !== this.windowGeneration) {
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

  onBackground(): void {
    const tick = AppStorage.get<number>('readerPositionFlushTick') ?? 0;
    AppStorage.setOrCreate('readerPositionFlushTick', tick + 1);
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
    if (mainWindow !== this.currentWindow) { return; }
    try { mainWindow.setImmersiveModeEnabledState(true); } catch (_error) { }
    try {
      void mainWindow.setWindowSystemBarProperties({
        navigationBarColor: '#00000000',
        statusBarColor: '#00000000'
      }).catch((_error: Object): void => {});
    } catch (_error) { this.logWindowListenerFailure('setWindowSystemBarProperties'); }
    updateStatusBarAppearance();
    this.publishAvoidAreas(mainWindow);
  }

  private publishAvoidAreas(mainWindow: window.Window): void {
    if (mainWindow !== this.currentWindow) { return; }
    try {
      this.publishAvoidArea(window.AvoidAreaType.TYPE_SYSTEM,
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM));
      this.publishAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR,
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR));
    } catch (_error) { this.logWindowListenerFailure('getWindowAvoidArea'); }
  }

  private publishAvoidArea(type: window.AvoidAreaType, area: window.AvoidArea): void {
    const density = display.getDefaultDisplaySync().densityPixels;
    const safeDensity = density > 0 ? density : 1;
    if (type === window.AvoidAreaType.TYPE_SYSTEM) {
      const top = area.topRect.height / safeDensity;
      AppStorage.setOrCreate('statusBarHeight', top);
      AppStorage.setOrCreate('statusBarHeightVp', top);
      AppStorage.setOrCreate('topRectHeight', top);
      return;
    }
    AppStorage.setOrCreate('bottomRectHeight', area.bottomRect.height / safeDensity);
  }
}
