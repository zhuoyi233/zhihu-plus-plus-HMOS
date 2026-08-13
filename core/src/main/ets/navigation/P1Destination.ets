import { JsonObjectValue, JsonStringValue, parseStrictJson } from './StrictJson';

export enum P1DestinationName {
  HOME = 'Home',
  FOLLOWING = 'Following',
  HOT = 'Hot',
  DAILY = 'Daily',
  DAILY_STORY = 'DailyStory',
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
  LOGIN = 'Login',
  SETTINGS = 'Settings',
  BLOCKING_RULES = 'BlockingRules',
  READ_HISTORY = 'ReadHistory',
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
  readonly name: P1DestinationName.HOME | P1DestinationName.FOLLOWING | P1DestinationName.HOT |
    P1DestinationName.DAILY | P1DestinationName.NOTIFICATION;
}

export interface InfrastructureDestination {
  readonly name: P1DestinationName.LOGIN | P1DestinationName.SETTINGS | P1DestinationName.BLOCKING_RULES |
    P1DestinationName.READ_HISTORY | P1DestinationName.TECHNICAL_LAB |
    P1DestinationName.READER_PROBE | P1DestinationName.IMAGE_PROBE |
    P1DestinationName.DATABASE_PROBE | P1DestinationName.DEEP_LINK_PROBE |
    P1DestinationName.QR_SCAN_PROBE | P1DestinationName.BACKGROUND_TASK_PROBE |
    P1DestinationName.DOMAIN_FIXTURE_PROBE;
}

