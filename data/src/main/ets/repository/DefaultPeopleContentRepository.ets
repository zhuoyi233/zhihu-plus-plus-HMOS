import {
  peopleContentIdentity,
  PeopleContentItem,
  PeopleContentPage,
  PeopleContentSection,
  PageCursor
} from '../domain/DomainModels';
import { decodePeopleContentPage } from '../domain/PeopleContentDecoder';
import { ZhihuHttpClient, ZhihuHttpResponse } from '../network/ZhihuHttpClient';
import { normalizePeopleIdentifier } from './DefaultPeopleRepository';
import { PeopleContentRepository } from './PeopleContentRepository';

const PEOPLE_CONTENT_LIMIT = 20;
const PEOPLE_CONTENT_CURSOR_MAX_LENGTH = 4096;
const ANSWERS_INCLUDE = 'data[*].question,excerpt,voteup_count,comment_count,created_time';
const ARTICLES_INCLUDE = 'data[*].title,excerpt,voteup_count,comment_count,created,updated';
const ACTIVITIES_INCLUDE = 'data[*].target.question,excerpt,voteup_count,comment_count,created_time,like_count';

export enum PeopleContentRepositoryFailureKind {
  INVALID_CURSOR = 'invalid_cursor',
  REPEATED_CURSOR = 'repeated_cursor',
  CANCELLED = 'cancelled'
}

export class PeopleContentRepositoryFailure extends Error {
  readonly kind: PeopleContentRepositoryFailureKind;

  constructor(kind: PeopleContentRepositoryFailureKind) {
    super(kind === PeopleContentRepositoryFailureKind.INVALID_CURSOR
      ? '用户内容返回了不受信任的分页地址'
      : kind === PeopleContentRepositoryFailureKind.REPEATED_CURSOR
        ? '用户内容分页游标已被请求'
        : '用户内容请求已取消');
    this.name = 'PeopleContentRepositoryFailure';
    this.kind = kind;
  }
}

function includeFor(section: PeopleContentSection): string {
  if (section === PeopleContentSection.ANSWERS) {
    return ANSWERS_INCLUDE;
  }
  if (section === PeopleContentSection.ARTICLES) {
    return ARTICLES_INCLUDE;
  }
  return ACTIVITIES_INCLUDE;
}

function baseUrl(identifier: string, section: PeopleContentSection): string {
  const encoded = encodeURIComponent(identifier);
  if (section === PeopleContentSection.ANSWERS) {
    return `https://www.zhihu.com/api/v4/members/${encoded}/answers`;
  }
  if (section === PeopleContentSection.ARTICLES) {
    return `https://www.zhihu.com/api/v4/members/${encoded}/articles`;
  }
  return `https://www.zhihu.com/api/v3/moments/${encoded}/activities`;
}

function allowedCursorPrefix(identifier: string, section: PeopleContentSection): string {
  return `${baseUrl(identifier, section)}?`;
}

export function isPeopleContentCursorUrl(identifier: string, section: PeopleContentSection, cursor: string): boolean {
  if (cursor.length === 0 || cursor.length > PEOPLE_CONTENT_CURSOR_MAX_LENGTH ||
    /[\u0000-\u0020\u007F-\uFFFF]/.test(cursor)) {
    return false;
  }
  return cursor.startsWith(allowedCursorPrefix(identifier, section)) && !cursor.includes('#');
}

