import { describe, expect, it } from '@ohos/hypium';
import {
  AppStartup,
  StartupClock,
  StartupPhase,
  StartupPhaseStatus,
  StartupTask,
  StartupTaskStatus
} from '../main/ets/startup/AppStartup';

class StepClock implements StartupClock {
  private current: number = 0;

  now(): number {
    this.current += 5;
    return this.current;
  }
}

export default function appStartupTest(): void {
  describe('appStartupTest', () => {
    it('runsCriticalTasksInDeterministicDependencyOrder', 0, async () => {
      const executionOrder: Array<string> = [];
      const tasks: Array<StartupTask> = [
        startupTask('content', StartupPhase.CRITICAL, ['account', 'storage'], executionOrder),
        startupTask('storage', StartupPhase.CRITICAL, [], executionOrder),
        startupTask('account', StartupPhase.CRITICAL, [], executionOrder)
      ];

      const summary = await new AppStartup(tasks, new StepClock()).runCritical();

      expect(executionOrder.join(',')).assertEqual('account,storage,content');
      expect(summary.status).assertEqual(StartupPhaseStatus.SUCCEEDED);
      expect(summary.tasks.length).assertEqual(3);
      expect(summary.tasks[0].durationMs).assertEqual(5);
    });

    it('runsEachPhaseOnlyOnce', 0, async () => {
      let criticalRuns = 0;
      let deferredRuns = 0;
      const startup = new AppStartup([
        {
          name: 'critical',
          phase: StartupPhase.CRITICAL,
          dependencies: [],
          run: (): Promise<void> => {
            criticalRuns += 1;
            return Promise.resolve();
          }
        },
        {
          name: 'deferred',
          phase: StartupPhase.DEFERRED,
          dependencies: ['critical'],
          run: (): Promise<void> => {
            deferredRuns += 1;
            return Promise.resolve();
          }
        }
      ]);

      await startup.runCritical();
      await startup.runCritical();
      await startup.runDeferred();
      await startup.runDeferred();

      expect(criticalRuns).assertEqual(1);
      expect(deferredRuns).assertEqual(1);
    });

    it('isolatesDeferredFailuresAndSkipsOnlyDependents', 0, async () => {
      const executionOrder: Array<string> = [];
      const startup = new AppStartup([
        startupTask('critical', StartupPhase.CRITICAL, [], executionOrder),
        startupTask('cache-warmup', StartupPhase.DEFERRED, ['critical'], executionOrder, true),
        startupTask('cache-index', StartupPhase.DEFERRED, ['cache-warmup'], executionOrder),
        startupTask('telemetry', StartupPhase.DEFERRED, ['critical'], executionOrder)
      ]);

      const summary = await startup.runDeferred();

      expect(summary.status).assertEqual(StartupPhaseStatus.DEGRADED);
      expect(executionOrder.join(',')).assertEqual('critical,cache-warmup,telemetry');
      expect(summary.tasks[0].status).assertEqual(StartupTaskStatus.FAILED);
      expect(summary.tasks[1].status).assertEqual(StartupTaskStatus.SKIPPED);
      expect(summary.tasks[2].status).assertEqual(StartupTaskStatus.SUCCEEDED);
    });

    it('doesNotRunDeferredTasksAfterCriticalFailure', 0, async () => {
      const executionOrder: Array<string> = [];
      const startup = new AppStartup([
        startupTask('critical', StartupPhase.CRITICAL, [], executionOrder, true),
        startupTask('deferred', StartupPhase.DEFERRED, ['critical'], executionOrder)
      ]);

      const criticalSummary = await startup.runCritical();
      const deferredSummary = await startup.runDeferred();

      expect(criticalSummary.status).assertEqual(StartupPhaseStatus.FAILED);
      expect(deferredSummary.status).assertEqual(StartupPhaseStatus.DEGRADED);
      expect(deferredSummary.tasks[0].status).assertEqual(StartupTaskStatus.SKIPPED);
      expect(executionOrder.join(',')).assertEqual('critical');
    });
  });
}

function startupTask(name: string, phase: StartupPhase, dependencies: Array<string>,
  executionOrder: Array<string>, shouldFail: boolean = false): StartupTask {
  return {
    name: name,
    phase: phase,
    dependencies: dependencies,
    run: (): Promise<void> => {
      executionOrder.push(name);
      return shouldFail
        ? Promise.reject(new Error('test failure'))
        : Promise.resolve();
    }
  };
}
