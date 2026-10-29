import {
  DailyStoryRepository,
  DailyStoryRepositoryFailure,
  DailyStoryRepositoryFailureKind,
  DailyStoryPayload,
  DomainDecodeError,
  HttpFailure,
  HttpFailureKind
} from 'data';
import { AppDestination } from 'core';
import {
  DailyStoryCompleteness,
  DailyStoryDiagnostic,
  DailyStoryDiagnosticCode,
  DailyStoryParseResult,
  DailyStoryStats,
  parseDailyStoryHtml,
  ReaderBlock
} from 'reader';

/**
 * 日报原生阅读页状态机。
 *
 * 一次打开只发一次正文请求（`getStory`），状态转换固定为：
 * IDLE → LOADING → READY / PARTIAL / UNSUPPORTED，任何失败进入 ERROR。
 * 所有异步回调都经过 `isCurrent(generation)` 检查，保证「离开页面」「A→B 快速切换」
 * 「旧请求迟到」都不会覆盖新正文、不会幽灵导航。
 */
export enum DailyStoryDetailPhase {
  IDLE = 'idle',
  LOADING = 'loading',
  /** 完整解析且有可展示内容。 */
  READY = 'ready',
  /** 正文可读，但有明确不支持/降级内容：就地提示，并提供浏览器入口。 */
  PARTIAL = 'partial',
  /** 有效响应但空 body/无可读块/超预算：提供原文与网页入口。 */
  UNSUPPORTED = 'unsupported',
  ERROR = 'error'
}

export interface DailyStoryViewState {
  readonly phase: DailyStoryDetailPhase;
  readonly storyId: string;
  readonly payload?: DailyStoryPayload;
  readonly blocks: Array<ReaderBlock>;
  readonly stats?: DailyStoryStats;
  readonly diagnostics: Array<DailyStoryDiagnostic>;
  readonly completeness?: DailyStoryCompleteness;
  /** 规范日报网页地址（始终可用，即使载荷尚未到达）。 */
  readonly webUrl: string;
  /** 可选的「查看知乎讨论」目标（来自响应 view-more / originUrl / 正文问答链接）。 */
  readonly originDestination?: AppDestination;
  readonly errorMessage?: string;
}

export type DailyStoryObserver = (state: DailyStoryViewState) => void;

/** 规范日报网页地址：不信任响应里的 url/share_url。 */
export function dailyStoryWebUrlFor(storyId: string): string {
  return /^[1-9][0-9]{0,29}$/.test(storyId)
    ? `https://daily.zhihu.com/story/${storyId}`
    : 'https://daily.zhihu.com/';
}

function emptyState(phase: DailyStoryDetailPhase, storyId: string): DailyStoryViewState {
  return {
    phase: phase,
    storyId: storyId,
    blocks: [],
    diagnostics: [],
    webUrl: dailyStoryWebUrlFor(storyId)
  };
}

export class DailyStoryDetailController {
  private readonly repository: DailyStoryRepository;
  private readonly observer: DailyStoryObserver;
  private active: boolean = false;
  private generation: number = 0;
  private state: DailyStoryViewState = emptyState(DailyStoryDetailPhase.IDLE, '');

  constructor(repository: DailyStoryRepository,
    observer: DailyStoryObserver = (_state: DailyStoryViewState): void => {
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
    // 递增代次：在途请求回来后既不再发回调，也不会被当作当前结果。
    this.generation += 1;
    this.repository.cancel();
  }

  snapshot(): DailyStoryViewState {
    return this.state;
  }

  /** 加载（或重新加载）指定日报正文；同页重试会取消上一次请求。 */
  async load(storyId: string): Promise<void> {
    if (!this.active) {
      return;
    }
    if (this.state.phase === DailyStoryDetailPhase.LOADING) {
      this.repository.cancel();
    }
    const generation = ++this.generation;
    this.state = emptyState(DailyStoryDetailPhase.LOADING, storyId);
    this.emit();
    let payload: DailyStoryPayload;
    try {
      payload = await this.repository.getStory(storyId);
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.state = {
        phase: DailyStoryDetailPhase.ERROR,
        storyId: storyId,
        blocks: [],
        diagnostics: [],
        webUrl: dailyStoryWebUrlFor(storyId),
        errorMessage: dailyStoryErrorMessage(error)
      };
      this.emit();
      return;
    }
    if (!this.isCurrent(generation)) {
      return;
    }
    // 解析在数据返回后同步执行：解析器是有界单遍扫描，异常输入由预算表达，不抛异常。
    let parsed: DailyStoryParseResult;
    try {
      parsed = parseDailyStoryHtml(payload.bodyHtml);
    } catch (_error) {
      parsed = {
        blocks: [],
        stats: {
          blockCount: 0, textLength: 0, headingCount: 0, imageCount: 0, linkCardCount: 0,
          quoteBlockCount: 0, sectionCount: 0, avatarCount: 0, placeholderCount: 0
        },
        diagnostics: [],
        completeness: DailyStoryCompleteness.UNSUPPORTED,
        sections: []
      };
    }
    const phase = parsed.completeness === DailyStoryCompleteness.COMPLETE
      ? DailyStoryDetailPhase.READY
      : parsed.completeness === DailyStoryCompleteness.PARTIAL
        ? DailyStoryDetailPhase.PARTIAL
        : DailyStoryDetailPhase.UNSUPPORTED;
    this.state = {
      phase: phase,
      storyId: storyId,
      payload: payload,
      blocks: parsed.blocks,
      stats: parsed.stats,
      diagnostics: parsed.diagnostics,
      completeness: parsed.completeness,
      webUrl: payload.shareUrl.length > 0 ? payload.shareUrl : dailyStoryWebUrlFor(storyId),
      originDestination: payload.originDestination,
      errorMessage: phase === DailyStoryDetailPhase.UNSUPPORTED
        ? dailyStoryUnsupportedMessage(parsed) : undefined
    };
    this.emit();
  }

  private isCurrent(generation: number): boolean {
    return this.active && generation === this.generation;
  }

  private emit(): void {
    if (this.active) {
      this.observer(this.state);
    }
  }
}

/** 不可支持态的说明：区分「服务端未返回正文」「解析为空」「超出预算」三种原因。 */
function dailyStoryUnsupportedMessage(parsed: DailyStoryParseResult): string {
  if (parsed.diagnostics.some((item: DailyStoryDiagnostic): boolean =>
    item.code === DailyStoryDiagnosticCode.BUDGET_EXCEEDED)) {
    return '这篇日报内容过大，暂不支持原生阅读';
  }
  if (parsed.stats.blockCount === 0) {
    return '这篇日报没有可原生展示的正文';
  }
  return '这篇日报暂不支持原生阅读';
}

export function dailyStoryErrorMessage(error: Object): string {
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