export interface ContentDestination {
  readonly name: P1DestinationName.QUESTION | P1DestinationName.ANSWER |
    P1DestinationName.ARTICLE | P1DestinationName.VIDEO | P1DestinationName.PIN |
    P1DestinationName.PEOPLE | P1DestinationName.COLLECTION | P1DestinationName.DAILY_STORY;
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

export const MAX_SEARCH_QUERY_LENGTH: number = 200;
export const MAX_DECIMAL_CONTENT_ID_LENGTH: number = 30;
export const MAX_PEOPLE_IDENTIFIER_LENGTH: number = 200;

export function isSafeSearchDestinationQuery(value: string | undefined): boolean {
  return typeof value === 'string' && value.length <= MAX_SEARCH_QUERY_LENGTH &&
    !/[\u0000-\u001F\u007F-\u009F]/.test(value);
}

export function isSafeDecimalContentId(value: string | undefined): boolean {
  return typeof value === 'string' && /^\d{1,30}$/.test(value);
}

export function isSafePinContentId(value: string | undefined): boolean {
  return typeof value === 'string' && /^[1-9][0-9]{0,29}$/.test(value);
}

export function isSafePeopleIdentifier(value: string | undefined): boolean {
  return typeof value === 'string' && /^[A-Za-z0-9_-]{1,200}$/.test(value);
}

export function isP1DestinationName(name: string): boolean {
  switch (name) {
    case P1DestinationName.HOME:
    case P1DestinationName.FOLLOWING:
    case P1DestinationName.HOT:
    case P1DestinationName.DAILY:
    case P1DestinationName.DAILY_STORY:
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
    case P1DestinationName.LOGIN:
    case P1DestinationName.SETTINGS:
    case P1DestinationName.BLOCKING_RULES:
    case P1DestinationName.READ_HISTORY:
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
  let wire: JsonObjectValue;
  try {
    const parsed = parseStrictJson(JSON.stringify(param));
    if (!(parsed instanceof JsonObjectValue)) {
      return undefined;
    }
    wire = parsed;
  } catch (_error) {
    return undefined;
  }
  const wireName = readString(wire, 'name');
  if (wireName !== name) {
    return undefined;
  }

  switch (name) {
    case P1DestinationName.HOME:
      return hasNoParameters(wire) ? { name: P1DestinationName.HOME } : undefined;
    case P1DestinationName.FOLLOWING:
      return hasNoParameters(wire) ? { name: P1DestinationName.FOLLOWING } : undefined;
    case P1DestinationName.HOT:
      return hasNoParameters(wire) ? { name: P1DestinationName.HOT } : undefined;
    case P1DestinationName.DAILY:
      return hasNoParameters(wire) ? { name: P1DestinationName.DAILY } : undefined;
    case P1DestinationName.DAILY_STORY:
      return decodeContent(wire, P1DestinationName.DAILY_STORY);
    case P1DestinationName.NOTIFICATION:
      return hasNoParameters(wire) ? { name: P1DestinationName.NOTIFICATION } : undefined;
    case P1DestinationName.LOGIN:
      return hasNoParameters(wire) ? { name: P1DestinationName.LOGIN } : undefined;
    case P1DestinationName.SETTINGS:
      return hasNoParameters(wire) ? { name: P1DestinationName.SETTINGS } : undefined;
    case P1DestinationName.BLOCKING_RULES:
      return hasNoParameters(wire) ? { name: P1DestinationName.BLOCKING_RULES } : undefined;
    case P1DestinationName.READ_HISTORY:
      return hasNoParameters(wire) ? { name: P1DestinationName.READ_HISTORY } : undefined;
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
      const contentId = readString(wire, 'contentId');
      const commentId = readString(wire, 'commentId');
      if (contentId === undefined || !hasText(contentId) || readString(wire, 'id') !== undefined || readString(wire, 'query') !== undefined ||
        (commentId !== undefined && !hasText(commentId)) ||
        !hasOnlyFields(wire, ['name', 'contentId', 'commentId'])) {
        return undefined;
      }
      return commentId === undefined
        ? { name: P1DestinationName.COMMENT, contentId: contentId }
        : {
          name: P1DestinationName.COMMENT,
          contentId: contentId,
          commentId: commentId
        };
    case P1DestinationName.SEARCH:
      const query = readString(wire, 'query');
      if (query === undefined || !isSafeSearchDestinationQuery(query) || readString(wire, 'id') !== undefined ||
        readString(wire, 'contentId') !== undefined || readString(wire, 'commentId') !== undefined ||
        !hasOnlyFields(wire, ['name', 'query'])) {
        return undefined;
      }
      return { name: P1DestinationName.SEARCH, query: query };
    default:
      return undefined;
  }
}

export function isInfrastructureDestination(destination: P1Destination): boolean {
  switch (destination.name) {
    case P1DestinationName.LOGIN:
    case P1DestinationName.SETTINGS:
    case P1DestinationName.BLOCKING_RULES:
    case P1DestinationName.READ_HISTORY:
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

export function shouldReloadAfterAuthentication(destination: P1Destination): boolean {
  switch (destination.name) {
    case P1DestinationName.QUESTION:
    case P1DestinationName.ANSWER:
    case P1DestinationName.ARTICLE:
    case P1DestinationName.SEARCH:
    case P1DestinationName.FOLLOWING:
    case P1DestinationName.PIN:
    case P1DestinationName.PEOPLE:
      return true;
    default:
      return false;
  }
}

function decodeContent(wire: JsonObjectValue, name: P1DestinationName.QUESTION | P1DestinationName.ANSWER |
  P1DestinationName.ARTICLE | P1DestinationName.VIDEO | P1DestinationName.PIN |
  P1DestinationName.PEOPLE | P1DestinationName.COLLECTION | P1DestinationName.DAILY_STORY): ContentDestination | undefined {
  const id = readString(wire, 'id');
  if (id === undefined || !hasText(id) ||
    readString(wire, 'contentId') !== undefined || readString(wire, 'commentId') !== undefined ||
    readString(wire, 'query') !== undefined ||
    !hasOnlyFields(wire, ['name', 'id'])) {
    return undefined;
  }
  let validId = true;
  if (name === P1DestinationName.PIN || name === P1DestinationName.DAILY_STORY) {
    validId = isSafePinContentId(id);
  } else if (name === P1DestinationName.PEOPLE) {
    validId = isSafePeopleIdentifier(id);
  } else if (name === P1DestinationName.QUESTION || name === P1DestinationName.ANSWER ||
    name === P1DestinationName.ARTICLE) {
    validId = isSafeDecimalContentId(id);
  }
  return validId ? { name: name, id: id } : undefined;
}

function hasNoParameters(wire: JsonObjectValue): boolean {
  return readString(wire, 'id') === undefined && readString(wire, 'contentId') === undefined &&
    readString(wire, 'commentId') === undefined && readString(wire, 'query') === undefined &&
    hasOnlyFields(wire, ['name']);
}

function hasText(value: string | undefined): boolean {
  return typeof value === 'string' && value.trim().length > 0;
}

function hasOnlyFields(wire: JsonObjectValue, allowed: Array<string>): boolean {
  return wire.entries.every((entry): boolean => allowed.includes(entry.name));
}

function readString(wire: JsonObjectValue, name: string): string | undefined {
  const value = wire.get(name);
  return value instanceof JsonStringValue ? value.value : undefined;
}
