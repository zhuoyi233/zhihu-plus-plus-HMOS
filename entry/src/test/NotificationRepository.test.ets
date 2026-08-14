import { describe, expect, it } from '@ohos/hypium';
import {
  buildNotificationListUrl,
  buildNotificationReadAllUrls,
  buildNotificationUnreadUrl,
  decodeNotificationPage,
  decodeUnreadCounts,
  DefaultNotificationRepository,
  isNotificationCursorUrl,
  NotificationCategory,
  NotificationRepositoryFailure,
  NotificationRepositoryFailureKind,
  PreparedZhihuHttpRequest,
  SessionCookie,
  SessionCookieProvider,
  ZhihuHttpClient,
  ZhihuHttpMethod,
  ZhihuHttpResponse,
  ZhihuHttpTransport,
  ZhihuHttpTransportFactory
} from 'data';

class NotificationSessionProvider implements SessionCookieProvider {
  getCookies(): Array<SessionCookie> {
    return [
      { name: 'z_c0', value: 'notification-session' },
      { name: 'd_c0', value: 'notification-device' }
    ];
  }
}

class NotificationTransport implements ZhihuHttpTransport {
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

class NotificationTransportFactory implements ZhihuHttpTransportFactory {
  private readonly responses: Array<ZhihuHttpResponse>;
  private index: number = 0;
  readonly requests: Array<PreparedZhihuHttpRequest> = [];

  constructor(responses: Array<ZhihuHttpResponse>) {
    this.responses = responses;
  }

  create(): ZhihuHttpTransport {
    const response = this.responses[this.index];
    this.index += 1;
    return new NotificationTransport(response, this.requests);
  }
}

class PendingNotificationTransport implements ZhihuHttpTransport {
  destroyed: boolean = false;

  request(_request: PreparedZhihuHttpRequest): Promise<ZhihuHttpResponse> {
    return new Promise<ZhihuHttpResponse>((_resolve, _reject) => {
    });
  }

  destroy(): void {
    this.destroyed = true;
  }
}

class PendingNotificationTransportFactory implements ZhihuHttpTransportFactory {
  readonly transport: PendingNotificationTransport = new PendingNotificationTransport();

