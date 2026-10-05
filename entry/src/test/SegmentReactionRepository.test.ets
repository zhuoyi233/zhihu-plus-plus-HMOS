import { describe, expect, it } from '@ohos/hypium';
import {
  DefaultSegmentReactionRepository,
  HttpFailure,
  HttpFailureKind,
  PreparedZhihuHttpRequest,
  SegmentInfoMark,
  SegmentInfoMeta,
  SegmentInfoParagraph,
  SessionCookie,
  SessionCookieProvider,
  ZhihuHttpClient,
  ZhihuHttpMethod,
  ZhihuHttpResponse,
  ZhihuHttpTransport,
  ZhihuHttpTransportFactory
} from 'data';

class SegmentCookieProvider implements SessionCookieProvider {
  getCookies(): Array<SessionCookie> {
    return [
      { name: 'd_c0', value: 'segment-device-cookie' },
      { name: 'z_c0', value: 'segment-session-cookie' }
    ];
  }
}

/** 单次请求脚本：走脚本出结果，或直接抛指定失败（模拟单飞 BUSY 之类的客户端侧拒绝）。 */
interface SegmentScriptedResponse {
  statusCode?: number;
  body?: string;
  failure?: HttpFailureKind;
}

class SegmentReactionTransport implements ZhihuHttpTransport {
  private readonly script: SegmentScriptedResponse;
  private readonly requests: Array<PreparedZhihuHttpRequest>;

  constructor(script: SegmentScriptedResponse, requests: Array<PreparedZhihuHttpRequest>) {
    this.script = script;
    this.requests = requests;
  }

  request(request: PreparedZhihuHttpRequest): Promise<ZhihuHttpResponse> {
    this.requests.push(request);
    if (this.script.failure !== undefined) {
      return Promise.reject(new HttpFailure(this.script.failure));
    }
    const response: ZhihuHttpResponse = {
      statusCode: this.script.statusCode ?? 200,
      body: this.script.body ?? ''
    };
    return Promise.resolve(response);
  }

  destroy(): void {
  }
}

class SegmentReactionTransportFactory implements ZhihuHttpTransportFactory {
  private readonly scripts: Array<SegmentScriptedResponse>;
  private index: number = 0;
  readonly requests: Array<PreparedZhihuHttpRequest> = [];

  constructor(scripts: Array<SegmentScriptedResponse>) {
    this.scripts = scripts;
  }

  create(): ZhihuHttpTransport {
    const script = this.scripts[this.index] ?? {};
    this.index += 1;
    return new SegmentReactionTransport(script, this.requests);
  }
}

/** 已点赞的划线：取消点赞走 DELETE + seg_ids 体。 */
function likedParagraph(): SegmentInfoParagraph {
  const meta: SegmentInfoMeta = {
    segIds: ['seg-1'],
    isLike: true,
    likeCount: 49,
    commentCount: 14,
    myCommentCount: 0,
    isSpan: false
  };
  const mark: SegmentInfoMark = { startIndex: 0, endIndex: 4, segInfo: meta };
  return { pid: 'p1', text: '实名制啊', marks: [mark] };
}

/** 未点赞的划线：点赞走 POST + position 体。 */
function unlikedParagraph(): SegmentInfoParagraph {
  const meta: SegmentInfoMeta = {
    segIds: ['seg-1'],
    isLike: false,
    likeCount: 49,
    commentCount: 14,
    myCommentCount: 0,
    isSpan: false
  };
  const mark: SegmentInfoMark = { startIndex: 0, endIndex: 4, segInfo: meta };
  return { pid: 'p1', text: '实名制啊', marks: [mark] };
}

function createRepository(factory: SegmentReactionTransportFactory): DefaultSegmentReactionRepository {
  // 测试里把重试等待压到 0，避免用例时长依赖真实定时器。
  return new DefaultSegmentReactionRepository(new ZhihuHttpClient(new SegmentCookieProvider(), factory),
    { maxAttempts: 3, delayMs: 0 });
}

