import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { AppLogEvent, AppLogger } from '../logging/AppLogger';
import { resolveZhihuLink } from '../navigation/DeepLinkResolver';
import {
  AppStartup,
  SystemStartupClock,
  StartupPhase,
  StartupPhaseStatus,
  StartupTask
} from '../startup/AppStartup';

export default class EntryAbility extends UIAbility {
  private startup: AppStartup | undefined = undefined;

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    AppLogger.info(AppLogEvent.ABILITY_CREATED);
    const tasks: Array<StartupTask> = [
      {
        name: 'deep-link-routing',
        phase: StartupPhase.CRITICAL,
        dependencies: [],
        run: (): Promise<void> => {
          this.logIncomingLink(want);
          return Promise.resolve();
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
    this.logIncomingLink(want);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.loadContentAfterCriticalStartup(windowStage);
  }

  private async loadContentAfterCriticalStartup(windowStage: window.WindowStage): Promise<void> {
    if (this.startup === undefined) {
      AppLogger.failure(AppLogEvent.STARTUP_NOT_READY);
      return;
    }
    const criticalSummary = await this.startup.runCritical();
    if (criticalSummary.status !== StartupPhaseStatus.SUCCEEDED) {
      AppLogger.failure(AppLogEvent.STARTUP_NOT_READY);
      return;
    }

    windowStage.loadContent('pages/Index', (error) => {
      if (error.code) {
        AppLogger.failure(AppLogEvent.CONTENT_LOAD_FAILED, error.code);
        return;
      }
      this.startup?.runDeferred();
    });
  }

  private logIncomingLink(want: Want): void {
    if (want.uri === undefined || want.uri.length === 0) {
      return;
    }
    const destination = resolveZhihuLink(want.uri);
    AppLogger.info(destination === undefined
      ? AppLogEvent.DEEP_LINK_UNSUPPORTED
      : AppLogEvent.DEEP_LINK_RESOLVED);
  }
}
