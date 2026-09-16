import {
  JsonArrayValue,
  jsonBoolean,
  jsonNumber,
  JsonObjectValue,
  jsonString,
  JsonValue,
  parseStrictJson
} from 'core';
import { FeedItem, FeedPage, FeedTargetKind, PageCursor, UserProfile } from './DomainModels';

function objectValue(value: JsonValue | undefined): JsonObjectValue | undefined {
  return value instanceof JsonObjectValue ? value : undefined;
}

function arrayValue(value: JsonValue | undefined): Array<JsonValue> {
  return value instanceof JsonArrayValue ? value.items : [];
}

function findObject(values: Array<JsonValue>, field: string, expected: string): JsonObjectValue | undefined {
  return values.map((value: JsonValue): JsonObjectValue | undefined => objectValue(value))
    .find((value: JsonObjectValue | undefined): boolean =>
      value !== undefined && jsonString(value.get(field)) === expected);
}

function actionRoute(card: JsonObjectValue): string | undefined {
  const action = objectValue(card.get('action'));
  const parameter = jsonString(action?.get('parameter'));
  if (parameter === undefined) return undefined;
  const marker = 'route_url=';
  const offset = parameter.indexOf(marker);
  if (offset < 0) return undefined;
  const encoded = parameter.substring(offset + marker.length).split('&')[0];
  try {
    return decodeURIComponent(encoded);
  } catch (_error) {
    return undefined;
  }
}

interface MobileRouteTarget {
  kind: FeedTargetKind;
  id: string;
}

function routeTarget(url: string): MobileRouteTarget | undefined {
  const answer = /\/question\/[1-9][0-9]{0,29}\/answer\/([1-9][0-9]{0,29})(?:[/?#]|$)/.exec(url);
  if (answer !== null) return { kind: FeedTargetKind.ANSWER, id: answer[1] };
  const article = /\/p\/([1-9][0-9]{0,29})(?:[/?#]|$)/.exec(url);
  if (article !== null) return { kind: FeedTargetKind.ARTICLE, id: article[1] };
  const question = /\/question\/([1-9][0-9]{0,29})(?:[/?#]|$)/.exec(url);
  if (question !== null) return { kind: FeedTargetKind.QUESTION, id: question[1] };
  const video = /\/(?:video|zvideo)\/([1-9][0-9]{0,29})(?:[/?#]|$)/.exec(url);
  if (video !== null) return { kind: FeedTargetKind.VIDEO, id: video[1] };
  return undefined;
}

function mobileAuthor(children: Array<JsonValue>): UserProfile | undefined {
  const line = children.map((value: JsonValue): JsonObjectValue | undefined => objectValue(value))
    .find((value: JsonObjectValue | undefined): boolean => {
      const style = value === undefined ? undefined : jsonString(value.get('style'));
      return style?.startsWith('RecommendAuthorLine') === true || style?.startsWith('LineAuthor_default') === true;
    });
  const elements = arrayValue(line?.get('elements'));
  const name = jsonString(findObject(elements, 'type', 'Text')?.get('text'));
  if (name === undefined || name.trim().length === 0) return undefined;
  const avatarElement = findObject(elements, 'style', 'Avatar_default');
  const avatarUrl = jsonString(objectValue(avatarElement?.get('image'))?.get('url'));
  const id = jsonString(line?.get('author_id')) ?? `mobile-${name}`;
  return {
    id: id,
    name: name,
    headline: '',
    avatarUrl: avatarUrl,
    followerCount: 0,
    isFollowing: jsonBoolean(line?.get('is_following')) ?? false,
    isOrganization: false
  };
}

function reactionCount(children: Array<JsonValue>, reaction: string): number {
  for (let index = 0; index < children.length; index += 1) {
    const child = objectValue(children[index]);
    const elements = arrayValue(child?.get('elements'));
    const reactionElement = findObject(elements, 'reaction', reaction);
    const count = jsonNumber(reactionElement?.get('count'));
    if (count !== undefined && Number.isFinite(count)) return count;
  }
  return 0;
}

function decodeCard(value: JsonValue): FeedItem | undefined {
  const card = objectValue(value);
  if (card === undefined || jsonString(card.get('type')) !== 'ComponentCard') return undefined;
  const url = actionRoute(card);
  const target = url === undefined ? undefined : routeTarget(url);
  if (url === undefined || target === undefined) return undefined;
  const children = arrayValue(card.get('children'));
  const title = jsonString(findObject(children, 'id', 'Text')?.get('text'));
  if (title === undefined || title.trim().length === 0) return undefined;
  const excerpt = jsonString(findObject(children, 'id', 'text_pin_summary')?.get('text')) ?? '';
  const id = jsonString(card.get('id')) ?? `mobile-${target.kind}-${target.id}`;
  return {
    id: id,
    verb: '手机版推荐',
    createdAt: 0,
    updatedAt: 0,
    target: {
      kind: target.kind,
      id: target.id,
      title: title,
      excerpt: excerpt,
      url: url,
      voteupCount: reactionCount(children, 'Vote'),
      commentCount: reactionCount(children, 'Comment'),
      author: mobileAuthor(children),
      topicIds: []
    }
  };
}

export function isMobileHomeFeedCursorUrl(url: string): boolean {
  return !/[\u0000-\u0020\u007F-\uFFFF]/.test(url) &&
    /^https:\/\/api\.zhihu\.com\/topstory\/recommend(?:\?[^#]*)?$/.test(url);
}

export function decodeMobileHomeFeedPage(json: string): FeedPage {
  const root = parseStrictJson(json);
  if (!(root instanceof JsonObjectValue)) throw new Error('移动推荐响应结构无效');
  const data = root.get('data');
  if (!(data instanceof JsonArrayValue)) throw new Error('移动推荐数据缺失');
  const items: Array<FeedItem> = [];
  data.items.forEach((value: JsonValue): void => {
    const item = decodeCard(value);
    if (item !== undefined) items.push(item);
  });
  const paging = objectValue(root.get('paging'));
  const next = jsonString(paging?.get('next'));
  const previous = jsonString(paging?.get('previous'));
  const cursor: PageCursor = {
    isEnd: jsonBoolean(paging?.get('is_end')) ?? next === undefined,
    isStart: jsonBoolean(paging?.get('is_start')) ?? previous === undefined,
    next: next,
    previous: previous,
    page: jsonNumber(paging?.get('page')) ?? 0,
    total: jsonNumber(paging?.get('totals')) ?? 0
  };
  return { items: items, cursor: cursor };
}