export function buildPeopleContentUrl(identifierValue: string, section: PeopleContentSection, cursor?: string): string {
  const identifier = normalizePeopleIdentifier(identifierValue);
  const include = `include=${encodeURIComponent(includeFor(section)).replace(/\*/g, '%2A')}`;
  if (cursor === undefined) {
    const sort = section === PeopleContentSection.ANSWERS ? 'sort_by=voteups&' :
      section === PeopleContentSection.ARTICLES ? 'sort_by=created&' : '';
    return `${baseUrl(identifier, section)}?${sort}limit=${PEOPLE_CONTENT_LIMIT}&${include}`;
  }
  if (!isPeopleContentCursorUrl(identifier, section, cursor)) {
    throw new PeopleContentRepositoryFailure(PeopleContentRepositoryFailureKind.INVALID_CURSOR);
  }
  const queryStart = cursor.indexOf('?');
  const values = cursor.substring(queryStart + 1).split('&');
  const preserved: Array<string> = [];
  values.forEach((value: string): void => {
    if (value.length === 0) {
      return;
    }
    const separator = value.indexOf('=');
    const encodedName = separator < 0 ? value : value.substring(0, separator);
    const encodedValue = separator < 0 ? '' : value.substring(separator + 1);
    let name: string;
    let decoded: string;
    try {
      name = decodeURIComponent(encodedName.replace(/\+/g, '%20'));
      decoded = decodeURIComponent(encodedValue.replace(/\+/g, '%20'));
    } catch (_error) {
      throw new PeopleContentRepositoryFailure(PeopleContentRepositoryFailureKind.INVALID_CURSOR);
    }
    if (!/^[A-Za-z0-9_.~-]+$/.test(name) || /[\u0000-\u001F\u007F]/.test(decoded)) {
      throw new PeopleContentRepositoryFailure(PeopleContentRepositoryFailureKind.INVALID_CURSOR);
    }
    if (name !== 'include') {
      preserved.push(`${encodeURIComponent(name)}=${encodeURIComponent(decoded)}`);
    }
  });
  preserved.push(include);
  return `${baseUrl(identifier, section)}?${preserved.join('&')}`;
}

function terminalCursor(cursor: PageCursor): PageCursor {
  return {
    isEnd: true,
    isStart: cursor.isStart,
    previous: cursor.previous,
    page: cursor.page,
    total: cursor.total
  };
}

export class DefaultPeopleContentRepository implements PeopleContentRepository {
  private readonly httpClient: ZhihuHttpClient;
  private requested: Set<string> = new Set<string>();
  private delivered: Set<string> = new Set<string>();
  private activeIdentifier?: string;
  private activeSection?: PeopleContentSection;
  private generation: number = 0;

  constructor(httpClient: ZhihuHttpClient) {
    this.httpClient = httpClient;
  }

  cancel(): void {
    this.generation += 1;
    this.httpClient.cancel();
  }

  async getContentPage(identifierValue: string, section: PeopleContentSection, cursor?: string): Promise<PeopleContentPage> {
    const identifier = normalizePeopleIdentifier(identifierValue);
    if (cursor !== undefined && (identifier !== this.activeIdentifier || section !== this.activeSection)) {
      throw new PeopleContentRepositoryFailure(PeopleContentRepositoryFailureKind.INVALID_CURSOR);
    }
    const requestUrl = buildPeopleContentUrl(identifier, section, cursor);
    if (cursor !== undefined && this.requested.has(requestUrl)) {
      throw new PeopleContentRepositoryFailure(PeopleContentRepositoryFailureKind.REPEATED_CURSOR);
    }
    const requestGeneration = this.generation;
    const response: ZhihuHttpResponse = await this.httpClient.execute({
      url: requestUrl,
      accept: 'application/json',
      useSession: true,
      signWithZse: true
    });
    if (requestGeneration !== this.generation) {
      throw new PeopleContentRepositoryFailure(PeopleContentRepositoryFailureKind.CANCELLED);
    }
    const page = decodePeopleContentPage(response.body, section);
    const requested = cursor === undefined ? new Set<string>() : cloneSet(this.requested);
    const delivered = cursor === undefined ? new Set<string>() : cloneSet(this.delivered);
    requested.add(requestUrl);
    const items = page.items.filter((item: PeopleContentItem): boolean => {
      const identity = peopleContentIdentity(item);
      if (delivered.has(identity)) {
        return false;
      }
      delivered.add(identity);
      return true;
    });
    const next = page.cursor.next;
    const repeats = (next === undefined && !page.cursor.isEnd) ||
      (next !== undefined && requested.has(buildPeopleContentUrl(identifier, section, next)));
    this.activeIdentifier = identifier;
    this.activeSection = section;
    this.requested = requested;
    this.delivered = delivered;
    return { items: items, cursor: repeats ? terminalCursor(page.cursor) : page.cursor };
  }
}

function cloneSet(source: Set<string>): Set<string> {
  const result = new Set<string>();
  source.forEach((value: string): void => {
    result.add(value);
  });
  return result;
}
