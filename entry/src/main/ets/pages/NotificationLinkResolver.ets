import { DeepLinkType, isSafePeopleIdentifier, parseAbsoluteUrl, P1Destination, P1DestinationName,
  resolveZhihuLink } from 'core';
import { MobileNotificationTimelineItem, mobileNotificationAvatarUrl } from 'data';

/**
 * 通知链接 → 页面目的地。优先级对齐上游 `navDestination()`：
 * content.targetLink → content.subTargetLink → targetSource.targetLink → head.targetLink，
 * 私信（inbox）优先，其次非个人主页链接，再次首个可解析链接，最后 target 人员兜底。
 */
export function timelineItemDestination(item: MobileNotificationTimelineItem): P1Destination | undefined {
  const links: Array<string> = [];
  const content = item.content;
  if (content !== undefined) {
    if (content.targetLink.trim().length > 0) {
      links.push(content.targetLink);
    }
    if (content.subTargetLink.trim().length > 0) {
      links.push(content.subTargetLink);
    }
  }
  const sourceLink = item.targetSource?.targetLink ?? '';
  if (sourceLink.trim().length > 0) {
    links.push(sourceLink);
  }
  const headLink = item.head?.targetLink ?? '';
  if (headLink.trim().length > 0) {
    links.push(headLink);
  }
  const resolved: Array<P1Destination> = [];
  links.forEach((link: string): void => {
    const destination = notificationLinkDestination(link);
    if (destination !== undefined) {
      resolved.push(destination);
    }
  });
  const message = resolved.find((destination: P1Destination): boolean =>
    destination.name === P1DestinationName.PRIVATE_MESSAGE);
  if (message !== undefined) {
    return message;
  }
  const nonPerson = resolved.find((destination: P1Destination): boolean =>
    destination.name !== P1DestinationName.PEOPLE);
  if (nonPerson !== undefined) {
    return nonPerson;
  }
  if (resolved.length > 0) {
    return resolved[0];
  }
  const target = item.target;
  if (target !== undefined && target.type === 'people') {
    const identifier = target.urlToken.trim().length > 0 ? target.urlToken : target.id;
    if (isSafePeopleIdentifier(identifier)) {
      return { name: P1DestinationName.PEOPLE, id: identifier };
    }
  }
  return undefined;
}

/**
 * 单条通知链接解析。识别上游私有的 inbox / timeline-entry 路径，其余交给
 * `resolveZhihuLink`（question/answer/article/pin/people 等）。
 */
export function notificationLinkDestination(link: string): P1Destination | undefined {
  if (link.length === 0 || link.length > 8192) {
    return undefined;
  }
  const parsed = parseAbsoluteUrl(link);
  if (parsed === undefined) {
    return undefined;
  }
  const protocol = parsed.protocol.toLowerCase();
  const host = parsed.hostname.toLowerCase();
  if (protocol !== 'https:' || (host !== 'www.zhihu.com' && host !== 'zhihu.com')) {
    return contentLinkDestination(link);
  }
  const segments = parsed.pathname.split('/').filter((segment: string): boolean => segment.length > 0);
  if (segments.length === 2 && segments[0] === 'inbox') {
    const peerId = segments[1];
    if (!/^[A-Za-z0-9_-]{1,128}$/.test(peerId)) {
      return undefined;
    }
    const title = parsed.params.get('title') ?? '';
    return {
      name: P1DestinationName.PRIVATE_MESSAGE,
      peerId: peerId,
      peerName: title.trim().length > 0 ? title : undefined
    };
  }
  if (segments.length === 5 && segments[0] === 'notifications' && segments[1] === 'v3' &&
    segments[2] === 'timeline' && segments[3] === 'entry') {
    const entryName = segments[4];
    if (!/^[a-z_]{1,40}$/.test(entryName)) {
      return undefined;
    }
    const title = parsed.params.get('title') ?? '';
    return {
      name: P1DestinationName.NOTIFICATION_ENTRY,
      entryName: entryName,
      title: title.trim().length > 0 ? title : '消息'
    };
  }
  return contentLinkDestination(link);
}

/** 站内内容链接（question/answer/article/pin/people）→ 目的地。 */
export function contentLinkDestination(link: string): P1Destination | undefined {
  const deep = resolveZhihuLink(link);
  if (deep === undefined) {
    return undefined;
  }
  if (deep.type === DeepLinkType.QUESTION) {
    return { name: P1DestinationName.QUESTION, id: deep.id };
  }
  if (deep.type === DeepLinkType.ANSWER) {
    return { name: P1DestinationName.ANSWER, id: deep.id };
  }
  if (deep.type === DeepLinkType.ARTICLE) {
    return { name: P1DestinationName.ARTICLE, id: deep.id };
  }
  if (deep.type === DeepLinkType.PIN) {
    return { name: P1DestinationName.PIN, id: deep.id };
  }
  if (deep.type === DeepLinkType.PERSON) {
    return isSafePeopleIdentifier(deep.id) ? { name: P1DestinationName.PEOPLE, id: deep.id } : undefined;
  }
  return undefined;
}

export function timelineItemAvatarUrl(item: MobileNotificationTimelineItem): string {
  return mobileNotificationAvatarUrl(item);
}
