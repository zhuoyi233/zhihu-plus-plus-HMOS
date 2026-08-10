import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';

export default class P0WorkSchedulerExtensionAbility extends WorkSchedulerExtensionAbility {
  onWorkStart(work: workScheduler.WorkInfo): void {
    try {
      workScheduler.stopWork(work, false);
    } catch (_error) {
      // The UI probe can cancel this one-off work before the callback runs; that race is already a clean stop.
    }
  }
}
