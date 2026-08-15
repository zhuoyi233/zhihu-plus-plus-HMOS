import { backgroundTaskManager, workScheduler } from '@kit.BackgroundTasksKit';

const PROBE_WORK_ID: number = 24001;
const PROBE_BUNDLE_NAME: string = 'com.github.zhuoyi233.zhplus';
const PROBE_ABILITY_NAME: string = 'WorkSchedulerProbeExtensionAbility';
const DEFERRED_START_DELAY_MS: number = 60_000;

export interface TransientTaskProbeResult {
  actualDelayMs: number;
  remainingDelayMs: number;
  remainingQuotaMs: number;
}

export interface DeferredTaskProbeResult {
  workId: number;
  registeredWorkCount: number;
  remainingWorkCount: number;
  earliestStartDelayMs: number;
}

export class BackgroundTaskProbe {
  async probeTransientTask(): Promise<TransientTaskProbeResult> {
    const delayInfo = backgroundTaskManager.requestSuspendDelay(
      'user-initiated operation completion probe',
      () => {}
    );
    try {
      const remainingDelayMs = await backgroundTaskManager.getRemainingDelayTime(delayInfo.requestId);
      const transientInfo = await backgroundTaskManager.getTransientTaskInfo();
      return {
        actualDelayMs: delayInfo.actualDelayTime,
        remainingDelayMs,
        remainingQuotaMs: transientInfo.remainingQuota
      };
    } finally {
      backgroundTaskManager.cancelSuspendDelay(delayInfo.requestId);
    }
  }

  async probeDeferredTask(): Promise<DeferredTaskProbeResult> {
    const work: workScheduler.WorkInfo = {
      workId: PROBE_WORK_ID,
      bundleName: PROBE_BUNDLE_NAME,
      abilityName: PROBE_ABILITY_NAME,
      isPersisted: false,
      networkType: workScheduler.NetworkType.NETWORK_TYPE_ANY,
      earliestStartTime: DEFERRED_START_DELAY_MS,
      parameters: {
        purpose: 'probe-background-boundary'
      }
    };
    workScheduler.startWork(work);
    try {
      const registered = await workScheduler.getWorkStatus(PROBE_WORK_ID);
      const allWorks = await workScheduler.obtainAllWorks();
      workScheduler.stopWork(work, true);
      const remainingWorks = await workScheduler.obtainAllWorks();
      return {
        workId: registered.workId,
        registeredWorkCount: allWorks.filter((item: workScheduler.WorkInfo) =>
          item.workId === PROBE_WORK_ID).length,
        remainingWorkCount: remainingWorks.filter((item: workScheduler.WorkInfo) =>
          item.workId === PROBE_WORK_ID).length,
        earliestStartDelayMs: registered.earliestStartTime ?? DEFERRED_START_DELAY_MS
      };
    } catch (error) {
      const originalError = error instanceof Error ? error : new Error('延迟任务登记或清理失败');
      try {
        workScheduler.stopWork(work, true);
      } catch (_error) {
      }
      throw originalError;
    }
  }
}