export default function segmentReactionRepositoryTest(): void {
  describe('segmentReactionRepositoryTest', () => {
    it('segmentReactionUnlikesWithDeleteAndSegIdsBody', 0, async () => {
      const factory = new SegmentReactionTransportFactory([{ statusCode: 204, body: '' }]);
      const repository = createRepository(factory);

      const result = await repository.toggleSegmentLike('answer', '123', likedParagraph(), 0);

      expect(factory.requests.length).assertEqual(1);
      expect(factory.requests[0].method).assertEqual(ZhihuHttpMethod.DELETE);
      expect(factory.requests[0].url)
        .assertEqual('https://www.zhihu.com/api/v4/reaction/answers/123/segment_reaction');
      expect(factory.requests[0].body).assertEqual('{"seg_ids":"seg-1"}');
      expect(result.isLike).assertFalse();
      expect(result.likeCount).assertEqual(48);
    });

    it('segmentReactionLikesWithPostAndPositionBodyThenParsesPayloadSegIds', 0, async () => {
      const factory = new SegmentReactionTransportFactory([
        { statusCode: 200, body: '{"payload":{"segId":"seg-9,seg-10"}}' }
      ]);
      const repository = createRepository(factory);

      const result = await repository.toggleSegmentLike('article', '456', unlikedParagraph(), 0);

      expect(factory.requests.length).assertEqual(1);
      expect(factory.requests[0].method).assertEqual(ZhihuHttpMethod.POST);
      expect(factory.requests[0].body)
        .assertEqual('{"seg_id":"seg-1","content":"实名制啊","position":{"start":{"paragraph_id":"p1","offset":0},' +
          '"end":{"paragraph_id":"p1","offset":4}}}');
      expect(result.isLike).assertTrue();
      expect(result.likeCount).assertEqual(50);
      expect(result.segIds.length).assertEqual(2);
      expect(result.segIds[0]).assertEqual('seg-9');
    });

    it('segmentReactionRetriesBusySingleFlightRejectionUntilSlotFrees', 0, async () => {
      // 第一次撞上别的请求占着单飞槽位（BUSY 由客户端直接抛出），第二次成功：
      // 用户视角仍然是"点一下就把划线点赞成功"，而不是整个点赞功能失效。
      const factory = new SegmentReactionTransportFactory([
        { failure: HttpFailureKind.BUSY },
        { statusCode: 204, body: '' }
      ]);
      const repository = createRepository(factory);

      const result = await repository.toggleSegmentLike('answer', '123', unlikedParagraph(), 0);

      expect(factory.requests.length).assertEqual(2);
      expect(factory.requests[1].method).assertEqual(ZhihuHttpMethod.POST);
      expect(result.isLike).assertTrue();
      expect(result.likeCount).assertEqual(50);
    });

    it('segmentReactionGivesUpAfterRetryBudgetIsExhausted', 0, async () => {
      const factory = new SegmentReactionTransportFactory([
        { failure: HttpFailureKind.BUSY },
        { failure: HttpFailureKind.BUSY },
        { failure: HttpFailureKind.BUSY }
      ]);
      const repository = createRepository(factory);

      let failure: HttpFailure | undefined = undefined;
      try {
        await repository.toggleSegmentLike('answer', '123', unlikedParagraph(), 0);
      } catch (error) {
        if (error instanceof HttpFailure) {
          failure = error;
        }
      }

      expect(factory.requests.length).assertEqual(3);
      expect(failure?.kind).assertEqual(HttpFailureKind.BUSY);
    });

    it('segmentReactionDoesNotRetryAuthenticationRejections', 0, async () => {
      const factory = new SegmentReactionTransportFactory([
        { failure: HttpFailureKind.AUTHENTICATION },
        { statusCode: 204, body: '' }
      ]);
      const repository = createRepository(factory);

      let failure: HttpFailure | undefined = undefined;
      try {
        await repository.toggleSegmentLike('answer', '123', unlikedParagraph(), 0);
      } catch (error) {
        if (error instanceof HttpFailure) {
          failure = error;
        }
      }

      expect(factory.requests.length).assertEqual(1);
      expect(failure?.kind).assertEqual(HttpFailureKind.AUTHENTICATION);
    });

    it('segmentReactionRetriesServerFailureThenSucceeds', 0, async () => {
      const factory = new SegmentReactionTransportFactory([
        { statusCode: 500, body: '' },
        { statusCode: 204, body: '' }
      ]);
      const repository = createRepository(factory);

      const result = await repository.toggleSegmentLike('answer', '123', likedParagraph(), 0);

      expect(factory.requests.length).assertEqual(2);
      expect(result.isLike).assertFalse();
    });
  });
}
