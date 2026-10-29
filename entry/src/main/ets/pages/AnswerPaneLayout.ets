import { LoadedContentDetail } from './ContentDetailState';

/** 整页面板上限：上一答 + 当前答 + 下一答，不随连续切换累积组件。 */
export const ANSWER_PANE_MAX: number = 3;

/** 正文实例身份：同一回答的同一次加载才是同一份正文（跨快照副本稳定）。 */
export function answerPaneIdentity(content: LoadedContentDetail): string {
  return `${content.value.id}:${content.loadGeneration ?? 0}`;
}

/**
 * 单篇回答页的整页面板角色表：上一答（-1）、当前答（0）、下一答（1）。
 *
 * 只负责按方向装配渲染顺序并提供方向查询，不持有正文生命周期：
 * 何处保留、何时淘汰由页面按导航器相邻关系决定，提交事务仍由导航器与控制器校验。
 */
export class AnswerPaneLayout {
  private readonly directions: Map<string, number> = new Map();

  /**
   * 装配渲染顺序：上一答、当前答、下一答；同一正文身份只保留首次出现，最多三份。
   * 当前答未就绪（非 READY）时传 undefined，邻答仍按各自方向保留。
   */
  arrange(previous: LoadedContentDetail | undefined, current: LoadedContentDetail | undefined,
    next: LoadedContentDetail | undefined): LoadedContentDetail[] {
    this.directions.clear();
    const panes: LoadedContentDetail[] = [];
    this.push(panes, previous, -1);
    this.push(panes, current, 0);
    this.push(panes, next, 1);
    return panes;
  }

  /** 面板方向：-1 上一答、0 当前答、1 下一答；未登记返回 0（调用方按"非邻答"处理）。 */
  directionOf(content: LoadedContentDetail): number {
    return this.directions.get(answerPaneIdentity(content)) ?? 0;
  }

  has(content: LoadedContentDetail): boolean {
    return this.directions.has(answerPaneIdentity(content));
  }

  size(): number { return this.directions.size; }

  private push(panes: LoadedContentDetail[], content: LoadedContentDetail | undefined, direction: number): void {
    if (content === undefined || panes.length >= ANSWER_PANE_MAX) { return; }
    const identity = answerPaneIdentity(content);
    if (this.directions.has(identity)) { return; }
    this.directions.set(identity, direction);
    panes.push(content);
  }
}
