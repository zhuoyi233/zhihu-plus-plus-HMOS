import { describe, expect, it } from '@ohos/hypium';
import {
  AppStartup,
  LatestOperationGuard,
  P1Destination,
  p1DestinationIdentity,
  P1DestinationName,
  StartupDestinationChannel,
  StartupClock,
  StartupPhase,
  StartupPhaseStatus,
  StartupTask,
  StartupTaskStatus
} from 'core';

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
        startupTask('content', StartupPhase.CRITICAL, ['deep-link-routing'], executionOrder),
        startupTask('deep-link-routing', StartupPhase.CRITICAL, ['database-migration'], executionOrder),
        startupTask('database-migration', StartupPhase.CRITICAL, [], executionOrder)
      ];

      const summary = await new AppStartup(tasks, new StepClock()).runCritical();

      expect(executionOrder.join(',')).assertEqual('database-migration,deep-link-routing,content');
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

    it('startsSessionRestoreOnlyAfterCriticalUiStartup', 0, async () => {
      const executionOrder: Array<string> = [];
      const startup = new AppStartup([
        startupTask('database-migration', StartupPhase.CRITICAL, [], executionOrder),
        startupTask('deep-link-routing', StartupPhase.CRITICAL, ['database-migration'], executionOrder),
        startupTask('session-restore', StartupPhase.DEFERRED, ['deep-link-routing'], executionOrder)
      ]);

      const critical = await startup.runCritical();
      expect(critical.status).assertEqual(StartupPhaseStatus.SUCCEEDED);
      expect(executionOrder.join(',')).assertEqual('database-migration,deep-link-routing');

      await startup.runDeferred();
      expect(executionOrder.join(',')).assertEqual('database-migration,deep-link-routing,session-restore');
    });

    it('doesNotContinueAsyncStartupAfterAbilityDestroy', 0, async () => {
      const guard = new LatestOperationGuard();
      const generation = guard.next();
      let loadContentRuns = 0;
      let deferredRuns = 0;
      const pendingStartup = Promise.resolve().then((): void => {
        if (!guard.isCurrent(generation)) {
          return;
        }
        loadContentRuns += 1;
        deferredRuns += 1;
      });

      guard.invalidate();
      await pendingStartup;

      expect(loadContentRuns).assertEqual(0);
      expect(deferredRuns).assertEqual(0);
    });

    it('keepsOnlyLatestColdStartupDestination', 0, () => {
      const channel = new StartupDestinationChannel();
      const received: Array<P1Destination> = [];
      channel.publish({ name: P1DestinationName.ANSWER, id: 'cold-a' });
      channel.publish({ name: P1DestinationName.ARTICLE, id: 'cold-b' });

      const unsubscribe = channel.subscribe((destination: P1Destination): void => {
        received.push(destination);
      });
      unsubscribe();

      expect(received.length).assertEqual(1);
      expect(received[0].name).assertEqual(P1DestinationName.ARTICLE);
      expect(p1DestinationIdentity(received[0])).assertEqual('Article:cold-b');
    });

    it('doesNotDeliverDuplicateNewWantDestination', 0, () => {
      const channel = new StartupDestinationChannel();
      const received: Array<P1Destination> = [];
      const unsubscribe = channel.subscribe((destination: P1Destination): void => {
        received.push(destination);
      });
      channel.publish({ name: P1DestinationName.SEARCH, query: 'ArkTS 导航' });
      channel.publish({ name: P1DestinationName.SEARCH, query: 'ArkTS 导航' });
      channel.publish({ name: P1DestinationName.SEARCH, query: 'HarmonyOS' });
      unsubscribe();

      expect(received.length).assertEqual(2);
      expect(p1DestinationIdentity(received[0]))
        .assertEqual(`Search:${encodeURIComponent('ArkTS 导航')}`);
      expect(p1DestinationIdentity(received[1])).assertEqual('Search:HarmonyOS');
    });

    it('makesNewerThemeSelectionOutrankRestoreAndInvalidatesOnLeave', 0, () => {
      const guard = new LatestOperationGuard();
      const restoreGeneration = guard.next();
      const selectionGeneration = guard.next();

      expect(guard.isCurrent(restoreGeneration)).assertFalse();
      expect(guard.isCurrent(selectionGeneration)).assertTrue();
      guard.invalidate();
      expect(guard.isCurrent(selectionGeneration)).assertFalse();
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
