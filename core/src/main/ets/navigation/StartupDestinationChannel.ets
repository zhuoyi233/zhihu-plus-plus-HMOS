import { DeepLinkDestination, DeepLinkType } from './DeepLinkResolver';
import { P1Destination, P1DestinationName } from './P1Destination';

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
