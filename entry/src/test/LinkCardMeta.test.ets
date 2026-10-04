import { describe, expect, it } from '@ohos/hypium';
import { DeepLinkType } from 'core';
import {
  decodeLinkCardMeta,
  DefaultLinkCardMetaRepository,
  LinkCardResourceKind,
  PreparedZhihuHttpRequest,
  SessionCookie,
  SessionCookieProvider,
  ZhihuHttpClient,
  ZhihuHttpResponse,
  ZhihuHttpTransport,
  ZhihuHttpTransportFactory
} from 'data';
import { formatLinkCardCount, linkCardKindLabel, linkCardMetaLine } from '../main/ets/pages/LinkCardMetaText';

class MetaSessionProvider implements SessionCookieProvider {
  getCookies(): Array<SessionCookie> {
    return [{ name: 'd_c0', value: 'link-card-device-cookie' }];
  }
}

class MetaTransport implements ZhihuHttpTransport {
  private readonly response: ZhihuHttpResponse;
  readonly requests: Array<PreparedZhihuHttpRequest> = [];

  constructor(response: ZhihuHttpResponse) {
    this.response = response;
  }

  request(request: PreparedZhihuHttpRequest): Promise<ZhihuHttpResponse> {
    this.requests.push(request);
    return Promise.resolve(this.response);
  }

  destroy(): void {
  }
}

class MetaTransportFactory implements ZhihuHttpTransportFactory {
  private readonly response: ZhihuHttpResponse;
  readonly transports: Array<MetaTransport> = [];

  constructor(response: ZhihuHttpResponse) {
    this.response = response;
  }

  create(): ZhihuHttpTransport {
    const transport = new MetaTransport(this.response);
    this.transports.push(transport);
    return transport;
  }
}

function jsonResponse(body: string): ZhihuHttpResponse {
  return { statusCode: 200, body: body };
}

