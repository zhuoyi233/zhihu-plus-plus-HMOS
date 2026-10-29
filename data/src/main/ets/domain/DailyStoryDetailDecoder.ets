import {
  AppDestination,
  DeepLinkDestination,
  DeepLinkType,
  isSafeDecimalContentId,
  JsonObjectValue,
  JsonStringValue,
  JsonValue,
  jsonArray,
  jsonIntegerLiteral,
  jsonNumber,
  jsonString,
  parseAbsoluteUrl,
  ParsedAbsoluteUrl,
  parseStrictJson,
  resolveZhihuLink,
  StrictJsonError,
  toAppDestination
} from 'core';
import { DomainDecodeError, DomainDecodeFailureKind } from './ZhihuDomainDecoder';

/**
 * 日报正文载荷：只承载数据，不依赖 `reader`。
 *
 * 块转换（`ReaderBlock[]`）由 reader 的日报适配器完成，entry 负责组合元数据与解析结果。
 * 这样 data 不新增 `data → reader` 依赖，保持现有依赖方向（data、reader 各自只依赖 core）。
 */
export interface DailyStorySection {
  /** 栏目名（如「瞎扯」）；未知为空串。 */
  readonly name: string;
  /** 栏目缩略图；未提供时为空串。 */
  readonly thumbnailUrl: string;
  /** 栏目 ID；未知为 0。 */
  readonly id: number;
}

export interface DailyStoryPayload {
  /** 已与请求 ID 核对过的十进制字符串 ID（不经 Number 中转，避免长 ID 丢精度）。 */
  readonly id: string;
  readonly title: string;
  /** 不可信 HTML 正文载荷；空串表示服务端未返回正文。 */
  readonly bodyHtml: string;
  /** 头图候选；没有候选时为空串。 */
  readonly imageUrl: string;
  /** 头图候选列表（保留响应顺序，仅作候选信息，不与正文图重复输出）。 */
  readonly imageUrls: Array<string>;
  readonly section?: DailyStorySection;
  /** 服务端原始 type 值；语义尚未建立，不用于分流。 */
  readonly rawType: number;
  /** 规范化后的分享/回退地址：始终为本应用构造的 https://daily.zhihu.com/story/{id}。 */
  readonly shareUrl: string;
  /** 响应中的原始 url（仅诊断用，不直接用于导航或分享）。 */
  readonly responseUrl: string;
  /** 可选发布时间（epoch 秒）；服务端未提供时为 0。 */
  readonly publishTimeSeconds: number;
  /**
   * 响应内可解析的讨论/原文目标（view-more → originUrl → 正文问答链接）。
   * 阅读页页尾用它渲染「查看知乎讨论」按钮；解析不到时为 undefined（不猜测目标）。
   */
  readonly originDestination?: AppDestination;
}

/** 正文载入上限（UTF-8 字节，明确不同于 string.length）：超限拒绝解析，不静默截断。 */
export const DAILY_STORY_MAX_BODY_UTF8_BYTES: number = 512 * 1024;

const MAX_DAILY_STORY_TITLE_LENGTH: number = 300;
const MAX_DAILY_STORY_SECTION_NAME_LENGTH: number = 60;
const MAX_DAILY_STORY_IMAGE_URL_LENGTH: number = 8192;
const SAFE_STORY_ID_PATTERN: RegExp = /^[1-9][0-9]{0,29}$/;

/** 统计 UTF-8 字节数（与 string.length 区分：中文/emoji 的代码单元数与字节数不同）。 */
export function dailyStoryUtf8ByteLength(value: string): number {
  let bytes = 0;
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    if (code < 0x80) {
      bytes += 1;
    } else if (code < 0x800) {
      bytes += 2;
    } else if (code >= 0xd800 && code <= 0xdbff && index + 1 < value.length) {
      const low = value.charCodeAt(index + 1);
      if (low >= 0xdc00 && low <= 0xdfff) {
        bytes += 4;
        index += 1;
      } else {
        bytes += 3;
      }
    } else {
      bytes += 3;
    }
  }
  return bytes;
}

/**
 * 响应 ID 解析：数字字面量按原始文本保留（长 ID 不经 Number 中转而丢精度），
 * 字符串 ID 仅在符合安全十进制规则时接受。
 */
function dailyStoryResponseId(root: JsonObjectValue): string | undefined {
  const value = root.get('id');
  if (value instanceof JsonStringValue) {
    return SAFE_STORY_ID_PATTERN.test(value.value) ? value.value : undefined;
  }
  const literal = jsonIntegerLiteral(value);
  return literal !== undefined && SAFE_STORY_ID_PATTERN.test(literal) ? literal : undefined;
}

