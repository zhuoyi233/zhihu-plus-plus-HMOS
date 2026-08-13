import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';

export default class P0WorkSchedulerExtensionAbility extends WorkSchedulerExtensionAbility {
  onWorkStart(work: workScheduler.WorkInfo): void {
    try {
      workScheduler.stopWork(work, false);
    } catch (_error) {
    }
  }
}
