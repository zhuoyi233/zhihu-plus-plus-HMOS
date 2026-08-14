import { describe, expect, it } from '@ohos/hypium';
import {
  buildChildCommentsUrl,
  buildCommentLikeBody,
  buildCommentLikeUrl,
  buildDeleteCommentUrl,
  buildRootCommentsUrl,
  buildSubmitCommentBody,
  buildSubmitCommentUrl,
  CommentContentKind,
  CommentRepositoryFailure,
  CommentRepositoryFailureKind,
  CommentSortOrder,
  decodeChildCommentPage,
  decodeCommentResponse,
  decodeRootCommentPage,
  DefaultCommentRepository,
  DomainDecodeError,
  DomainDecodeFailureKind,
  escapeCommentHtml,
  isChildCommentsCursorUrl,
  isRootCommentsCursorUrl,
  PreparedZhihuHttpRequest,
  SessionCookie,
  SessionCookieProvider,
  ZhihuHttpClient,
  ZhihuHttpMethod,
  ZhihuHttpResponse,
  ZhihuHttpTransport,
  ZhihuHttpTransportFactory
} from 'data';

class CommentSessionProvider implements SessionCookieProvider {
  getCookies(): Array<SessionCookie> {
    return [
      { name: 'z_c0', value: 'comment-session' },
      { name: 'd_c0', value: 'comment-device' }
    ];
  }
}

class CommentTransport implements ZhihuHttpTransport {
  readonly requests: Array<PreparedZhihuHttpRequest>;
  private readonly response: ZhihuHttpResponse;

  constructor(response: ZhihuHttpResponse, requests: Array<PreparedZhihuHttpRequest>) {
    this.response = response;
    this.requests = requests;
  }

  request(request: PreparedZhihuHttpRequest): Promise<ZhihuHttpResponse> {
    this.requests.push(request);
    return Promise.resolve(this.response);
  }

  destroy(): void {
  }
}

class CommentTransportFactory implements ZhihuHttpTransportFactory {
  private readonly responses: Array<ZhihuHttpResponse>;
  private index: number = 0;
  readonly requests: Array<PreparedZhihuHttpRequest> = [];

  constructor(responses: Array<ZhihuHttpResponse>) {
    this.responses = responses;
  }

  create(): ZhihuHttpTransport {
    const response = this.responses[this.index];
    this.index += 1;
    return new CommentTransport(response, this.requests);
  }
}

class PendingCommentTransport implements ZhihuHttpTransport {
  destroyed: boolean = false;

  request(_request: PreparedZhihuHttpRequest): Promise<ZhihuHttpResponse> {
    return new Promise<ZhihuHttpResponse>((_resolve, _reject) => {
    });
  }

  destroy(): void {
    this.destroyed = true;
  }
}

class PendingCommentTransportFactory implements ZhihuHttpTransportFactory {
  readonly transport: PendingCommentTransport = new PendingCommentTransport();

  create(): ZhihuHttpTransport {
    return this.transport;
  }
}

