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

function mobileAuthorLine(children: Array<JsonValue>): JsonObjectValue | undefined {
  return children.map((value: JsonValue): JsonObjectValue | undefined => objectValue(value))
    .find((value: JsonObjectValue | undefined): boolean => {
      const style = value === undefined ? undefined : jsonString(value.get('style'));
      return style?.startsWith('RecommendAuthorLine') === true || style?.startsWith('LineAuthor_default') === true;
    });
}

interface MobileAuthorMetadata {
  id?: string;
  name?: string;
  avatarUrl?: string;
  followerCount?: number;
  isFollowing?: boolean;
}

function nonNegativeCount(value: JsonValue | undefined): number | undefined {
  const count = jsonNumber(value);
  return count !== undefined && Number.isSafeInteger(count) && count >= 0 ? count : undefined;
}

function mobileAuthorMetadata(card: JsonObjectValue, line: JsonObjectValue | undefined): MobileAuthorMetadata {
  const extra = objectValue(card.get('extra'));
  const business = objectValue(extra?.get('business_ext_map'));
  const userInfo = objectValue(business?.get('userInfo'));
  const passthrough = objectValue(extra?.get('passthrough_info'));
  const author = objectValue(passthrough?.get('author'));
  // 实际新版响应用 none 明确表示未关注。其他未识别状态保持未知，不能当成 false。
  const followState = jsonString(userInfo?.get('followState'));
  return {
    id: jsonString(line?.get('author_id')) ?? jsonString(author?.get('id')) ??
      jsonString(userInfo?.get('memberHashId')),
    name: jsonString(author?.get('name')) ?? jsonString(userInfo?.get('userName')),
    avatarUrl: jsonString(author?.get('avatar_url')) ?? jsonString(userInfo?.get('avatarUrl')),
    followerCount: nonNegativeCount(line?.get('follower_count')) ??
      nonNegativeCount(line?.get('followers_count')) ?? nonNegativeCount(author?.get('follower_count')),
    isFollowing: jsonBoolean(line?.get('is_following')) ?? jsonBoolean(author?.get('is_following')) ??
      (followState === 'none' ? false : undefined)
  };
}

function mobileAuthor(line: JsonObjectValue | undefined, metadata: MobileAuthorMetadata): UserProfile | undefined {
  const elements = arrayValue(line?.get('elements'));
  const name = jsonString(findObject(elements, 'type', 'Text')?.get('text')) ?? metadata.name;
  if (name === undefined || name.trim().length === 0) return undefined;
  const avatarElement = findObject(elements, 'style', 'Avatar_default');
  const avatarUrl = jsonString(objectValue(avatarElement?.get('image'))?.get('url')) ?? metadata.avatarUrl;
  const id = metadata.id ?? `mobile-${name}`;
  return {
    id: id,
    name: name,
    headline: '',
    avatarUrl: avatarUrl,
    followerCount: metadata.followerCount ?? 0,
    isFollowing: metadata.isFollowing ?? false,
    isOrganization: false
  };
}

function reactionCount(children: Array<JsonValue>, reaction: string): number | undefined {
  for (let index = 0; index < children.length; index += 1) {
    const child = objectValue(children[index]);
    const elements = arrayValue(child?.get('elements'));
    const reactionElement = findObject(elements, 'reaction', reaction);
    const count = nonNegativeCount(reactionElement?.get('count'));
    if (count !== undefined) return count;
  }
  return undefined;
}

interface MobileFooterCount {
  count: number;
  upperBound: number;
}

function footerCount(children: Array<JsonValue>, label: string): MobileFooterCount | undefined {
  for (let index = 0; index < children.length; index += 1) {
    const child = objectValue(children[index]);
    const style = jsonString(child?.get('style'))?.toLowerCase() ?? '';
    if (jsonString(child?.get('type')) !== 'Line' ||
      (jsonString(child?.get('id')) !== 'feed_footer' && !style.startsWith('linefooter'))) continue;
    const elements = arrayValue(child?.get('elements'));
    for (let elementIndex = 0; elementIndex < elements.length; elementIndex += 1) {
      const element = objectValue(elements[elementIndex]);
      if (jsonString(element?.get('type')) !== 'Text') continue;
      const parts = (jsonString(element?.get('text')) ?? '').split(/[·•]/);
      for (let partIndex = 0; partIndex < parts.length; partIndex += 1) {
        const part = parts[partIndex].trim();
        if (!part.endsWith(label)) continue;
        const numberText = part.substring(0, part.length - label.length).trim();
        const match = /^(\d+|\d{1,3}(?:,\d{3})+)(?:\.(\d+))?\s*([万亿])?$/.exec(numberText);
        if (match === null || (match[2] !== undefined && match[3] === undefined)) continue;
        const scale = match[3] === '亿' ? 100000000 : (match[3] === '万' ? 10000 : 1);
        const decimals = match[2] ?? '';
        const count = Number(`${match[1].replace(/,/g, '')}${decimals.length > 0 ? `.${decimals}` : ''}`) * scale;
        // “1.9 万”等为缩写值；过滤使用保守上界，避免阈值落在舍入区间时误屏蔽。
        const upperBound = count + (scale > 1 ? Math.max(1, scale / Math.pow(10, decimals.length)) - 1 : 0);
        if (Number.isSafeInteger(count) && Number.isSafeInteger(upperBound) && count >= 0) {
          return { count: count, upperBound: upperBound };
        }
      }
    }
  }
  return undefined;
}

function decodeCard(value: JsonValue): FeedItem | undefined {
  const card = objectValue(value);
  if (card === undefined || jsonString(card.get('type')) !== 'ComponentCard') return undefined;
  const url = actionRoute(card);
  const target = url === undefined ? undefined : routeTarget(url);
  if (url === undefined || target === undefined) return undefined;
  const children = arrayValue(card.get('children'));
  const authorLine = mobileAuthorLine(children);
  const authorMetadata = mobileAuthorMetadata(card, authorLine);
  const voteCount = reactionCount(children, 'Vote');
  const voteFooter = voteCount === undefined ? footerCount(children, '赞同') : undefined;
  const commentCount = reactionCount(children, 'Comment') ?? footerCount(children, '评论')?.count;
  const title = jsonString(findObject(children, 'id', 'Text')?.get('text'));
  if (title === undefined || title.trim().length === 0) return undefined;
  const excerpt = jsonString(findObject(children, 'id', 'text_pin_summary')?.get('text')) ?? '';
  const id = jsonString(card.get('id')) ?? `mobile-${target.kind}-${target.id}`;
  return {
    id: id,
    // 对齐上游 AndroidHomeFeedViewModel：移动端推荐卡 details 追加「手机版推荐」，
    // 混合推荐模式下与 Web 卡（action_text）区分来源。
    verb: '手机版推荐',
    actionText: '手机版推荐',
    createdAt: 0,
    updatedAt: 0,
    target: {
      kind: target.kind,
      id: target.id,
      title: title,
      excerpt: excerpt,
      url: url,
      voteupCount: voteCount ?? voteFooter?.count,
      voteupCountUpperBound: voteFooter?.upperBound,
      commentCount: commentCount,
      author: mobileAuthor(authorLine, authorMetadata),
      authorFollowerCount: authorMetadata.followerCount,
      authorIsFollowing: authorMetadata.isFollowing,
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