function normalizeImageUrl(value: string | undefined): string {
  const trimmed = (value ?? '').trim();
  if (trimmed.length === 0 || trimmed.length > MAX_DAILY_STORY_IMAGE_URL_LENGTH) {
    return '';
  }
  return trimmed.startsWith('//') ? `https:${trimmed}` : trimmed;
}

function parseRoot(json: string): JsonObjectValue {
  try {
    const parsed = parseStrictJson(json);
    if (parsed instanceof JsonObjectValue) {
      return parsed;
    }
  } catch (error) {
    if (error instanceof StrictJsonError) {
      throw new DomainDecodeError(DomainDecodeFailureKind.INVALID_JSON, '日报正文响应不是有效 JSON');
    }
  }
  throw invalid('日报正文响应结构无效');
}

function attributeValue(tag: string, name: string): string {
  const quoted = new RegExp(`\\b${name}\\s*=\\s*(["'])(.*?)\\1`, 'i').exec(tag);
  if (quoted !== null) {
    return quoted[2];
  }
  const unquoted = new RegExp(`\\b${name}\\s*=\\s*([^\\s>]+)`, 'i').exec(tag);
  return unquoted === null ? '' : unquoted[1];
}

function classIncludes(tag: string, name: string): boolean {
  return attributeValue(tag, 'class').split(/\s+/).includes(name);
}

function resolveNativeDestination(url: string): AppDestination | undefined {
  const link: DeepLinkDestination | undefined = resolveZhihuLink(url.trim());
  if (link === undefined) {
    return undefined;
  }
  switch (link.type) {
    case DeepLinkType.ANSWER:
    case DeepLinkType.QUESTION:
    case DeepLinkType.ARTICLE:
      return toAppDestination(link);
    default:
      return undefined;
  }
}

/**
 * 响应内原文/讨论目标：阅读页页尾「查看知乎讨论」按钮的跳转目标。
 *
 * 优先级（从最贴近日报语义到兜底）：
 * 1. `div.view-more` 内的站内链接——日报自带的「查看知乎讨论」入口（指向讨论所在的问题）；
 * 2. 隐藏的 `a.originUrl`——历史原文入口，实测主样本为 `/question/None/answer/None`（不可用）；
 * 3. 正文第一个问答链接——`/question/{id}/answer/{aid}` 归一为问题页，保证页尾仍有讨论入口。
 * 只产出原生可路由目标（问题/回答/文章），解析失败返回 undefined 而非抛错。
 */
export function dailyStoryOriginDestination(html: string): AppDestination | undefined {
  const viewMore = viewMoreDestination(html);
  if (viewMore !== undefined) {
    return viewMore;
  }
  const anchorTags = html.match(/<a\b[^>]*>/gi) ?? [];
  for (let index = 0; index < anchorTags.length; index += 1) {
    const tag = anchorTags[index];
    if (classIncludes(tag, 'originUrl')) {
      const destination = resolveNativeDestination(attributeValue(tag, 'href'));
      if (destination !== undefined) {
        return destination;
      }
    }
  }
  for (let index = 0; index < anchorTags.length; index += 1) {
    const tag = anchorTags[index];
    if (!classIncludes(tag, 'originUrl')) {
      const destination = questionDestination(attributeValue(tag, 'href'));
      if (destination !== undefined) {
        return destination;
      }
    }
  }
  return undefined;
}

/** `div.view-more` 内的站内链接；统一归一为问题页（该入口的语义就是「查看讨论」）。 */
function viewMoreDestination(html: string): AppDestination | undefined {
  const marker = /<div\b[^>]*>/gi;
  let div = marker.exec(html);
  while (div !== null) {
    if (classIncludes(div[0], 'view-more')) {
      const closing = html.indexOf('</div>', marker.lastIndex);
      const section = html.slice(marker.lastIndex, closing < 0 ? html.length : closing);
      const linkTags = section.match(/<a\b[^>]*>/gi) ?? [];
      for (let index = 0; index < linkTags.length; index += 1) {
        const href = attributeValue(linkTags[index], 'href');
        const question = questionDestination(href);
        if (question !== undefined) {
          return question;
        }
        const direct = resolveNativeDestination(href);
        if (direct !== undefined) {
          return direct;
        }
      }
    }
    div = marker.exec(html);
  }
  return undefined;
}

/**
 * 问答链接 → 问题页目标：`/question/{id}` 与 `/question/{id}/answer/{aid}` 都只取问题 ID，
 * 因为「查看讨论」要落在讨论所在的问题而不是某一条回答。只接受知乎主站的绝对地址。
 */
