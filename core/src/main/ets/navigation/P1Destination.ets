export enum P1DestinationName {
  HOME = 'Home',
  QUESTION = 'Question',
  ANSWER = 'Answer',
  ARTICLE = 'Article',
  VIDEO = 'Video',
  PIN = 'Pin',
  PEOPLE = 'People',
  COMMENT = 'Comment',
  SEARCH = 'Search',
  COLLECTION = 'Collection',
  NOTIFICATION = 'Notification',
  SETTINGS = 'Settings',
  TECHNICAL_LAB = 'TechnicalLab',
  READER_PROBE = 'ReaderProbe',
  IMAGE_PROBE = 'ImageProbe',
  DATABASE_PROBE = 'DatabaseProbe',
  DEEP_LINK_PROBE = 'DeepLinkProbe',
  QR_SCAN_PROBE = 'QrScanProbe',
  BACKGROUND_TASK_PROBE = 'BackgroundTaskProbe',
  DOMAIN_FIXTURE_PROBE = 'DomainFixtureProbe'
}

export interface StatelessDestination {
  readonly name: P1DestinationName.HOME | P1DestinationName.NOTIFICATION;
}

export interface InfrastructureDestination {
  readonly name: P1DestinationName.SETTINGS | P1DestinationName.TECHNICAL_LAB |
    P1DestinationName.READER_PROBE | P1DestinationName.IMAGE_PROBE |
    P1DestinationName.DATABASE_PROBE | P1DestinationName.DEEP_LINK_PROBE |
    P1DestinationName.QR_SCAN_PROBE | P1DestinationName.BACKGROUND_TASK_PROBE |
    P1DestinationName.DOMAIN_FIXTURE_PROBE;
}

export interface ContentDestination {
  readonly name: P1DestinationName.QUESTION | P1DestinationName.ANSWER |
    P1DestinationName.ARTICLE | P1DestinationName.VIDEO | P1DestinationName.PIN |
    P1DestinationName.PEOPLE | P1DestinationName.COLLECTION;
  readonly id: string;
}

export interface CommentDestination {
  readonly name: P1DestinationName.COMMENT;
  readonly contentId: string;
  readonly commentId?: string;
}

export interface SearchDestination {
  readonly name: P1DestinationName.SEARCH;
  readonly query: string;
}

export type P1Destination = StatelessDestination | InfrastructureDestination | ContentDestination |
  CommentDestination | SearchDestination;

interface WireDestination {
  name?: string;
  id?: string;
  contentId?: string;
  commentId?: string;
  query?: string;
}

export function isP1DestinationName(name: string): boolean {
  switch (name) {
    case P1DestinationName.HOME:
    case P1DestinationName.QUESTION:
    case P1DestinationName.ANSWER:
    case P1DestinationName.ARTICLE:
    case P1DestinationName.VIDEO:
    case P1DestinationName.PIN:
    case P1DestinationName.PEOPLE:
    case P1DestinationName.COMMENT:
    case P1DestinationName.SEARCH:
    case P1DestinationName.COLLECTION:
    case P1DestinationName.NOTIFICATION:
    case P1DestinationName.SETTINGS:
    case P1DestinationName.TECHNICAL_LAB:
    case P1DestinationName.READER_PROBE:
    case P1DestinationName.IMAGE_PROBE:
    case P1DestinationName.DATABASE_PROBE:
    case P1DestinationName.DEEP_LINK_PROBE:
    case P1DestinationName.QR_SCAN_PROBE:
    case P1DestinationName.BACKGROUND_TASK_PROBE:
    case P1DestinationName.DOMAIN_FIXTURE_PROBE:
      return true;
    default:
      return false;
  }
}

