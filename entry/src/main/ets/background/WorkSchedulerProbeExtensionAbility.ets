import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';

export default class WorkSchedulerProbeExtensionAbility extends WorkSchedulerExtensionAbility {
  onWorkStart(work: workScheduler.WorkInfo): void {
    try {
      workScheduler.stopWork(work, false);
    } catch (_error) {
    }
  }
}
