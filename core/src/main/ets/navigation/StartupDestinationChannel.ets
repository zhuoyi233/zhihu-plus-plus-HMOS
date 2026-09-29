import { DeepLinkDestination, DeepLinkType } from './DeepLinkResolver';
import { decodeAppDestination, AppDestination, AppDestinationName } from './AppDestination';

export type StartupDestinationListener = (destination: AppDestination) => void;

export class LatestOperationGuard {
  private generation: number = 0;

  next(): number {
    this.generation += 1;
    return this.generation;
  }

  invalidate(): void {
    this.generation += 1;
  }

  isCurrent(generation: number): boolean {
    return generation === this.generation;
  }
}

export class StartupDestinationChannel {
  private readonly listeners: Array<StartupDestinationListener> = [];
  private pending: AppDestination | undefined = undefined;
  private activeIdentity: string | undefined = undefined;

  publish(destination: AppDestination): void {
    if (this.listeners.length === 0) {
      this.pending = destination;
      return;
    }
    const identity = appDestinationIdentity(destination);
    if (identity === this.activeIdentity) {
      return;
    }
    this.activeIdentity = identity;
    this.listeners.slice().forEach((listener: StartupDestinationListener) => listener(destination));
  }

  subscribe(listener: StartupDestinationListener): () => void {
    this.listeners.push(listener);
    const destination = this.pending;
    this.pending = undefined;
    if (destination !== undefined) {
      this.activeIdentity = appDestinationIdentity(destination);
      listener(destination);
    }
    return (): void => {
      const index = this.listeners.indexOf(listener);
      if (index >= 0) {
        this.listeners.splice(index, 1);
      }
      if (this.listeners.length === 0) {
        this.activeIdentity = undefined;
      }
    };
  }
}

export const startupDestinationChannel: StartupDestinationChannel = new StartupDestinationChannel();

/**
 * 返回栈页面的最小结构视图，与 ArkUI `NavPathInfo` 结构兼容
 * （`param` 为可选，兼容无参页面或深链恢复的条目）。
 */
export interface NavigationStackEntry {
  readonly name: string;
  readonly param?: Object;
}

/**
 * 在返回栈中查找与目标身份（name + 参数）相同的页面下标。
 *
 * 与 `shouldPushAppDestination` 只比较栈顶不同，本函数扫描整个返回栈，
 * 用于「同一导航目标不重复入栈」的治理（P3-7，参考 CLAUDE.md「返回栈上下文保存」
 * 经验：从详情页作者进入个人主页这类外部导航要防止同一目标短时间连续入栈，
 * 否则返回时可能只是露出前一个重复页面）。参数化页面（如 PEOPLE/QUESTION）不能
 * 使用按 name 匹配的 MOVE_TO_TOP_SINGLETON——那会把不同 id 的页面错误去重，
 * 因此必须按身份（name + 参数）比较。
 *
 * @param entries 返回栈条目（来自 NavPathStack.getPathStack()）
 * @param destination 待入栈目标
 * @returns 第一个身份匹配的下标；栈中不存在时返回 -1
 */
export function findAppDestinationStackIndex(entries: Array<NavigationStackEntry>, destination: AppDestination): number {
  const identity = appDestinationIdentity(destination);
  for (let index = 0; index < entries.length; index += 1) {
    const param = entries[index].param;
    const decoded = param === undefined
      ? decodeAppDestination(entries[index].name, new Object())
      : decodeAppDestination(entries[index].name, param);
    if (decoded !== undefined && appDestinationIdentity(decoded) === identity) {
      return index;
    }
  }
  return -1;
}

export function appDestinationIdentity(destination: AppDestination): string {
  switch (destination.name) {
    case AppDestinationName.QUESTION:
    case AppDestinationName.ANSWER:
    case AppDestinationName.ARTICLE:
    case AppDestinationName.VIDEO:
    case AppDestinationName.PIN:
    case AppDestinationName.PEOPLE:
    case AppDestinationName.COLLECTION:
    case AppDestinationName.COLLECTIONS:
      return `${destination.name}:${encodeURIComponent(destination.id)}`;
    case AppDestinationName.WRITE_ANSWER:
      return `${destination.name}:${encodeURIComponent(destination.questionId)}:` +
        encodeURIComponent(destination.answerId ?? '');
    case AppDestinationName.WRITE_PIN:
      return `${destination.name}:${encodeURIComponent(destination.draftId)}`;
    case AppDestinationName.COMMENT:
      return `${destination.name}:${destination.contentType}:${encodeURIComponent(destination.contentId)}:` +
        encodeURIComponent(destination.commentId ?? '') + ':' +
        encodeURIComponent(destination.segmentId ?? '');
    case AppDestinationName.SEARCH:
      return `${destination.name}:${encodeURIComponent(destination.query)}`;
    case AppDestinationName.WHATS_NEW:
      // 展示本机版本与预览目标版本是两个不同页面身份，防止互相误去重。
      return `${destination.name}:${encodeURIComponent(destination.version ?? '')}`;
    default:
      return destination.name;
  }
}

export function shouldPushAppDestination(current: AppDestination | undefined, next: AppDestination): boolean {
  return current === undefined || appDestinationIdentity(current) !== appDestinationIdentity(next);
}

export function toAppDestination(destination: DeepLinkDestination): AppDestination {
  switch (destination.type) {
    case DeepLinkType.MAIN_TABS:
      return { name: AppDestinationName.HOME };
    case DeepLinkType.ANSWER:
      return { name: AppDestinationName.ANSWER, id: destination.id };
    case DeepLinkType.QUESTION:
      return { name: AppDestinationName.QUESTION, id: destination.id };
    case DeepLinkType.ARTICLE:
      return { name: AppDestinationName.ARTICLE, id: destination.id };
    case DeepLinkType.VIDEO:
      return { name: AppDestinationName.VIDEO, id: destination.id };
    case DeepLinkType.PIN:
      return { name: AppDestinationName.PIN, id: destination.id };
    case DeepLinkType.PERSON:
      return { name: AppDestinationName.PEOPLE, id: destination.id };
    case DeepLinkType.SEARCH:
      return { name: AppDestinationName.SEARCH, query: destination.query };
  }
}