export function decodeP1Destination(name: string, param: Object): P1Destination | undefined {
  if (!isP1DestinationName(name)) {
    return undefined;
  }
  let wire: WireDestination;
  try {
    wire = JSON.parse(JSON.stringify(param)) as WireDestination;
  } catch (_error) {
    return undefined;
  }
  if (wire.name !== name) {
    return undefined;
  }

  switch (name) {
    case P1DestinationName.HOME:
      return hasNoParameters(wire) ? { name: P1DestinationName.HOME } : undefined;
    case P1DestinationName.NOTIFICATION:
      return hasNoParameters(wire) ? { name: P1DestinationName.NOTIFICATION } : undefined;
    case P1DestinationName.SETTINGS:
      return hasNoParameters(wire) ? { name: P1DestinationName.SETTINGS } : undefined;
    case P1DestinationName.TECHNICAL_LAB:
      return hasNoParameters(wire) ? { name: P1DestinationName.TECHNICAL_LAB } : undefined;
    case P1DestinationName.READER_PROBE:
      return hasNoParameters(wire) ? { name: P1DestinationName.READER_PROBE } : undefined;
    case P1DestinationName.IMAGE_PROBE:
      return hasNoParameters(wire) ? { name: P1DestinationName.IMAGE_PROBE } : undefined;
    case P1DestinationName.DATABASE_PROBE:
      return hasNoParameters(wire) ? { name: P1DestinationName.DATABASE_PROBE } : undefined;
    case P1DestinationName.DEEP_LINK_PROBE:
      return hasNoParameters(wire) ? { name: P1DestinationName.DEEP_LINK_PROBE } : undefined;
    case P1DestinationName.QR_SCAN_PROBE:
      return hasNoParameters(wire) ? { name: P1DestinationName.QR_SCAN_PROBE } : undefined;
    case P1DestinationName.BACKGROUND_TASK_PROBE:
      return hasNoParameters(wire) ? { name: P1DestinationName.BACKGROUND_TASK_PROBE } : undefined;
    case P1DestinationName.DOMAIN_FIXTURE_PROBE:
      return hasNoParameters(wire) ? { name: P1DestinationName.DOMAIN_FIXTURE_PROBE } : undefined;
    case P1DestinationName.QUESTION:
      return decodeContent(wire, P1DestinationName.QUESTION);
    case P1DestinationName.ANSWER:
      return decodeContent(wire, P1DestinationName.ANSWER);
    case P1DestinationName.ARTICLE:
      return decodeContent(wire, P1DestinationName.ARTICLE);
    case P1DestinationName.VIDEO:
      return decodeContent(wire, P1DestinationName.VIDEO);
    case P1DestinationName.PIN:
      return decodeContent(wire, P1DestinationName.PIN);
    case P1DestinationName.PEOPLE:
      return decodeContent(wire, P1DestinationName.PEOPLE);
    case P1DestinationName.COLLECTION:
      return decodeContent(wire, P1DestinationName.COLLECTION);
    case P1DestinationName.COMMENT:
      if (!hasText(wire.contentId) || wire.id !== undefined || wire.query !== undefined ||
        (wire.commentId !== undefined && !hasText(wire.commentId)) ||
        !hasOnlyFields(wire, ['name', 'contentId', 'commentId'])) {
        return undefined;
      }
      return wire.commentId === undefined
        ? { name: P1DestinationName.COMMENT, contentId: wire.contentId as string }
        : {
          name: P1DestinationName.COMMENT,
          contentId: wire.contentId as string,
          commentId: wire.commentId
        };
    case P1DestinationName.SEARCH:
      if (typeof wire.query !== 'string' || wire.id !== undefined || wire.contentId !== undefined ||
        wire.commentId !== undefined || !hasOnlyFields(wire, ['name', 'query'])) {
        return undefined;
      }
      return { name: P1DestinationName.SEARCH, query: wire.query };
    default:
      return undefined;
  }
}

export function isInfrastructureDestination(destination: P1Destination): boolean {
  switch (destination.name) {
    case P1DestinationName.SETTINGS:
    case P1DestinationName.TECHNICAL_LAB:
    case P1DestinationName.READER_PROBE:
    case P1DestinationName.IMAGE_PROBE:
    case P1DestinationName.DATABASE_PROBE:
    case P1DestinationName.DEEP_LINK_PROBE:
    case P1DestinationName.QR_SCAN_PROBE:
    case P1DestinationName.BACKGROUND_TASK_PROBE:
    case P1DestinationName.DOMAIN_FIXTURE_PROBE:
      return true;
    default:
      return false;
  }
}

function decodeContent(wire: WireDestination, name: P1DestinationName.QUESTION | P1DestinationName.ANSWER |
  P1DestinationName.ARTICLE | P1DestinationName.VIDEO | P1DestinationName.PIN |
  P1DestinationName.PEOPLE | P1DestinationName.COLLECTION): ContentDestination | undefined {
  if (!hasText(wire.id) || wire.contentId !== undefined || wire.commentId !== undefined || wire.query !== undefined ||
    !hasOnlyFields(wire, ['name', 'id'])) {
    return undefined;
  }
  return { name: name, id: wire.id as string };
}

function hasNoParameters(wire: WireDestination): boolean {
  return wire.id === undefined && wire.contentId === undefined && wire.commentId === undefined &&
    wire.query === undefined && hasOnlyFields(wire, ['name']);
}

function hasText(value: string | undefined): boolean {
  return typeof value === 'string' && value.trim().length > 0;
}

function hasOnlyFields(wire: WireDestination, allowed: Array<string>): boolean {
  return Object.keys(wire).every((key: string) => allowed.includes(key));
}
