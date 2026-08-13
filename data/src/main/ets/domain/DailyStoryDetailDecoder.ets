import {
  DeepLinkDestination,
  DeepLinkType,
  JsonObjectValue,
  JsonStringValue,
  P1Destination,
  parseStrictJson,
  resolveZhihuLink,
  StrictJsonError,
  toP1Destination
} from 'core';
import { DomainDecodeError, DomainDecodeFailureKind } from './ZhihuDomainDecoder';

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
  const quoted = new RegExp(`\\b${name}\\s*=\\s*([\"'])(.*?)\\1`, 'i').exec(tag);
  if (quoted !== null) {
    return quoted[2];
  }
  const unquoted = new RegExp(`\\b${name}\\s*=\\s*([^\\s>]+)`, 'i').exec(tag);
  return unquoted === null ? '' : unquoted[1];
}

function classIncludes(tag: string, name: string): boolean {
  return attributeValue(tag, 'class').split(/\\s+/).includes(name);
}

function resolveNativeDestination(url: string): P1Destination | undefined {
  const link: DeepLinkDestination | undefined = resolveZhihuLink(url.trim());
  if (link === undefined) {
    return undefined;
  }
  switch (link.type) {
    case DeepLinkType.ANSWER:
    case DeepLinkType.QUESTION:
    case DeepLinkType.ARTICLE:
      return toP1Destination(link);
    default:
      return undefined;
  }
}

function originUrlDestination(html: string): P1Destination | undefined {
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
  const marker = /<div\b[^>]*>/gi;
  let div = marker.exec(html);
  while (div !== null) {
    if (classIncludes(div[0], 'view-more')) {
      const closing = html.indexOf('</div>', marker.lastIndex);
      const section = html.slice(marker.lastIndex, closing < 0 ? html.length : closing);
      const linkTags = section.match(/<a\b[^>]*>/gi) ?? [];
      for (let index = 0; index < linkTags.length; index += 1) {
        const destination = resolveNativeDestination(attributeValue(linkTags[index], 'href'));
        if (destination !== undefined) {
          return destination;
        }
      }
    }
    div = marker.exec(html);
  }
  return undefined;
}

export function decodeDailyStoryDestination(json: string): P1Destination | undefined {
  const root = parseRoot(json);
  const body = root.get('body');
  if (!(body instanceof JsonStringValue)) {
    throw invalid('dailyStory.body 不能为空');
  }
  return originUrlDestination(body.value);
}

function invalid(message: string): DomainDecodeError {
  return new DomainDecodeError(DomainDecodeFailureKind.MISSING_FIELD, message);
}