  create(): ZhihuHttpTransport {
    return this.transport;
  }
}

export default function notificationRepositoryTest(): void {
  describe('notificationRepositoryTest', () => {
    it('buildsCanonicalNotificationUrlsAndRejectsInvalidInput', 0, () => {
      expect(buildNotificationListUrl(NotificationCategory.DEFAULT)).assertEqual(
        'https://www.zhihu.com/api/v4/notifications/v2/default?limit=20'
      );
      expect(buildNotificationListUrl(NotificationCategory.FOLLOW)).assertEqual(
        'https://www.zhihu.com/api/v4/notifications/v2/follow?limit=20'
      );
      expect(buildNotificationListUrl(NotificationCategory.VOTE_THANK)).assertEqual(
        'https://www.zhihu.com/api/v4/notifications/v2/vote_thank?limit=20'
      );
      expect(buildNotificationUnreadUrl()).assertEqual(
        'https://www.zhihu.com/api/v4/me?include=default_notifications_count%2C' +
        'follow_notifications_count%2Cvote_thank_notifications_count'
      );
      expect(buildNotificationReadAllUrls()).assertDeepEquals([
        'https://www.zhihu.com/api/v4/notifications/v2/default/actions/readall',
        'https://www.zhihu.com/api/v4/notifications/v2/follow/actions/readall',
        'https://www.zhihu.com/api/v4/notifications/v2/vote_thank/actions/readall'
      ]);
    });

    it('validatesNotificationCursorsAgainstTheirCategoryPrefix', 0, () => {
      const validDefault = 'https://www.zhihu.com/api/v4/notifications/v2/default?limit=20&offset=20';
      expect(isNotificationCursorUrl(NotificationCategory.DEFAULT, validDefault)).assertTrue();
      expect(isNotificationCursorUrl(NotificationCategory.FOLLOW, validDefault)).assertFalse();
      expect(isNotificationCursorUrl(NotificationCategory.VOTE_THANK, validDefault)).assertFalse();
      expect(isNotificationCursorUrl(NotificationCategory.DEFAULT,
        'https://www.zhihu.com/api/v4/notifications/v2/follow?limit=20')).assertFalse();
      expect(isNotificationCursorUrl(NotificationCategory.DEFAULT,
        'https://www.zhihu.com/evil')).assertFalse();
      expect(isNotificationCursorUrl(NotificationCategory.DEFAULT,
        'https://www.zhihu.com/api/v4/notifications/v2/default?limit=20#frag')).assertFalse();
      expect(isNotificationCursorUrl(NotificationCategory.DEFAULT, 'not-a-url')).assertFalse();
      expect(isNotificationCursorUrl(NotificationCategory.DEFAULT, '')).assertFalse();

      const longCursor = 'https://www.zhihu.com/api/v4/notifications/v2/default?x=' + 'a'.repeat(5000);
      expect(isNotificationCursorUrl(NotificationCategory.DEFAULT, longCursor)).assertFalse();
    });

    it('loadsNotificationPageWithSessionAndZseAndDeduplicates', 0, async () => {
      const factory = new NotificationTransportFactory([{ statusCode: 200, body: NOTIFICATION_PAGE_JSON }]);
      const repository = new DefaultNotificationRepository(
        new ZhihuHttpClient(new NotificationSessionProvider(), factory)
      );
      const page = await repository.getNotificationsPage(NotificationCategory.DEFAULT);

      expect(factory.requests.length).assertEqual(1);
      const request = factory.requests[0];
      expect(request.url).assertEqual('https://www.zhihu.com/api/v4/notifications/v2/default?limit=20');
      expect(request.method).assertEqual(ZhihuHttpMethod.GET);
      expect(request.maxRedirects).assertEqual(0);
      expect(request.headers.Cookie?.includes('notification-session')).assertTrue();
      expect(JSON.stringify(request.headers).includes('"x-zse-96":"2.0_')).assertTrue();

      expect(page.items.length).assertEqual(2);
      expect(page.items[0].id).assertEqual('n1');
      expect(page.items[0].category).assertEqual(NotificationCategory.DEFAULT);
      expect(page.items[0].isRead).assertFalse();
      expect(page.items[0].mergeCount).assertEqual(3);
      expect(page.items[0].verb).assertEqual(' 邀请你回答问题');
      expect(page.items[0].target?.kind).assertEqual('question');
      expect(page.items[0].target?.id).assertEqual('123');
      expect(page.cursor.next).assertEqual(
        'https://www.zhihu.com/api/v4/notifications/v2/default?limit=20&offset=20'
      );
      expect(page.cursor.isEnd).assertFalse();
    });

    it('deduplicatesIdenticalNotificationsAcrossPages', 0, async () => {
      const factory = new NotificationTransportFactory([
        { statusCode: 200, body: NOTIFICATION_PAGE_JSON },
        { statusCode: 200, body: NOTIFICATION_PAGE_SECOND_JSON }
      ]);
      const repository = new DefaultNotificationRepository(
        new ZhihuHttpClient(new NotificationSessionProvider(), factory)
      );
      const first = await repository.getNotificationsPage(NotificationCategory.DEFAULT);
      expect(first.items.length).assertEqual(2);
      const second = await repository.getNotificationsPage(
        NotificationCategory.DEFAULT,
        'https://www.zhihu.com/api/v4/notifications/v2/default?limit=20&offset=20'
      );
      expect(second.items.length).assertEqual(1);
      expect(second.items[0].id).assertEqual('n3');
    });

    it('truncatesCursorLoopIntoTerminalState', 0, async () => {
      const factory = new NotificationTransportFactory([
        { statusCode: 200, body: NOTIFICATION_PAGE_LOOP_JSON },
        { statusCode: 200, body: NOTIFICATION_PAGE_LOOP_JSON }
      ]);
      const repository = new DefaultNotificationRepository(
        new ZhihuHttpClient(new NotificationSessionProvider(), factory)
      );
      const first = await repository.getNotificationsPage(NotificationCategory.DEFAULT);
      expect(first.cursor.isEnd).assertFalse();
      const second = await repository.getNotificationsPage(
        NotificationCategory.DEFAULT,
        'https://www.zhihu.com/api/v4/notifications/v2/default?limit=20&offset=20'
      );
      expect(second.cursor.isEnd).assertTrue();
    });

    it('rejectsRepeatedCursorWithFailure', 0, async () => {
      const factory = new NotificationTransportFactory([
        { statusCode: 200, body: NOTIFICATION_PAGE_LOOP_JSON },
        { statusCode: 200, body: NOTIFICATION_PAGE_LOOP_JSON }
      ]);
      const repository = new DefaultNotificationRepository(
        new ZhihuHttpClient(new NotificationSessionProvider(), factory)
      );
      await repository.getNotificationsPage(NotificationCategory.DEFAULT);
      const cursor = 'https://www.zhihu.com/api/v4/notifications/v2/default?limit=20&offset=20';
      await repository.getNotificationsPage(NotificationCategory.DEFAULT, cursor);
      let failure: NotificationRepositoryFailure | undefined = undefined;
      try {
        await repository.getNotificationsPage(NotificationCategory.DEFAULT, cursor);
      } catch (error) {
        if (error instanceof NotificationRepositoryFailure) {
          failure = error;
        }
      }
      expect(failure?.kind).assertEqual(NotificationRepositoryFailureKind.REPEATED_CURSOR);
      expect(factory.requests.length).assertEqual(2);
    });

    it('decodesUnreadCountsFromSnakeCasePayload', 0, () => {
      const counts = decodeUnreadCounts(UNREAD_COUNTS_JSON);
      expect(counts.defaultCount).assertEqual(1);
      expect(counts.followCount).assertEqual(2);
      expect(counts.voteThankCount).assertEqual(3);
    });

    it('decodesNotificationPageAndSkipsInvalidItems', 0, () => {
      const page = decodeNotificationPage(NOTIFICATION_PAGE_MIXED_JSON, NotificationCategory.FOLLOW);
      expect(page.items.length).assertEqual(2);
      expect(page.items[0].id).assertEqual('ok1');
      expect(page.items[0].category).assertEqual(NotificationCategory.FOLLOW);
      expect(page.items[1].verb).assertEqual('喜欢了你的回答');
    });

    it('marksAllCategoriesReadWithThreeSignedPosts', 0, async () => {
      const factory = new NotificationTransportFactory([
        { statusCode: 200, body: '{}' },
        { statusCode: 200, body: '{}' },
        { statusCode: 200, body: '{}' }
      ]);
      const repository = new DefaultNotificationRepository(
        new ZhihuHttpClient(new NotificationSessionProvider(), factory)
      );
      await repository.markAllAsRead();

      expect(factory.requests.length).assertEqual(3);
      const urls = factory.requests.map((request: PreparedZhihuHttpRequest): string => request.url);
      expect(urls).assertDeepEquals([
        'https://www.zhihu.com/api/v4/notifications/v2/default/actions/readall',
        'https://www.zhihu.com/api/v4/notifications/v2/follow/actions/readall',
        'https://www.zhihu.com/api/v4/notifications/v2/vote_thank/actions/readall'
      ]);
      factory.requests.forEach((request: PreparedZhihuHttpRequest): void => {
        expect(request.method).assertEqual(ZhihuHttpMethod.POST);
        expect(JSON.stringify(request.headers).includes('"x-zse-96":"2.0_')).assertTrue();
        expect(request.headers.Cookie?.includes('notification-session')).assertTrue();
      });
    });

    it('cancelsPendingRequestAndDestroysTransport', 0, async () => {
      const factory = new PendingNotificationTransportFactory();
      const repository = new DefaultNotificationRepository(
        new ZhihuHttpClient(new NotificationSessionProvider(), factory)
      );
      const pending = repository.getNotificationsPage(NotificationCategory.DEFAULT);
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

const NOTIFICATION_PAGE_JSON =
  '{"data":[' +
  '{"id":"n1","type":"notification","is_read":false,"create_time":1760000000,"merge_count":3,' +
  '"content":{"verb":" 邀请你回答问题","actors":[{"name":"邀请者","type":"member",' +
  '"link":"https://www.zhihu.com/people/inviter","url_token":"inviter"}],' +
  '"target":{"text":"如何选择开发工具？","link":"https://www.zhihu.com/question/123"},' +
  '"extend":{"text":"","icon":"https://pic.example/icon.png"}},' +
  '"target":{"type":"question","url":"https://www.zhihu.com/question/123","title":"如何选择开发工具？",' +
  '"id":"123","created":1760000000}},' +
  '{"id":"n2","type":"notification","is_read":true,"create_time":1750000000,"merge_count":1,' +
  '"content":{"verb":"赞同了你的文章","actors":{"name":"读者","type":"member",' +
  '"link":"https://www.zhihu.com/people/reader","url_token":"reader"},' +
  '"target":{"text":"文章标题","link":"https://zhuanlan.zhihu.com/p/456"},' +
  '"extend":{"text":"","icon":"https://pic.example/icon.png"}},' +
  '"target":{"type":"article","url":"https://zhuanlan.zhihu.com/p/456","title":"文章标题",' +
  '"id":"456","excerpt":"文章摘要"}}' +
  '],"paging":{"is_end":false,' +
  '"next":"https://www.zhihu.com/api/v4/notifications/v2/default?limit=20&offset=20","previous":""}}';

const NOTIFICATION_PAGE_SECOND_JSON =
  '{"data":[' +
  '{"id":"n1","type":"notification","is_read":true,"create_time":1760000000,"merge_count":3,' +
  '"content":{"verb":" 邀请你回答问题","actors":[],"target":{"text":"x","link":"https://www.zhihu.com/question/123"},' +
  '"extend":{"text":""}},' +
  '"target":{"type":"question","url":"https://www.zhihu.com/question/123","title":"如何选择开发工具？",' +
  '"id":"123"}},' +
  '{"id":"n3","type":"notification","is_read":false,"create_time":1740000000,"merge_count":1,' +
  '"content":{"verb":"关注了你的回答","actors":[],"target":{"text":"y","link":"https://www.zhihu.com/answer/789"},' +
  '"extend":{"text":""}},' +
  '"target":{"type":"answer","url":"https://www.zhihu.com/answer/789","title":"回答标题",' +
  '"id":"789"}}' +
  '],"paging":{"is_end":true,"next":null,"previous":""}}';

const NOTIFICATION_PAGE_LOOP_JSON =
  '{"data":[' +
  '{"id":"loop1","type":"notification","is_read":false,"create_time":1760000000,"merge_count":1,' +
  '"content":{"verb":"评论了你的回答","actors":[],"target":{"text":"x","link":"https://www.zhihu.com/answer/1"},' +
  '"extend":{"text":""}},' +
  '"target":{"type":"answer","url":"https://www.zhihu.com/answer/1","title":"回答",' +
  '"id":"1"}}' +
  '],"paging":{"is_end":false,' +
  '"next":"https://www.zhihu.com/api/v4/notifications/v2/default?limit=20&offset=20","previous":""}}';

const NOTIFICATION_PAGE_MIXED_JSON =
  '{"data":[' +
  '{"id":"ok1","type":"notification","is_read":true,"create_time":1760000000,"merge_count":1,' +
  '"content":{"verb":"关注了你的提问","actors":[],"target":{"text":"x","link":"https://www.zhihu.com/question/1"},' +
  '"extend":{"text":""}},' +
  '"target":{"type":"question","url":"https://www.zhihu.com/question/1","title":"问题",' +
  '"id":"1"}},' +
  '{"id":"","type":"notification","is_read":false,"create_time":1760000000,"merge_count":1,' +
  '"content":{"verb":"bad","actors":[],"target":{"text":"x","link":"x"},"extend":{"text":""}}},' +
  '{"id":"ok2","type":"notification","is_read":false,"create_time":1750000000,"merge_count":2,' +
  '"content":{"verb":"喜欢了你的回答","actors":[],"target":{"text":"y","link":"https://www.zhihu.com/answer/2"},' +
  '"extend":{"text":""}},' +
  '"target":{"type":"answer","url":"https://www.zhihu.com/answer/2","title":"回答",' +
  '"id":"2"}}' +
  '],"paging":{"is_end":true,"next":null,"previous":""}}';

const UNREAD_COUNTS_JSON =
  '{"default_notifications_count":1,"follow_notifications_count":2,"vote_thank_notifications_count":3}';
