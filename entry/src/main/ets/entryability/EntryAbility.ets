import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { AppSessionOwner, closeAppDatabase, getAppDatabase, getAppSessionOwner } from 'data';
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

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.lifecycleGeneration = this.lifecycleGuard.next();
    setAbilityContext(this.context);
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

  onWindowStageCreate(windowStage: window.WindowStage): void {
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
}