export default function linkCardMetaTest(): void {
  describe('linkCardMeta', (): void => {
    it('decodes answer meta', 0, (): void => {
      const meta = decodeLinkCardMeta('{"id":1,"voteup_count":123,"comment_count":45}', DeepLinkType.ANSWER);
      expect(meta !== undefined).assertTrue();
      if (meta === undefined) {
        return;
      }
      expect(meta.kind === LinkCardResourceKind.ANSWER).assertTrue();
      expect(meta.voteupCount === 123).assertTrue();
      expect(meta.commentCount === 45).assertTrue();
      expect(meta.answerCount === undefined).assertTrue();
    });

    it('decodes article meta', 0, (): void => {
      const meta = decodeLinkCardMeta('{"id":2,"voteup_count":0,"comment_count":7}', DeepLinkType.ARTICLE);
      expect(meta !== undefined).assertTrue();
      if (meta === undefined) {
        return;
      }
      expect(meta.kind === LinkCardResourceKind.ARTICLE).assertTrue();
      expect(meta.voteupCount === 0).assertTrue();
      expect(meta.commentCount === 7).assertTrue();
    });

    it('decodes question meta', 0, (): void => {
      const meta = decodeLinkCardMeta('{"id":3,"answer_count":128}', DeepLinkType.QUESTION);
      expect(meta !== undefined).assertTrue();
      if (meta === undefined) {
        return;
      }
      expect(meta.kind === LinkCardResourceKind.QUESTION).assertTrue();
      expect(meta.answerCount === 128).assertTrue();
      expect(meta.voteupCount === undefined).assertTrue();
      expect(meta.commentCount === undefined).assertTrue();
    });

    it('decodes pin meta from like_count', 0, (): void => {
      const meta = decodeLinkCardMeta('{"id":4,"like_count":66,"comment_count":12}', DeepLinkType.PIN);
      expect(meta !== undefined).assertTrue();
      if (meta === undefined) {
        return;
      }
      expect(meta.kind === LinkCardResourceKind.PIN).assertTrue();
      expect(meta.voteupCount === 66).assertTrue();
      expect(meta.commentCount === 12).assertTrue();
    });

    it('returns undefined for malformed bodies', 0, (): void => {
      expect(decodeLinkCardMeta('not-json', DeepLinkType.ANSWER) === undefined).assertTrue();
      expect(decodeLinkCardMeta('[1,2]', DeepLinkType.ANSWER) === undefined).assertTrue();
      expect(decodeLinkCardMeta('{}', DeepLinkType.QUESTION) !== undefined).assertTrue();
    });

    it('formats counts like zhihu', 0, (): void => {
      expect(formatLinkCardCount(0) === '0').assertTrue();
      expect(formatLinkCardCount(9999) === '9999').assertTrue();
      expect(formatLinkCardCount(12345) === '1.2 万').assertTrue();
      expect(formatLinkCardCount(210000000) === '2.1 亿').assertTrue();
    });

    it('builds meta lines', 0, (): void => {
      expect(linkCardMetaLine({ kind: LinkCardResourceKind.ANSWER, voteupCount: 123, commentCount: 45 }) ===
        '123 赞同 · 45 评论 · 回答').assertTrue();
      expect(linkCardMetaLine({ kind: LinkCardResourceKind.ARTICLE, voteupCount: 12345 }) ===
        '1.2 万 赞同 · 文章').assertTrue();
      expect(linkCardMetaLine({ kind: LinkCardResourceKind.QUESTION, answerCount: 128 }) ===
        '128 回答 · 问题').assertTrue();
      expect(linkCardMetaLine({ kind: LinkCardResourceKind.PIN, voteupCount: 3, commentCount: 4 }) ===
        '3 赞同 · 4 评论 · 想法').assertTrue();
    });

    it('labels resource kinds', 0, (): void => {
      expect(linkCardKindLabel(LinkCardResourceKind.ANSWER) === '回答').assertTrue();
      expect(linkCardKindLabel(LinkCardResourceKind.ARTICLE) === '文章').assertTrue();
      expect(linkCardKindLabel(LinkCardResourceKind.QUESTION) === '问题').assertTrue();
      expect(linkCardKindLabel(LinkCardResourceKind.PIN) === '想法').assertTrue();
    });

    it('fetches answer meta via minimal include endpoint', 0, async (): Promise<void> => {
      const factory = new MetaTransportFactory(jsonResponse('{"voteup_count":123,"comment_count":45}'));
      const repository = new DefaultLinkCardMetaRepository(
        new ZhihuHttpClient(new MetaSessionProvider(), factory));
      const meta = await repository.getMeta('https://www.zhihu.com/question/4875074049/answer/2083857545970578808');
      expect(meta !== undefined).assertTrue();
      if (meta === undefined) {
        return;
      }
      expect(meta.kind === LinkCardResourceKind.ANSWER).assertTrue();
      expect(meta.voteupCount === 123).assertTrue();
      expect(meta.commentCount === 45).assertTrue();
      expect(factory.transports.length === 1).assertTrue();
      const requests = factory.transports[0].requests;
      expect(requests.length === 1).assertTrue();
      expect(requests[0].url ===
        'https://www.zhihu.com/api/v4/answers/2083857545970578808?include=voteup_count,comment_count')
        .assertTrue();
    });

    it('resolves link.zhihu.com wrappers and question endpoints', 0, async (): Promise<void> => {
      const factory = new MetaTransportFactory(jsonResponse('{"answer_count":42}'));
      const repository = new DefaultLinkCardMetaRepository(
        new ZhihuHttpClient(new MetaSessionProvider(), factory));
      const meta = await repository.getMeta('https://link.zhihu.com/?target=https%3A%2F%2Fwww.zhihu.com%2Fquestion%2F4875074049');
      expect(meta !== undefined).assertTrue();
      if (meta === undefined) {
        return;
      }
      expect(meta.kind === LinkCardResourceKind.QUESTION).assertTrue();
      expect(meta.answerCount === 42).assertTrue();
      const requests = factory.transports[0].requests;
      expect(requests.length === 1).assertTrue();
      expect(requests[0].url === 'https://www.zhihu.com/api/v4/questions/4875074049?include=answer_count')
        .assertTrue();
    });

    it('skips external links', 0, async (): Promise<void> => {
      const factory = new MetaTransportFactory(jsonResponse('{}'));
      const repository = new DefaultLinkCardMetaRepository(
        new ZhihuHttpClient(new MetaSessionProvider(), factory));
      const meta = await repository.getMeta('https://example.com/some/page');
      expect(meta === undefined).assertTrue();
      expect(factory.transports.length === 0).assertTrue();
    });
  });
}
