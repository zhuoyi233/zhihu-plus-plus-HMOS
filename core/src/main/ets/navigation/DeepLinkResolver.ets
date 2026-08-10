import { parseAbsoluteUrl, ParsedAbsoluteUrl } from './AbsoluteUrlParser';

export enum DeepLinkType {
  ANSWER = 'answer',
  QUESTION = 'question',
  ARTICLE = 'article',
  PERSON = 'person',
  VIDEO = 'video',
  PIN = 'pin',
  SEARCH = 'search',
  MAIN_TABS = 'main_tabs'
}

export interface DeepLinkDestination {
  type: DeepLinkType;
  id: string;
  query: string;
}

const MAX_REDIRECT_DEPTH: number = 2;

export function resolveZhihuLink(input: string): DeepLinkDestination | undefined {
  return resolveZhihuLinkAtDepth(input.trim(), 0);
}

export function describeDeepLink(destination: DeepLinkDestination): string {
  switch (destination.type) {
    case DeepLinkType.ANSWER:
      return `回答：${destination.id}`;
    case DeepLinkType.QUESTION:
      return `问题：${destination.id}`;
    case DeepLinkType.ARTICLE:
      return `文章：${destination.id}`;
    case DeepLinkType.PERSON:
      return `用户：${destination.id}`;
    case DeepLinkType.VIDEO:
      return `视频：${destination.id}`;
    case DeepLinkType.PIN:
      return `想法：${destination.id}`;
    case DeepLinkType.SEARCH:
      return `搜索：${destination.query}`;
    case DeepLinkType.MAIN_TABS:
      return '首页';
  }
}

function resolveZhihuLinkAtDepth(input: string, depth: number): DeepLinkDestination | undefined {
  if (input.length === 0 || depth > MAX_REDIRECT_DEPTH) {
    return undefined;
  }

  const parsed: ParsedAbsoluteUrl | undefined = parseAbsoluteUrl(input);
  if (parsed === undefined) {
    return undefined;
  }

  const protocol = parsed.protocol.toLowerCase();
  const host = parsed.hostname.toLowerCase();
  const segments = parsed.pathname.split('/').filter((segment: string) => segment.length > 0);
  const emptyQuery = '';

  if (protocol === 'http:' || protocol === 'https:') {
    if (parsed.hasUserInfo || parsed.port.length > 0) {
      return undefined;
    }
    if (host === 'link.zhihu.com') {
      const target = parsed.params.get('target');
      return target === undefined ? undefined : resolveZhihuLinkAtDepth(target, depth + 1);
    }
    if (host === 'zhuanlan.zhihu.com') {
      if (segments.length === 2 && segments[0] === 'p' && isDecimalId(segments[1])) {
        return { type: DeepLinkType.ARTICLE, id: segments[1], query: emptyQuery };
      }
      return undefined;
    }
    if (host !== 'zhihu.com' && host !== 'www.zhihu.com') {
      return undefined;
    }

    if (segments.length === 4 && segments[0] === 'question' && isDecimalId(segments[1]) &&
      segments[2] === 'answer' && isDecimalId(segments[3])) {
      return { type: DeepLinkType.ANSWER, id: segments[3], query: emptyQuery };
    }
    if (segments.length === 2 && segments[0] === 'answer' && isDecimalId(segments[1])) {
      return { type: DeepLinkType.ANSWER, id: segments[1], query: emptyQuery };
    }
    if (segments.length === 2 && segments[0] === 'question' && isDecimalId(segments[1])) {
      return { type: DeepLinkType.QUESTION, id: segments[1], query: emptyQuery };
    }
    if (segments.length === 3 && segments[0] === 'oia' && segments[1] === 'articles' &&
      isDecimalId(segments[2])) {
      return { type: DeepLinkType.ARTICLE, id: segments[2], query: emptyQuery };
    }
    if (segments.length === 2 && segments[0] === 'people' && segments[1].length > 0) {
      return { type: DeepLinkType.PERSON, id: segments[1], query: emptyQuery };
    }
    if (segments.length === 2 && segments[0] === 'video' && isDecimalId(segments[1])) {
      return { type: DeepLinkType.VIDEO, id: segments[1], query: emptyQuery };
    }
    if (segments.length === 2 && segments[0] === 'pin' && isDecimalId(segments[1])) {
      return { type: DeepLinkType.PIN, id: segments[1], query: emptyQuery };
    }
    if (segments.length === 3 && segments[0] === 'appview' && isDecimalId(segments[2])) {
      if (segments[1] === 'pin') {
        return { type: DeepLinkType.PIN, id: segments[2], query: emptyQuery };
      }
      if (segments[1] === 'answer') {
        return { type: DeepLinkType.ANSWER, id: segments[2], query: emptyQuery };
      }
      if (segments[1] === 'p') {
        return { type: DeepLinkType.ARTICLE, id: segments[2], query: emptyQuery };
      }
      return undefined;
    }
    if (segments.length === 1 && segments[0] === 'search') {
      return { type: DeepLinkType.SEARCH, id: '', query: parsed.params.get('q') ?? '' };
    }
    return undefined;
  }

  if (protocol !== 'zhihu:') {
    return undefined;
  }
  if (host === 'feed' && segments.length === 0) {
    return { type: DeepLinkType.MAIN_TABS, id: '', query: emptyQuery };
  }
  if (host === 'search' && segments.length === 0) {
    return { type: DeepLinkType.SEARCH, id: '', query: parsed.params.get('q') ?? '' };
  }
  if (segments.length !== 1 || !isDecimalId(segments[0])) {
    return undefined;
  }
  if (host === 'answers') {
    return { type: DeepLinkType.ANSWER, id: segments[0], query: emptyQuery };
  }
  if (host === 'questions') {
    return { type: DeepLinkType.QUESTION, id: segments[0], query: emptyQuery };
  }
  if (host === 'articles') {
    return { type: DeepLinkType.ARTICLE, id: segments[0], query: emptyQuery };
  }
  if (host === 'pin') {
    return { type: DeepLinkType.PIN, id: segments[0], query: emptyQuery };
  }
  return undefined;
}

function isDecimalId(value: string): boolean {
  return /^\d+$/.test(value);
}