export default function commentRepositoryTest(): void {
  describe('commentRepositoryTest', () => {
    it('buildsCanonicalCommentUrlsAndRejectsInvalidInputs', 0, () => {
      expect(buildRootCommentsUrl('answer', '456')).assertEqual(
        'https://www.zhihu.com/api/v4/comment_v5/answers/456/root_comment?order_by=score'
      );
      expect(buildRootCommentsUrl('article', '789', CommentSortOrder.TIME)).assertEqual(
        'https://www.zhihu.com/api/v4/comment_v5/articles/789/root_comment?order_by=ts'
      );
      expect(buildRootCommentsUrl('question', '123')).assertEqual(
        'https://www.zhihu.com/api/v4/comment_v5/questions/123/root_comment?order_by=score'
      );
      expect(buildRootCommentsUrl('pin', '456')).assertEqual(
        'https://www.zhihu.com/api/v4/comment_v5/pins/456/root_comment?order_by=score'
      );
      expect(buildChildCommentsUrl('1001')).assertEqual(
        'https://www.zhihu.com/api/v4/comment_v5/comment/1001/child_comment'
      );
      expect(buildSubmitCommentUrl('answer', '456')).assertEqual(
        'https://www.zhihu.com/api/v4/comment_v5/answers/456/comment'
      );
      expect(buildDeleteCommentUrl('1001')).assertEqual('https://www.zhihu.com/api/v4/comments/1001');
      expect(buildCommentLikeUrl('1001')).assertEqual('https://www.zhihu.com/api/v4/comments/1001/voters');
      expect(buildCommentLikeBody()).assertEqual('{"type":"up"}');

      expect(escapeCommentHtml('<a href="x">&</a>')).assertEqual(
        '&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;'
      );
      expect(buildSubmitCommentBody({
        contentType: CommentContentKind.ANSWER,
        contentId: '456',
        content: '你好'
      })).assertEqual('{"content":"<p>你好</p>"}');

      const invalidIds: Array<string> = ['', '0', '-1', '01', '1/2', '1?include=secret', 'abc'];
      invalidIds.forEach((id: string): void => {
        let failure: CommentRepositoryFailure | undefined = undefined;
        try {
          buildDeleteCommentUrl(id);
        } catch (error) {
          if (error instanceof CommentRepositoryFailure) {
            failure = error;
          }
        }
        expect(failure?.kind).assertEqual(CommentRepositoryFailureKind.INVALID_IDENTIFIER);
      });

      const invalidTypes: Array<string> = ['zvideo', 'column', ''];
      invalidTypes.forEach((type: string): void => {
        let failure: CommentRepositoryFailure | undefined = undefined;
        try {
          buildRootCommentsUrl(type, '1');
        } catch (error) {
          if (error instanceof CommentRepositoryFailure) {
            failure = error;
          }
        }
        expect(failure?.kind).assertEqual(CommentRepositoryFailureKind.INVALID_IDENTIFIER);
      });

      let blankFailure: CommentRepositoryFailure | undefined = undefined;
      try {
        buildSubmitCommentBody({
          contentType: CommentContentKind.ANSWER,
          contentId: '456',
          content: '   '
        });
      } catch (error) {
        if (error instanceof CommentRepositoryFailure) {
          blankFailure = error;
        }
      }
      expect(blankFailure?.kind).assertEqual(CommentRepositoryFailureKind.INVALID_CONTENT);
    });

    it('validatesRootCommentCursorsAgainstTheirSourcePrefix', 0, () => {
      const validCursor =
        'https://www.zhihu.com/api/v4/comment_v5/answers/456/root_comment?order_by=score&limit=20&offset=20';
      expect(isRootCommentsCursorUrl('answer', '456', validCursor)).assertTrue();
      expect(isRootCommentsCursorUrl('article', '456', validCursor)).assertFalse();
      expect(isRootCommentsCursorUrl('answer', '457', validCursor)).assertFalse();
      expect(isRootCommentsCursorUrl('answer', '456',
        'https://www.zhihu.com/api/v4/comment_v5/answers/456/child_comment?limit=20')).assertFalse();
      expect(isRootCommentsCursorUrl('answer', '456', 'https://www.zhihu.com/evil')).assertFalse();
      expect(isRootCommentsCursorUrl('answer', '456',
        'https://www.zhihu.com/api/v4/comment_v5/answers/456/root_comment?x#frag')).assertFalse();
      expect(isRootCommentsCursorUrl('answer', '456', 'not-a-url')).assertFalse();
      expect(isRootCommentsCursorUrl('answer', '456', '')).assertFalse();

      let failure: CommentRepositoryFailure | undefined = undefined;
      try {
        buildRootCommentsUrl('answer', '456', CommentSortOrder.SCORE, 'https://www.zhihu.com/evil');
      } catch (error) {
        if (error instanceof CommentRepositoryFailure) {
          failure = error;
        }
      }
      expect(failure?.kind).assertEqual(CommentRepositoryFailureKind.INVALID_CURSOR);
    });

    it('validatesChildCommentCursorsAgainstTheirSourcePrefix', 0, () => {
      const validCursor =
        'https://www.zhihu.com/api/v4/comment_v5/comment/1001/child_comment?limit=20&offset=20';
      expect(isChildCommentsCursorUrl('1001', validCursor)).assertTrue();
      expect(isChildCommentsCursorUrl('1002', validCursor)).assertFalse();
      expect(isChildCommentsCursorUrl('1001',
        'https://www.zhihu.com/api/v4/comment_v5/answers/456/root_comment?x')).assertFalse();
      expect(isChildCommentsCursorUrl('1001',
        'https://www.zhihu.com/api/v4/comment_v5/comment/1001/child_comment?x#frag')).assertFalse();
      expect(isChildCommentsCursorUrl('1001', '')).assertFalse();

      let failure: CommentRepositoryFailure | undefined = undefined;
      try {
        buildChildCommentsUrl('1001', 'https://www.zhihu.com/evil');
      } catch (error) {
        if (error instanceof CommentRepositoryFailure) {
          failure = error;
        }
      }
      expect(failure?.kind).assertEqual(CommentRepositoryFailureKind.INVALID_CURSOR);
    });

    it('loadsRootCommentsPageWithSessionAndZseAndDeduplicates', 0, async () => {
      const factory = new CommentTransportFactory([{ statusCode: 200, body: ROOT_PAGE_JSON }]);
      const repository = new DefaultCommentRepository(
        new ZhihuHttpClient(new CommentSessionProvider(), factory)
      );
      const page = await repository.getRootCommentsPage('answer', '456');

      expect(factory.requests.length).assertEqual(1);
      const request = factory.requests[0];
      expect(request.url.startsWith(
        'https://www.zhihu.com/api/v4/comment_v5/answers/456/root_comment?order_by=score'
      )).assertTrue();
      expect(request.method).assertEqual(ZhihuHttpMethod.GET);
      expect(request.maxRedirects).assertEqual(0);
      expect(request.headers.Cookie?.includes('comment-session')).assertTrue();
      expect(JSON.stringify(request.headers).includes('"x-zse-96":"2.0_')).assertTrue();

      expect(page.items.length).assertEqual(2);
      expect(page.items[0].id).assertEqual('1001');
      expect(page.items[0].contentHtml).assertEqual('<p>测试评论一</p>');
      expect(page.items[0].liked).assertTrue();
      expect(page.items[0].likeCount).assertEqual(5);
      expect(page.items[0].isAuthor).assertTrue();
      expect(page.items[0].childCommentCount).assertEqual(2);
      expect(page.items[0].childComments.length).assertEqual(1);
      expect(page.items[0].childComments[0].id).assertEqual('2001');
      expect(page.items[0].childComments[0].replyToAuthor?.name).assertEqual('张三');
      expect(page.items[0].authorTag).assertEqual('作者');
      expect(page.items[0].commentTags.length).assertEqual(1);
      expect(page.items[0].commentTags[0].text).assertEqual('北京');
      expect(page.items[1].id).assertEqual('1002');
      expect(page.items[1].collapsed).assertTrue();
      expect(page.cursor.isEnd).assertFalse();
      expect(page.cursor.next).assertEqual(
        'https://www.zhihu.com/api/v4/comment_v5/answers/456/root_comment?order_by=score&limit=20&offset=20'
      );
    });

    it('decodesChildCommentPageWithPagination', 0, () => {
      const page = decodeChildCommentPage(CHILD_PAGE_JSON);
      expect(page.items.length).assertEqual(1);
      expect(page.items[0].id).assertEqual('3001');
      expect(page.items[0].likeCount).assertEqual(2);
      expect(page.cursor.isEnd).assertTrue();
      expect(page.cursor.next).assertUndefined();
    });

    it('decodesAuthorIdAsHexLikeUpstreamPeopleId', 0, () => {
      const page = decodeRootCommentPage(
        '{"data":[{"id":"1001","content":"<p>hex 作者</p>","created_time":1700000000,' +
        '"is_delete":false,"collapsed":false,"reviewing":false,"liked":false,"like_count":0,' +
        '"is_author":false,"is_author_top":false,"author":{"id":"7984d572517b489e42f418a63eae0b09",' +
        '"url_token":"dan-guo-feng-97","name":"快乐奔跑","avatar_url":"","headline":""},' +
        '"author_tag":[],"comment_tag":[],"child_comment_count":0,"child_comments":[]}],' +
        '"paging":{"is_end":true,"next":null,"previous":""}}'
      );
      expect(page.items.length).assertEqual(1);
      expect(page.items[0].author.id).assertEqual('7984d572517b489e42f418a63eae0b09');
      expect(page.items[0].author.urlToken).assertEqual('dan-guo-feng-97');
      expect(page.items[0].author.name).assertEqual('快乐奔跑');
    });

    it('rejectsUpstreamErrorAndInvalidRootStructure', 0, () => {
      let upstreamError: DomainDecodeError | undefined = undefined;
      try {
        decodeRootCommentPage('{"error":{"message":"denied"}}');
      } catch (error) {
        if (error instanceof DomainDecodeError) {
          upstreamError = error;
        }
      }
      expect(upstreamError?.kind).assertEqual(DomainDecodeFailureKind.UPSTREAM_ERROR);

      let missingData: DomainDecodeError | undefined = undefined;
      try {
        decodeRootCommentPage('{"data":{}}');
      } catch (error) {
        if (error instanceof DomainDecodeError) {
          missingData = error;
        }
      }
      expect(missingData?.kind).assertEqual(DomainDecodeFailureKind.MISSING_FIELD);

      let invalidJson: DomainDecodeError | undefined = undefined;
      try {
        decodeRootCommentPage('not-json');
      } catch (error) {
        if (error instanceof DomainDecodeError) {
          invalidJson = error;
        }
      }
      expect(invalidJson?.kind).assertEqual(DomainDecodeFailureKind.INVALID_JSON);
    });

    it('submitsCommentWithEscapedJsonBodyAndParsesCreated', 0, async () => {
      const factory = new CommentTransportFactory([{ statusCode: 200, body: SUBMIT_RESPONSE_JSON }]);
      const repository = new DefaultCommentRepository(
        new ZhihuHttpClient(new CommentSessionProvider(), factory)
      );
      const created = await repository.submitComment({
        contentType: CommentContentKind.ANSWER,
        contentId: '456',
        content: '你好 <b>世界</b>',
        replyToCommentId: '1001'
      });

      expect(factory.requests.length).assertEqual(1);
      const request = factory.requests[0];
      expect(request.url).assertEqual('https://www.zhihu.com/api/v4/comment_v5/answers/456/comment');
      expect(request.method).assertEqual(ZhihuHttpMethod.POST);
      expect(request.body).assertEqual('{"content":"<p>你好 &lt;b&gt;世界&lt;/b&gt;</p>","reply_comment_id":"1001"}');
      expect(JSON.stringify(request.headers).includes('"Content-Type":"application/json"')).assertTrue();
      expect(JSON.stringify(request.headers).includes('"x-zse-96":"2.0_')).assertTrue();

      expect(created.id).assertEqual('5001');
      expect(created.isAuthor).assertTrue();
      expect(created.contentHtml).assertEqual('<p>你好 &lt;b&gt;世界&lt;/b&gt;</p>');

      const decoded = decodeCommentResponse(SUBMIT_RESPONSE_JSON);
      expect(decoded.id).assertEqual('5001');
    });

    it('rejectsBlankCommentBeforeAnyNetworkCall', 0, async () => {
      const factory = new CommentTransportFactory([{ statusCode: 200, body: SUBMIT_RESPONSE_JSON }]);
      const repository = new DefaultCommentRepository(
        new ZhihuHttpClient(new CommentSessionProvider(), factory)
      );
      let failure: CommentRepositoryFailure | undefined = undefined;
      try {
        await repository.submitComment({
          contentType: CommentContentKind.ANSWER,
          contentId: '456',
          content: '   '
        });
      } catch (error) {
        if (error instanceof CommentRepositoryFailure) {
          failure = error;
        }
      }
      expect(failure?.kind).assertEqual(CommentRepositoryFailureKind.INVALID_CONTENT);
      expect(factory.requests.length).assertEqual(0);
    });

    it('deletesCommentWithSignedDelete', 0, async () => {
      const factory = new CommentTransportFactory([{ statusCode: 200, body: '{}' }]);
      const repository = new DefaultCommentRepository(
        new ZhihuHttpClient(new CommentSessionProvider(), factory)
      );
      await repository.deleteComment('1001');

      expect(factory.requests.length).assertEqual(1);
      const request = factory.requests[0];
      expect(request.url).assertEqual('https://www.zhihu.com/api/v4/comments/1001');
      expect(request.method).assertEqual(ZhihuHttpMethod.DELETE);
      expect(JSON.stringify(request.headers).includes('"x-zse-96":"2.0_')).assertTrue();
    });

    it('togglesCommentLikeWithVotersPostAndDelete', 0, async () => {
      const factory = new CommentTransportFactory([
        { statusCode: 200, body: '{}' },
        { statusCode: 200, body: '{}' }
      ]);
      const repository = new DefaultCommentRepository(
        new ZhihuHttpClient(new CommentSessionProvider(), factory)
      );
      await repository.likeComment('1001', true);
      await repository.likeComment('1001', false);

      expect(factory.requests.length).assertEqual(2);
      const like = factory.requests[0];
      expect(like.url).assertEqual('https://www.zhihu.com/api/v4/comments/1001/voters');
      expect(like.method).assertEqual(ZhihuHttpMethod.POST);
      expect(like.body).assertEqual('{"type":"up"}');
      expect(JSON.stringify(like.headers).includes('"x-zse-96":"2.0_')).assertTrue();

      const unlike = factory.requests[1];
      expect(unlike.url).assertEqual('https://www.zhihu.com/api/v4/comments/1001/voters');
      expect(unlike.method).assertEqual(ZhihuHttpMethod.DELETE);
      expect(unlike.body).assertEqual('{"type":"up"}');
    });

    it('rejectsRepeatedCursorAndStopsPagination', 0, async () => {
      const factory = new CommentTransportFactory([
        { statusCode: 200, body: ROOT_PAGE_JSON },
        { statusCode: 200, body: ROOT_PAGE_JSON }
      ]);
      const repository = new DefaultCommentRepository(
        new ZhihuHttpClient(new CommentSessionProvider(), factory)
      );
      await repository.getRootCommentsPage('answer', '456');
      const cursor =
        'https://www.zhihu.com/api/v4/comment_v5/answers/456/root_comment?order_by=score&limit=20&offset=20';
      const second = await repository.getRootCommentsPage('answer', '456', CommentSortOrder.SCORE, cursor);
      expect(second.items.length).assertEqual(0);
      expect(factory.requests.length).assertEqual(2);

      let failure: CommentRepositoryFailure | undefined = undefined;
      try {
        await repository.getRootCommentsPage('answer', '456', CommentSortOrder.SCORE, cursor);
      } catch (error) {
        if (error instanceof CommentRepositoryFailure) {
          failure = error;
        }
      }
      expect(failure?.kind).assertEqual(CommentRepositoryFailureKind.REPEATED_CURSOR);
      expect(factory.requests.length).assertEqual(2);
    });

    it('cancelsPendingRequestAndDestroysTransport', 0, async () => {
      const factory = new PendingCommentTransportFactory();
      const repository = new DefaultCommentRepository(
        new ZhihuHttpClient(new CommentSessionProvider(), factory)
      );
      const pending = repository.getRootCommentsPage('answer', '456');
      repository.cancel();
      let cancelled: boolean = false;
      try {
        await pending;
      } catch (_error) {
        cancelled = true;
      }
      expect(cancelled).assertTrue();
      expect(factory.transport.destroyed).assertTrue();
    });
  });
}

