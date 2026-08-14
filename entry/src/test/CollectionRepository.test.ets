import { describe, expect, it } from '@ohos/hypium';
import {
  buildCollectionDetailUrl,
  buildCollectionItemsUrl,
  buildCollectionsPageUrl,
  buildContentCollectionsUrl,
  buildCreateCollectionUrl,
  buildDeleteCollectionUrl,
  buildContentCollectionToggleUrl,
  CollectionContentKind,
  CollectionRepositoryFailure,
  CollectionRepositoryFailureKind,
  decodeCollectionDetail,
  decodeCollectionItemsPage,
  decodeCollectionsPage,
  decodeContentCollections,
  DefaultCollectionRepository,
  isCollectionItemsCursorUrl,
  isCollectionsCursorUrl,
  PreparedZhihuHttpRequest,
  SessionCookie,
  SessionCookieProvider,
  ZhihuHttpClient,
  ZhihuHttpMethod,
  ZhihuHttpResponse,
  ZhihuHttpTransport,
  ZhihuHttpTransportFactory
} from 'data';

class CollectionSessionProvider implements SessionCookieProvider {
  getCookies(): Array<SessionCookie> {
    return [
      { name: 'z_c0', value: 'collection-session' },
      { name: 'd_c0', value: 'collection-device' }
    ];
  }
}

class CollectionTransport implements ZhihuHttpTransport {
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

class CollectionTransportFactory implements ZhihuHttpTransportFactory {
  private readonly responses: Array<ZhihuHttpResponse>;
  private index: number = 0;
  readonly requests: Array<PreparedZhihuHttpRequest> = [];

  constructor(responses: Array<ZhihuHttpResponse>) {
    this.responses = responses;
  }

  create(): ZhihuHttpTransport {
    const response = this.responses[this.index];
    this.index += 1;
    return new CollectionTransport(response, this.requests);
  }
}

class PendingCollectionTransport implements ZhihuHttpTransport {
  destroyed: boolean = false;

  request(_request: PreparedZhihuHttpRequest): Promise<ZhihuHttpResponse> {
    return new Promise<ZhihuHttpResponse>((_resolve, _reject) => {
    });
  }

  destroy(): void {
    this.destroyed = true;
  }
}

class PendingCollectionTransportFactory implements ZhihuHttpTransportFactory {
  readonly transport: PendingCollectionTransport = new PendingCollectionTransport();