function questionDestination(url: string): AppDestination | undefined {
  const parsed: ParsedAbsoluteUrl | undefined = parseAbsoluteUrl(url.trim());
  if (parsed === undefined) {
    return undefined;
  }
  const protocol = parsed.protocol.toLowerCase();
  const host = parsed.hostname.toLowerCase();
  if ((protocol !== 'https:' && protocol !== 'http:') || parsed.hasUserInfo || parsed.port.length > 0 ||
    (host !== 'zhihu.com' && host !== 'www.zhihu.com')) {
    return undefined;
  }
  const segments = parsed.pathname.split('/').filter((segment: string): boolean => segment.length > 0);
  if (segments.length < 2 || segments[0] !== 'question' || !isSafeDecimalContentId(segments[1])) {
    return undefined;
  }
  return resolveNativeDestination(`https://www.zhihu.com/question/${segments[1]}`);
}

function decodeSection(root: JsonObjectValue): DailyStorySection | undefined {
  const value = root.get('section');
  if (!(value instanceof JsonObjectValue)) {
    return undefined;
  }
  const name = (jsonString(value.get('name')) ?? '').trim();
  if (name.length === 0 || name.length > MAX_DAILY_STORY_SECTION_NAME_LENGTH) {
    return undefined;
  }
  const rawId = jsonNumber(value.get('id')) ?? 0;
  return {
    name: name,
    thumbnailUrl: normalizeImageUrl(jsonString(value.get('thumbnail'))),
    id: Number.isSafeInteger(rawId) && rawId > 0 ? Math.trunc(rawId) : 0
  };
}

/**
 * 解码日报正文响应为 `DailyStoryPayload`。
 *
 * - `expectedId` 存在时校验响应 ID 与之一致（不一致抛 MISSING_FIELD），防止缓存/代理串包；
 * - `body` 缺失或非字符串抛错（与空正文区分：空正文是有效响应，由上层决定降级）；
 * - `url`/`share_url` 不参与导航与分享，分享地址统一取 `shareUrl`（本应用构造）。
 */
export function decodeDailyStoryPayload(json: string, expectedId?: string): DailyStoryPayload {
  const root = parseRoot(json);
  const responseId = dailyStoryResponseId(root);
  if (responseId === undefined) {
    throw invalid('日报正文响应缺少有效 id');
  }
  if (expectedId !== undefined && responseId !== expectedId) {
    throw invalid('日报正文响应 id 与请求不一致');
  }
  const body = root.get('body');
  if (!(body instanceof JsonStringValue)) {
    throw invalid('dailyStory.body 不能为空');
  }
  if (dailyStoryUtf8ByteLength(body.value) > DAILY_STORY_MAX_BODY_UTF8_BYTES) {
    throw invalid('日报正文超出可解析大小上限');
  }
  const image = normalizeImageUrl(jsonString(root.get('image')));
  const imageUrls: Array<string> = [];
  const images = jsonArray(root.get('images'));
  if (images !== undefined) {
    images.items.forEach((item: JsonValue): void => {
      const url = normalizeImageUrl(jsonString(item));
      if (url.length > 0 && !imageUrls.includes(url)) {
        imageUrls.push(url);
      }
    });
  }
  if (image.length > 0 && !imageUrls.includes(image)) {
    imageUrls.unshift(image);
  }
  const rawType = jsonNumber(root.get('type')) ?? 0;
  const publishTime = jsonNumber(root.get('publish_time')) ?? 0;
  const title = (jsonString(root.get('title')) ?? '').trim();
  const payload: DailyStoryPayload = {
    id: responseId,
    title: title.length > MAX_DAILY_STORY_TITLE_LENGTH ? title.slice(0, MAX_DAILY_STORY_TITLE_LENGTH) : title,
    bodyHtml: body.value,
    imageUrl: image,
    imageUrls: imageUrls,
    section: decodeSection(root),
    rawType: Number.isSafeInteger(rawType) ? Math.trunc(rawType) : 0,
    shareUrl: `https://daily.zhihu.com/story/${responseId}`,
    responseUrl: jsonString(root.get('url')) ?? '',
    publishTimeSeconds: Number.isSafeInteger(publishTime) && publishTime > 0 ? Math.trunc(publishTime) : 0,
    originDestination: dailyStoryOriginDestination(body.value)
  };
  return payload;
}

/** 兼容旧契约：只取原文目标（保留给关闭新链路时的旧调用方与既有测试）。 */
export function decodeDailyStoryDestination(json: string): AppDestination | undefined {
  const root = parseRoot(json);
  const body = root.get('body');
  if (!(body instanceof JsonStringValue)) {
    throw invalid('dailyStory.body 不能为空');
  }
  return dailyStoryOriginDestination(body.value);
}

function invalid(message: string): DomainDecodeError {
  return new DomainDecodeError(DomainDecodeFailureKind.MISSING_FIELD, message);
}
