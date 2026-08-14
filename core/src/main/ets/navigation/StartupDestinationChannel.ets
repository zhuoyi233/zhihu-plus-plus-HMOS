import { DeepLinkDestination, DeepLinkType } from './DeepLinkResolver';
import { decodeP1Destination, P1Destination, P1DestinationName } from './P1Destination';

export type StartupDestinationListener = (destination: P1Destination) => void;

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
  private pending: P1Destination | undefined = undefined;
  private activeIdentity: string | undefined = undefined;

  publish(destination: P1Destination): void {
    if (this.listeners.length === 0) {
      this.pending = destination;
      return;
    }
    const identity = p1DestinationIdentity(destination);
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
      this.activeIdentity = p1DestinationIdentity(destination);
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
export interface P1StackEntry {
  readonly name: string;
  readonly param?: Object;
}

/**
 * 在返回栈中查找与目标身份（name + 参数）相同的页面下标。
 *
 * 与 `shouldPushP1Destination` 只比较栈顶不同，本函数扫描整个返回栈，
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
export function findP1DestinationStackIndex(entries: Array<P1StackEntry>, destination: P1Destination): number {
  const identity = p1DestinationIdentity(destination);
  for (let index = 0; index < entries.length; index += 1) {
    const param = entries[index].param;
    const decoded = param === undefined
      ? decodeP1Destination(entries[index].name, new Object())
      : decodeP1Destination(entries[index].name, param);
    if (decoded !== undefined && p1DestinationIdentity(decoded) === identity) {
      return index;
    }
  }
  return -1;
}

export function p1DestinationIdentity(destination: P1Destination): string {
  switch (destination.name) {
    case P1DestinationName.QUESTION:
    case P1DestinationName.ANSWER:
    case P1DestinationName.ARTICLE:
    case P1DestinationName.VIDEO:
    case P1DestinationName.PIN:
    case P1DestinationName.PEOPLE:
    case P1DestinationName.COLLECTION:
    case P1DestinationName.COLLECTIONS:
      return `${destination.name}:${encodeURIComponent(destination.id)}`;
    case P1DestinationName.COMMENT:
      return `${destination.name}:${encodeURIComponent(destination.contentId)}:` +
        encodeURIComponent(destination.commentId ?? '');
    case P1DestinationName.SEARCH:
      return `${destination.name}:${encodeURIComponent(destination.query)}`;
    default:
      return destination.name;
  }
}

export function shouldPushP1Destination(current: P1Destination | undefined, next: P1Destination): boolean {
  return current === undefined || p1DestinationIdentity(current) !== p1DestinationIdentity(next);
}

export function toP1Destination(destination: DeepLinkDestination): P1Destination {
  switch (destination.type) {
    case DeepLinkType.MAIN_TABS:
      return { name: P1DestinationName.HOME };
    case DeepLinkType.ANSWER:
      return { name: P1DestinationName.ANSWER, id: destination.id };
    case DeepLinkType.QUESTION:
      return { name: P1DestinationName.QUESTION, id: destination.id };
    case DeepLinkType.ARTICLE:
      return { name: P1DestinationName.ARTICLE, id: destination.id };
    case DeepLinkType.VIDEO:
      return { name: P1DestinationName.VIDEO, id: destination.id };
    case DeepLinkType.PIN:
      return { name: P1DestinationName.PIN, id: destination.id };
    case DeepLinkType.PERSON:
      return { name: P1DestinationName.PEOPLE, id: destination.id };
    case DeepLinkType.SEARCH:
      return { name: P1DestinationName.SEARCH, query: destination.query };
  }
}