  create(): ZhihuHttpTransport {
    return this.transport;
  }
}

export default function collectionRepositoryTest(): void {
  describe('collectionRepositoryTest', () => {
    it('buildsCanonicalCollectionUrlsAndRejectsInvalidInputs', 0, () => {
      expect(buildCollectionsPageUrl('alice-token')).assertEqual(
        'https://www.zhihu.com/api/v4/people/alice-token/collections?limit=20&include=' +
          'data%5B%2A%5D.updated_time%2Canswer_count%2Cfollower_count%2Citem_count%2Clike_count%2Ccomment_count%2Ccreator'
      );
      expect(buildCollectionDetailUrl('123')).assertEqual('https://www.zhihu.com/api/v4/collections/123');
      expect(buildCollectionItemsUrl('123')).assertEqual(
        'https://www.zhihu.com/api/v4/collections/123/items?limit=20&include=' +
          'data%5B%2A%5D.content%2Cexcerpt%2Ccreated_time%2Cupdated_time%2Cauthor'
      );
      expect(buildContentCollectionsUrl('answer', '456')).assertEqual(
        'https://www.zhihu.com/api/v4/collections/contents/answer/456?limit=50'
      );
      expect(buildCreateCollectionUrl()).assertEqual('https://www.zhihu.com/api/v4/collections');
      expect(buildDeleteCollectionUrl('123')).assertEqual('https://www.zhihu.com/api/v4/collections/123');
      expect(buildContentCollectionToggleUrl('article', '789')).assertEqual(
        'https://www.zhihu.com/api/v4/collections/contents/article/789'
      );

      const invalidIds: Array<string> = ['', '0', '-1', '01', '1/2', '1?include=secret', 'abc'];
      invalidIds.forEach((id: string): void => {
        let failure: CollectionRepositoryFailure | undefined = undefined;
        try {
          buildCollectionDetailUrl(id);
        } catch (error) {
          if (error instanceof CollectionRepositoryFailure) {
            failure = error;
          }
        }
        expect(failure?.kind).assertEqual(CollectionRepositoryFailureKind.INVALID_IDENTIFIER);
      });

      const invalidTypes: Array<string> = ['question', 'pin', 'zvideo', ''];
      invalidTypes.forEach((type: string): void => {
        let failure: CollectionRepositoryFailure | undefined = undefined;
        try {
          buildContentCollectionToggleUrl(type, '1');
        } catch (error) {
          if (error instanceof CollectionRepositoryFailure) {
            failure = error;
          }
        }
        expect(failure?.kind).assertEqual(CollectionRepositoryFailureKind.INVALID_IDENTIFIER);
      });
    });

    it('validatesCollectionCursorsAgainstTheirSourcePrefix', 0, () => {
      const validListCursor = 'https://www.zhihu.com/api/v4/people/alice-token/collections?limit=20&include=x';
      expect(isCollectionsCursorUrl('alice-token', validListCursor)).assertTrue();
      expect(isCollectionsCursorUrl('bob-token', validListCursor)).assertFalse();
      expect(isCollectionsCursorUrl('alice-token', 'https://www.zhihu.com/api/v4/collections/1/items?limit=20')).assertFalse();
      expect(isCollectionsCursorUrl('alice-token', 'https://www.zhihu.com/evil')).assertFalse();
      expect(isCollectionsCursorUrl('alice-token', 'https://www.zhihu.com/api/v4/people/alice-token/collections?x#frag')).assertFalse();

      const validItemsCursor = 'https://www.zhihu.com/api/v4/collections/123/items?limit=20&include=y';
      expect(isCollectionItemsCursorUrl('123', validItemsCursor)).assertTrue();
      expect(isCollectionItemsCursorUrl('456', validItemsCursor)).assertFalse();
      expect(isCollectionItemsCursorUrl('123', 'https://www.zhihu.com/api/v4/people/alice/collections?limit=20')).assertFalse();
      expect(isCollectionItemsCursorUrl('123', 'not-a-url')).assertFalse();
    });

    it('loadsCollectionsPageWithSessionAndZseAndDeduplicates', 0, async () => {
      const factory = new CollectionTransportFactory([{ statusCode: 200, body: COLLECTIONS_PAGE_JSON }]);
      const repository = new DefaultCollectionRepository(
        new ZhihuHttpClient(new CollectionSessionProvider(), factory)
      );
      const page = await repository.getCollectionsPage('alice-token');

      expect(factory.requests.length).assertEqual(1);
      const request = factory.requests[0];
      expect(request.url.startsWith('https://www.zhihu.com/api/v4/people/alice-token/collections?')).assertTrue();
      expect(request.method).assertEqual(ZhihuHttpMethod.GET);
      expect(request.maxRedirects).assertEqual(0);
      expect(request.headers.Cookie?.includes('collection-session')).assertTrue();
      expect(JSON.stringify(request.headers).includes('"x-zse-96":"2.0_')).assertTrue();

      expect(page.items.length).assertEqual(2);
      expect(page.items[0].id).assertEqual('100');
      expect(page.items[0].title).assertEqual('我的收藏');
      expect(page.items[0].itemCount).assertEqual(12);
      expect(page.cursor.next).assertEqual(
        'https://www.zhihu.com/api/v4/people/alice-token/collections?limit=20&offset=20&include=x'
      );
      expect(page.cursor.isEnd).assertFalse();
    });

    it('loadsCollectionDetailFromCollectionWrapper', 0, async () => {
      const detail = decodeCollectionDetail(COLLECTION_DETAIL_JSON);
      expect(detail.id).assertEqual('100');
      expect(detail.title).assertEqual('我的收藏');
      expect(detail.isPublic).assertTrue();
      expect(detail.creatorName).assertEqual('张三');
    });

    it('decodesCollectionItemsAndSkipsUnsupportedKinds', 0, () => {
      const page = decodeCollectionItemsPage(COLLECTION_ITEMS_JSON);
      expect(page.items.length).assertEqual(3);
      const answer = page.items.find((item): boolean => item.kind === CollectionContentKind.ANSWER);
      expect(answer?.id).assertEqual('9007199254740993');
      expect(answer?.title).assertEqual('完整问题标题');
      expect(answer?.voteupCount).assertEqual(27);
      expect(answer?.authorName).assertEqual('张三');
      const article = page.items.find((item): boolean => item.kind === CollectionContentKind.ARTICLE);
      expect(article?.title).assertEqual('完整文章标题');
      const pin = page.items.find((item): boolean => item.kind === CollectionContentKind.PIN);
      expect(pin?.title).assertEqual('想法');
    });

    it('decodesContentCollectionsWithFavoritedFlags', 0, () => {
      const collections = decodeContentCollections(CONTENT_COLLECTIONS_JSON);
      expect(collections.length).assertEqual(2);
      expect(collections[0].isFavorited).assertTrue();
      expect(collections[1].isFavorited).assertFalse();
    });

    it('createsCollectionWithJsonBody', 0, async () => {
      const factory = new CollectionTransportFactory([{ statusCode: 200, body: '{}' }]);
      const repository = new DefaultCollectionRepository(
        new ZhihuHttpClient(new CollectionSessionProvider(), factory)
      );
      await repository.createCollection('新收藏夹', '描述', true);

      expect(factory.requests.length).assertEqual(1);
      const request = factory.requests[0];
      expect(request.url).assertEqual('https://www.zhihu.com/api/v4/collections');
      expect(request.method).assertEqual(ZhihuHttpMethod.POST);
      expect(request.body).assertEqual('{"title":"新收藏夹","description":"描述","is_public":true}');
      expect(JSON.stringify(request.headers).includes('"x-zse-96":"2.0_')).assertTrue();
    });

    it('deletesCollectionWithSignedDelete', 0, async () => {
      const factory = new CollectionTransportFactory([{ statusCode: 200, body: '{}' }]);
      const repository = new DefaultCollectionRepository(
        new ZhihuHttpClient(new CollectionSessionProvider(), factory)
      );
      await repository.deleteCollection('100');

      expect(factory.requests.length).assertEqual(1);
      const request = factory.requests[0];
      expect(request.url).assertEqual('https://www.zhihu.com/api/v4/collections/100');
      expect(request.method).assertEqual(ZhihuHttpMethod.DELETE);
      expect(JSON.stringify(request.headers).includes('"x-zse-96":"2.0_')).assertTrue();
    });

    it('togglesContentFavoriteWithFormBodyAndContentType', 0, async () => {
      const factory = new CollectionTransportFactory([
        { statusCode: 200, body: '{}' },
        { statusCode: 200, body: '{}' }
      ]);
      const repository = new DefaultCollectionRepository(
        new ZhihuHttpClient(new CollectionSessionProvider(), factory)
      );
      await repository.addContentToCollection('100', 'answer', '456');
      await repository.removeContentFromCollection('100', 'article', '789');

      expect(factory.requests.length).assertEqual(2);
      const add = factory.requests[0];
      expect(add.url).assertEqual('https://www.zhihu.com/api/v4/collections/contents/answer/456');
      expect(add.method).assertEqual(ZhihuHttpMethod.POST);
      expect(add.body).assertEqual('add_collections=100');
      expect(JSON.stringify(add.headers).includes('"Content-Type":"application/x-www-form-urlencoded"')).assertTrue();
      expect(JSON.stringify(add.headers).includes('"x-zse-96":"2.0_')).assertTrue();

      const remove = factory.requests[1];
      expect(remove.url).assertEqual('https://www.zhihu.com/api/v4/collections/contents/article/789');
      expect(remove.method).assertEqual(ZhihuHttpMethod.DELETE);
      expect(remove.body).assertEqual('remove_collections=100');
      expect(JSON.stringify(remove.headers).includes('"Content-Type":"application/x-www-form-urlencoded"')).assertTrue();
    });

    it('cancelsPendingRequestAndDestroysTransport', 0, async () => {
      const factory = new PendingCollectionTransportFactory();
      const repository = new DefaultCollectionRepository(
        new ZhihuHttpClient(new CollectionSessionProvider(), factory)
      );
      const pending = repository.getCollectionsPage('alice-token');
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

const COLLECTIONS_PAGE_JSON =
  '{"data":[' +
  '{"id":"100","title":"我的收藏","description":"常用内容","is_public":true,' +
  '"answer_count":12,"follower_count":3,"item_count":12,"like_count":5,"comment_count":1,' +
  '"updated_time":1700000000,"creator":{"name":"张三"}},' +
  '{"id":"200","title":"学习资料","description":"","is_public":false,' +
  '"answer_count":4,"follower_count":0,"item_count":4,"like_count":0,"comment_count":0,' +
  '"updated_time":1600000000,"creator":{"name":"张三"}},' +
  '{"id":"100","title":"重复收藏夹","description":"","is_public":true,' +
  '"answer_count":1,"follower_count":0,"item_count":1,"like_count":0,"comment_count":0,' +
  '"updated_time":1500000000,"creator":{"name":"张三"}}' +
  '],"paging":{"is_end":false,' +
  '"next":"https://www.zhihu.com/api/v4/people/alice-token/collections?limit=20&offset=20&include=x",' +
  '"previous":""}}';

const COLLECTION_DETAIL_JSON =
  '{"collection":{"id":"100","title":"我的收藏","description":"常用内容","is_public":true,' +
  '"answer_count":12,"follower_count":3,"item_count":12,"like_count":5,"comment_count":1,' +
  '"updated_time":1700000000,"creator":{"name":"张三"}}}';

const COLLECTION_ITEMS_JSON =
  '{"data":[' +
  '{"created":"2026-01-01T00:00:00.000Z","content":{' +
  '"type":"answer","id":"9007199254740993","question":{"id":"10000000000000001","title":"完整问题标题"},' +
  '"excerpt":"回答摘要","voteup_count":27,"comment_count":3,"author":{"name":"张三"},"created_time":1700000000}},' +
  '{"created":"2026-01-02T00:00:00.000Z","content":{' +
  '"type":"article","id":"30000000000000003","title":"完整文章标题","excerpt":"文章摘要",' +
  '"voteup_count":10,"comment_count":2,"author":{"name":"李四"},"created":1600000000}},' +
  '{"created":"2026-01-03T00:00:00.000Z","content":{' +
  '"type":"pin","id":"40000000000000004","content":"想法正文","like_count":8,"comment_count":1,' +
  '"author":{"name":"王五"},"created":1500000000}},' +
  '{"created":"2026-01-04T00:00:00.000Z","content":{' +
  '"type":"zvideo","id":"50000000000000005","title":"视频","author":{"name":"赵六"}}}' +
  '],"paging":{"is_end":true,"next":null,"previous":""}}';

const CONTENT_COLLECTIONS_JSON =
  '{"data":[' +
  '{"id":"100","title":"我的收藏","description":"","is_public":true,' +
  '"answer_count":12,"follower_count":3,"item_count":12,"like_count":5,"comment_count":1,' +
  '"is_favorited":true,"updated_time":1700000000,"creator":{"name":"张三"}},' +
  '{"id":"200","title":"学习资料","description":"","is_public":false,' +
  '"answer_count":4,"follower_count":0,"item_count":4,"like_count":0,"comment_count":0,' +
  '"is_favorited":false,"updated_time":1600000000,"creator":{"name":"张三"}}' +
  '],"paging":{"is_end":true,"next":null,"previous":""}}';
