import {
  DailyStoryRepository,
  DailyStoryRepositoryFailure,
  DailyStoryRepositoryFailureKind,
  DomainDecodeError,
  HttpFailure,
  HttpFailureKind
} from 'data';
import { P1Destination } from 'core';

export enum DailyStoryDetailPhase {
  IDLE = 'idle',
  LOADING = 'loading',
  READY = 'ready',
  ERROR = 'error'
}

export interface DailyStoryDetailViewState {
  readonly phase: DailyStoryDetailPhase;
  readonly destination?: P1Destination;
  readonly errorMessage?: string;
}

export type DailyStoryDetailObserver = (state: DailyStoryDetailViewState) => void;

export class DailyStoryDetailController {
  private readonly repository: DailyStoryRepository;
  private readonly observer: DailyStoryDetailObserver;
  private active: boolean = false;
  private generation: number = 0;
  private phase: DailyStoryDetailPhase = DailyStoryDetailPhase.IDLE;
  private destination?: P1Destination;
  private errorMessage?: string;

  constructor(repository: DailyStoryRepository,
    observer: DailyStoryDetailObserver = (_state: DailyStoryDetailViewState): void => {
    }) {
    this.repository = repository;
    this.observer = observer;
  }

  activate(): void {
    if (this.active) {
      return;
    }
    this.active = true;
    this.emit();
  }

  deactivate(): void {
    if (!this.active) {
      return;
    }
    this.active = false;
    this.generation += 1;
    this.repository.cancel();
  }

  snapshot(): DailyStoryDetailViewState {
    return {
      phase: this.phase,
      destination: this.destination,
      errorMessage: this.errorMessage
    };
  }

  async load(storyId: string): Promise<void> {
    if (!this.active) {
      return;
    }
    if (this.phase === DailyStoryDetailPhase.LOADING) {
      this.repository.cancel();
    }
    const generation = ++this.generation;
    this.phase = DailyStoryDetailPhase.LOADING;
    this.destination = undefined;
    this.errorMessage = undefined;
    this.emit();
    try {
      const destination = await this.repository.getDestination(storyId);
      if (!this.isCurrent(generation)) {
        return;
      }
      if (destination === undefined) {
        this.phase = DailyStoryDetailPhase.ERROR;
        this.errorMessage = '该日报暂不支持原生阅读';
      } else {
        this.phase = DailyStoryDetailPhase.READY;
        this.destination = destination;
      }
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.phase = DailyStoryDetailPhase.ERROR;
      this.errorMessage = dailyStoryDetailErrorMessage(error);
    }
    this.emit();
  }

  private isCurrent(generation: number): boolean {
    return this.active && generation === this.generation;
  }

  private emit(): void {
    if (this.active) {
      this.observer(this.snapshot());
    }
  }
}

export function dailyStoryDetailErrorMessage(error: Object): string {
  if (error instanceof DailyStoryRepositoryFailure) {
    return error.kind === DailyStoryRepositoryFailureKind.INVALID_ID
      ? '日报 ID 无效，无法加载正文'
      : '日报正文请求已取消';
  }
  if (error instanceof HttpFailure) {
    switch (error.kind) {
      case HttpFailureKind.TIMEOUT:
      case HttpFailureKind.NETWORK:
        return '网络连接失败，请检查网络后重试';
      case HttpFailureKind.RATE_LIMITED:
        return '请求过于频繁，请稍后重试';
      case HttpFailureKind.SERVER:
        return '知乎服务暂时不可用，请稍后重试';
      default:
        return '日报正文暂时不可用，请稍后重试';
    }
  }
  if (error instanceof DomainDecodeError) {
    return '日报正文响应无法解析，请稍后重试';
  }
  return '日报正文加载失败，请稍后重试';
}