const ROOT_PAGE_JSON =
  '{"data":[' +
  '{"id":"1001","type":"comment","resource_type":"answer","url":"","top":false,' +
  '"content":"<p>测试评论一</p>","created_time":1700000000,"is_delete":false,"collapsed":false,"reviewing":false,' +
  '"reply_comment_id":null,"reply_root_comment_id":null,"liked":true,"like_count":5,"disliked":false,' +
  '"dislike_count":0,"is_author":true,"is_author_top":false,"can_collapse":false,"can_share":true,' +
  '"can_unfold":false,"can_truncate":false,"can_more":false,' +
  '"author":{"id":"1","url_token":"alice","name":"张三","avatar_url":"https://pic/1","headline":"测试"},' +
  '"reply_to_author":null,"author_tag":[{"text":"作者"}],"reply_author_tag":[],"content_tag":[],' +
  '"comment_tag":[{"type":"ip_info","text":"北京"}],"child_comment_count":2,"child_comment_next_offset":0,' +
  '"child_comments":[{"id":"2001","content":"<p>子评论一</p>","created_time":1700000100,"is_delete":false,' +
  '"collapsed":false,"reviewing":false,"liked":false,"like_count":1,"is_author":false,"is_author_top":false,' +
  '"author":{"id":"2","url_token":"bob","name":"李四","avatar_url":"","headline":""},' +
  '"reply_to_author":{"id":"1","url_token":"alice","name":"张三","avatar_url":"","headline":""},' +
  '"author_tag":[],"comment_tag":[],"child_comment_count":0,"child_comments":[]}],' +
  '"is_visible_only_to_myself":false},' +
  '{"id":"1002","content":"<p>测试评论二</p>","created_time":1690000000,"is_delete":false,"collapsed":true,' +
  '"reviewing":false,"liked":false,"like_count":0,"is_author":false,"is_author_top":false,' +
  '"author":{"id":"3","url_token":"carol","name":"王五","avatar_url":"","headline":""},' +
  '"author_tag":[],"comment_tag":[],"child_comment_count":0,"child_comments":[]},' +
  '{"id":"1001","content":"<p>重复评论</p>","created_time":1680000000,"is_delete":false,"collapsed":false,' +
  '"reviewing":false,"liked":false,"like_count":0,"is_author":false,"is_author_top":false,' +
  '"author":{"id":"1","url_token":"alice","name":"张三","avatar_url":"","headline":""},' +
  '"author_tag":[],"comment_tag":[],"child_comment_count":0,"child_comments":[]}' +
  '],"paging":{"is_end":false,' +
  '"next":"https://www.zhihu.com/api/v4/comment_v5/answers/456/root_comment?order_by=score&limit=20&offset=20",' +
  '"previous":""}}';

const CHILD_PAGE_JSON =
  '{"data":[' +
  '{"id":"3001","content":"<p>子评论A</p>","created_time":1700000200,"is_delete":false,"collapsed":false,' +
  '"reviewing":false,"liked":false,"like_count":2,"is_author":false,"is_author_top":false,' +
  '"author":{"id":"4","url_token":"dave","name":"赵六","avatar_url":"","headline":""},' +
  '"author_tag":[],"comment_tag":[],"child_comment_count":0,"child_comments":[]}' +
  '],"paging":{"is_end":true,"next":null,"previous":""}}';

const SUBMIT_RESPONSE_JSON =
  '{"id":"5001","content":"<p>你好 &lt;b&gt;世界&lt;/b&gt;</p>","created_time":1700000300,"is_delete":false,' +
  '"collapsed":false,"reviewing":false,"liked":false,"like_count":0,"is_author":true,"is_author_top":false,' +
  '"author":{"id":"9","url_token":"me","name":"我自己","avatar_url":"","headline":""},' +
  '"author_tag":[],"comment_tag":[],"child_comment_count":0,"child_comments":[]}';
