export enum StartupPhase {
  CRITICAL = 'critical',
  DEFERRED = 'deferred'
}

export enum StartupTaskStatus {
  SUCCEEDED = 'succeeded',
  FAILED = 'failed',
  SKIPPED = 'skipped'
}

export enum StartupPhaseStatus {
  SUCCEEDED = 'succeeded',
  FAILED = 'failed',
  DEGRADED = 'degraded'
}

export interface StartupTask {
  readonly name: string;
  readonly phase: StartupPhase;
  readonly dependencies: Array<string>;
  readonly run: () => Promise<void>;
}

export interface StartupTaskResult {
  readonly name: string;
  readonly status: StartupTaskStatus;
  readonly durationMs: number;
}

export interface StartupPhaseSummary {
  readonly phase: StartupPhase;
  readonly status: StartupPhaseStatus;
  readonly durationMs: number;
  readonly tasks: Array<StartupTaskResult>;
}

export interface StartupClock {
  now(): number;
}

export type StartupObserver = (summary: StartupPhaseSummary) => void;

export class SystemStartupClock implements StartupClock {
  now(): number {
    return Date.now();
  }
}

export class AppStartup {
  private readonly orderedCriticalTasks: Array<StartupTask>;
  private readonly orderedDeferredTasks: Array<StartupTask>;
  private readonly taskStatuses: Map<string, StartupTaskStatus> = new Map();
  private readonly clock: StartupClock;
  private readonly observer: StartupObserver | undefined;
  private criticalRun: Promise<StartupPhaseSummary> | undefined = undefined;
  private deferredRun: Promise<StartupPhaseSummary> | undefined = undefined;

  constructor(tasks: Array<StartupTask>, clock: StartupClock = new SystemStartupClock(),
    observer?: StartupObserver) {
    this.validateTasks(tasks);
    this.orderedCriticalTasks = this.orderTasks(tasks.filter((task: StartupTask) =>
      task.phase === StartupPhase.CRITICAL));
    this.orderedDeferredTasks = this.orderTasks(tasks.filter((task: StartupTask) =>
      task.phase === StartupPhase.DEFERRED));
    this.clock = clock;
    this.observer = observer;
  }

  runCritical(): Promise<StartupPhaseSummary> {
    if (this.criticalRun === undefined) {
      this.criticalRun = this.executePhase(StartupPhase.CRITICAL, this.orderedCriticalTasks);
    }
    return this.criticalRun;
  }

  runDeferred(): Promise<StartupPhaseSummary> {
    if (this.deferredRun === undefined) {
      this.deferredRun = this.executeDeferredAfterCritical();
    }
    return this.deferredRun;
  }

  private async executeDeferredAfterCritical(): Promise<StartupPhaseSummary> {
    const criticalSummary = await this.runCritical();
    if (criticalSummary.status !== StartupPhaseStatus.SUCCEEDED) {
      const skippedTasks: Array<StartupTaskResult> = this.orderedDeferredTasks.map(
        (task: StartupTask): StartupTaskResult => {
        this.taskStatuses.set(task.name, StartupTaskStatus.SKIPPED);
        return {
          name: task.name,
          status: StartupTaskStatus.SKIPPED,
          durationMs: 0
        };
      });
      const summary: StartupPhaseSummary = {
        phase: StartupPhase.DEFERRED,
        status: StartupPhaseStatus.DEGRADED,
        durationMs: 0,
        tasks: skippedTasks
      };
      this.notify(summary);
      return summary;
    }
    return this.executePhase(StartupPhase.DEFERRED, this.orderedDeferredTasks);
  }

  private async executePhase(phase: StartupPhase,
    orderedTasks: Array<StartupTask>): Promise<StartupPhaseSummary> {
    const phaseStartedAt = this.clock.now();
    const results: Array<StartupTaskResult> = [];
    let failedCount = 0;
    let skippedCount = 0;

    for (const task of orderedTasks) {
      const blocked = task.dependencies.some((dependency: string) =>
        this.taskStatuses.get(dependency) !== StartupTaskStatus.SUCCEEDED);
      if (blocked) {
        this.taskStatuses.set(task.name, StartupTaskStatus.SKIPPED);
        results.push({ name: task.name, status: StartupTaskStatus.SKIPPED, durationMs: 0 });
        skippedCount += 1;
        continue;
      }

      const taskStartedAt = this.clock.now();
      let status = StartupTaskStatus.SUCCEEDED;
      try {
        await task.run();
      } catch (_error) {
        status = StartupTaskStatus.FAILED;
        failedCount += 1;
      }
      const durationMs = Math.max(0, this.clock.now() - taskStartedAt);
      this.taskStatuses.set(task.name, status);
      results.push({ name: task.name, status: status, durationMs: durationMs });
    }

    let phaseStatus = StartupPhaseStatus.SUCCEEDED;
    if (failedCount > 0 || skippedCount > 0) {
      phaseStatus = phase === StartupPhase.CRITICAL
        ? StartupPhaseStatus.FAILED
        : StartupPhaseStatus.DEGRADED;
    }
    const summary: StartupPhaseSummary = {
      phase: phase,
      status: phaseStatus,
      durationMs: Math.max(0, this.clock.now() - phaseStartedAt),
      tasks: results
    };
    this.notify(summary);
    return summary;
  }

  private notify(summary: StartupPhaseSummary): void {
    if (this.observer === undefined) {
      return;
    }
    try {
      this.observer(summary);
    } catch (_error) {
    }
  }

  private validateTasks(tasks: Array<StartupTask>): void {
    const tasksByName: Map<string, StartupTask> = new Map();
    for (const task of tasks) {
      if (!/^[a-z][a-z0-9-]{0,47}$/.test(task.name)) {
        throw new Error('Startup task name must be a stable identifier');
      }
      if (tasksByName.has(task.name)) {
        throw new Error(`Duplicate startup task: ${task.name}`);
      }
      tasksByName.set(task.name, task);
    }

    for (const task of tasks) {
      for (const dependency of task.dependencies) {
        const dependencyTask = tasksByName.get(dependency);
        if (dependencyTask === undefined) {
          throw new Error(`Unknown startup dependency: ${dependency}`);
        }
        if (task.phase === StartupPhase.CRITICAL && dependencyTask.phase === StartupPhase.DEFERRED) {
          throw new Error('Critical startup task cannot depend on a deferred task');
        }
      }
    }
    this.orderTasks(tasks);
  }

  private orderTasks(tasks: Array<StartupTask>): Array<StartupTask> {
    const pending = tasks.slice();
    const ordered: Array<StartupTask> = [];
    while (pending.length > 0) {
      pending.sort((left: StartupTask, right: StartupTask) => {
        if (left.name === right.name) {
          return 0;
        }
        return left.name < right.name ? -1 : 1;
      });
      const readyIndex = pending.findIndex((candidate: StartupTask) =>
        !candidate.dependencies.some((dependency: string) =>
          pending.some((pendingTask: StartupTask) => pendingTask.name === dependency)));
      if (readyIndex < 0) {
        throw new Error('Startup task graph contains a cycle');
      }
      ordered.push(pending[readyIndex]);
      pending.splice(readyIndex, 1);
    }
    return ordered;
  }
}
