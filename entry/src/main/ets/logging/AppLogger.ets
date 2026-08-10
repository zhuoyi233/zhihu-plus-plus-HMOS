import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  StartupPhaseSummary,
  StartupTaskResult
} from '../startup/AppStartup';

const LOG_DOMAIN = 0xD001;
const LOG_TAG = 'ZhihuPlusStartup';

export enum AppLogEvent {
  ABILITY_CREATED = 'ability-created',
  APP_READY = 'app-ready',
  CONTENT_LOAD_FAILED = 'content-load-failed',
  DEEP_LINK_RESOLVED = 'deep-link-resolved',
  DEEP_LINK_UNSUPPORTED = 'deep-link-unsupported',
  STARTUP_NOT_READY = 'startup-not-ready'
}

export class AppLogger {
  static info(event: AppLogEvent): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'event=%{public}s', event);
  }

  static failure(event: AppLogEvent, errorCode: number = 0): void {
    hilog.error(LOG_DOMAIN, LOG_TAG, 'event=%{public}s code=%{public}d', event, errorCode);
  }

  static startupSummary(summary: StartupPhaseSummary): void {
    const taskSummary = summary.tasks.map((task: StartupTaskResult) =>
      `${this.safeTaskName(task.name)}:${task.status}:${task.durationMs}`).join(',');
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'startup phase=%{public}s status=%{public}s durationMs=%{public}d tasks=%{public}s',
      summary.phase, summary.status, summary.durationMs, taskSummary);
  }

  private static safeTaskName(name: string): string {
    return /^[a-z][a-z0-9-]{0,47}$/.test(name) ? name : 'invalid-task';
  }
}
