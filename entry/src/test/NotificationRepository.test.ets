import { describe, expect, it } from '@ohos/hypium';
import {
  buildMobileMessageListUrl,
  buildMobileReadAllUrl,
  buildMobileTimelineListUrl,
  buildPrivateMessageListUrl,
  decodeMobileMessagePage,
  decodeMobileTimelinePage,
  decodePrivateMessagePage,
  decodePrivateMessagePeer,
  decodePrivateMessageReceipt,
  DefaultMobileNotificationRepository,
  encryptZhihuMessageBody,
  isMobileMessageCursorUrl,
  isMobileTimelineCursorUrl,
  isPrivateMessageCursorUrl,
  isValidMobileNotificationEntryName,
  isValidPrivateMessagePeerId,
  MobileNotificationCategory,
  mobileNotificationCategoryInfo,
  mobileNotificationDisplayTitle,
  MobileNotificationRepositoryFailure,
  MobileNotificationRepositoryFailureKind,
  PreparedZhihuHttpRequest,
  SessionCookie,
  SessionCookieProvider,
  shouldShowMobileNotification,
  defaultNotificationPreferences,
  ZhihuMobileHttpClient,
  ZhihuHttpMethod,
  ZhihuHttpResponse,
  ZhihuHttpTransport,
  ZhihuHttpTransportFactory
} from 'data';

class MobileSessionProvider implements SessionCookieProvider {
  getCookies(): Array<SessionCookie> {
    return [
      { name: 'z_c0', value: 'mobile-session' },
      { name: 'd_c0', value: 'mobile-device' }
    ];
  }
}

class RecordingTransport implements ZhihuHttpTransport {
  readonly requests: Array<PreparedZhihuHttpRequest>;

  constructor(requests: Array<PreparedZhihuHttpRequest>, response: ZhihuHttpResponse) {
    this.requests = requests;
    this.response = response;
  }

  private readonly response: ZhihuHttpResponse;

  request(request: PreparedZhihuHttpRequest): Promise<ZhihuHttpResponse> {
    this.requests.push(request);
    return Promise.resolve(this.response);
  }

  destroy(): void {
  }
}

class RecordingTransportFactory implements ZhihuHttpTransportFactory {
  readonly requests: Array<PreparedZhihuHttpRequest> = [];
  private readonly responses: Array<ZhihuHttpResponse>;
  private index: number = 0;

  constructor(responses: Array<ZhihuHttpResponse>) {
    this.responses = responses;
  }

  create(): ZhihuHttpTransport {
    const response = this.responses[Math.min(this.index, this.responses.length - 1)];
    this.index += 1;
    return new RecordingTransport(this.requests, response);
  }
}

class PendingMobileTransport implements ZhihuHttpTransport {
  destroyed: boolean = false;

  request(_request: PreparedZhihuHttpRequest): Promise<ZhihuHttpResponse> {
    return new Promise<ZhihuHttpResponse>((_resolve, _reject) => {
    });
  }

  destroy(): void {
    this.destroyed = true;
  }
}

class PendingMobileTransportFactory implements ZhihuHttpTransportFactory {
  readonly transport: PendingMobileTransport = new PendingMobileTransport();

  create(): ZhihuHttpTransport {
    return this.transport;
  }
}

export default function mobileNotificationRepositoryTest(): void {
  describe('mobileNotificationRepositoryTest', () => {
    it('buildsCanonicalMobileNotificationUrls', 0, () => {
      expect(buildMobileMessageListUrl()).assertEqual(
        'https://api.zhihu.com/notifications/v3/message/v3?limit=20');
      expect(buildMobileTimelineListUrl('comment')).assertEqual(
        'https://api.zhihu.com/notifications/v3/timeline/entry/comment?limit=20');
      expect(buildMobileTimelineListUrl('invite')).assertEqual(
        'https://api.zhihu.com/notifications/v3/timeline/entry/invite?invite_with_time_slice=1&limit=20');
      expect(buildMobileReadAllUrl('favlist_me')).assertEqual(
        'https://api.zhihu.com/notifications/v3/timeline/entry/favlist_me/actions/readall');
      expect(buildPrivateMessageListUrl('peer-id')).assertEqual(
        'https://api.zhihu.com/messages?limit=20&sender_id=peer-id');
      expect(isValidMobileNotificationEntryName('comment')).assertTrue();
      expect(isValidMobileNotificationEntryName('INVITE')).assertFalse();
      expect(isValidMobileNotificationEntryName('')).assertFalse();
      expect(isValidPrivateMessagePeerId('peer_1-x')).assertTrue();
      expect(isValidPrivateMessagePeerId('../evil')).assertFalse();
    });

    it('validatesMobileCursorsAgainstTrustedPrefixes', 0, () => {
      const messageCursor =
        'https://api.zhihu.com/notifications/v3/message/v3?limit=20&after=abc';
      expect(isMobileMessageCursorUrl(messageCursor)).assertTrue();
      expect(isMobileMessageCursorUrl('https://api.zhihu.com/evil?x=1')).assertFalse();
      expect(isMobileMessageCursorUrl('not-a-url')).assertFalse();
      expect(isMobileMessageCursorUrl('')).assertFalse();

      const timelineCursor =
        'https://api.zhihu.com/notifications/v3/timeline/entry/comment?limit=20&after=abc';
      expect(isMobileTimelineCursorUrl('comment', timelineCursor)).assertTrue();
      expect(isMobileTimelineCursorUrl('like', timelineCursor)).assertFalse();
      expect(isMobileTimelineCursorUrl('comment',
        'https://api.zhihu.com/notifications/v3/timeline/entry/comment?x=1#frag')).assertFalse();

      const privateCursor = 'https://api.zhihu.com/messages?limit=20&sender_id=peer-id&after=1';
      expect(isPrivateMessageCursorUrl('peer-id', privateCursor)).assertTrue();
      expect(isPrivateMessageCursorUrl('other-peer', privateCursor)).assertFalse();
      expect(isPrivateMessageCursorUrl('peer-id',
        'https://api.zhihu.com/messages/user/peer-id?sender_id=peer-id')).assertFalse();

      const longCursor = messageCursor + 'x=' + 'a'.repeat(5000);
      expect(isMobileMessageCursorUrl(longCursor)).assertFalse();
    });

    it('normalizesUpstreamHttpCursorToHttps', 0, () => {
      const httpCursor = 'http://api.zhihu.com/notifications/v3/timeline/entry/comment?limit=20&after=abc';
      expect(isMobileTimelineCursorUrl('comment', httpCursor)).assertFalse();
      expect(buildMobileTimelineListUrl('comment', httpCursor)).assertEqual(
        'https://api.zhihu.com/notifications/v3/timeline/entry/comment?limit=20&after=abc');
    });

    it('loadsMessagePageWithMobileHeaders', 0, async () => {
      const factory = new RecordingTransportFactory([{ statusCode: 200, body: MESSAGE_OVERVIEW_JSON }]);
      const repository = new DefaultMobileNotificationRepository(
        new ZhihuMobileHttpClient(new MobileSessionProvider(), factory));
      const page = await repository.getMessagePage();

      expect(factory.requests.length).assertEqual(1);
      const request = factory.requests[0];
      expect(request.url).assertEqual('https://api.zhihu.com/notifications/v3/message/v3?limit=20');
      expect(request.method).assertEqual(ZhihuHttpMethod.GET);
      expect(request.headers.Cookie?.includes('mobile-session')).assertTrue();
      expect(JSON.stringify(request.headers).includes('com.zhihu.android/')).assertTrue();
      expect(JSON.stringify(request.headers).includes('"x-api-version":"3.1.8"')).assertTrue();
      expect(JSON.stringify(request.headers).includes('x-zse-96')).assertFalse();

      expect(page.overview.head.length).assertEqual(2);
      expect(page.overview.columnHead.length).assertEqual(1);
      expect(page.items.length).assertEqual(3);
      expect(page.items[0].uniqueId).assertEqual('c1');
      expect(page.items[0].isRead).assertFalse();
      expect(page.items[0].unreadCount).assertEqual(2);
      expect(page.items[0].content?.title).assertEqual('张三');
      expect(page.cursor.isEnd).assertFalse();
    });

    it('loadsTimelinePageAndSkipsBrokenItems', 0, async () => {
      const factory = new RecordingTransportFactory([{ statusCode: 200, body: TIMELINE_PAGE_JSON }]);
      const repository = new DefaultMobileNotificationRepository(
        new ZhihuMobileHttpClient(new MobileSessionProvider(), factory));
      const page = await repository.getTimelinePage('like');

      expect(page.items.length).assertEqual(2);
      expect(page.items[0].uniqueId).assertEqual('t1');
      expect(page.items[0].head?.author?.name).assertEqual('李四');
      expect(page.items[1].target?.title).assertEqual('如何学习 ArkTS');
      expect(page.cursor.next).assertEqual(undefined);
      expect(page.cursor.isEnd).assertTrue();
    });

    it('marksEntryAsReadWithMobilePost', 0, async () => {
      const factory = new RecordingTransportFactory([{ statusCode: 204, body: '' }]);
      const repository = new DefaultMobileNotificationRepository(
        new ZhihuMobileHttpClient(new MobileSessionProvider(), factory));
      await repository.markEntryAsRead('comment');

      expect(factory.requests.length).assertEqual(1);
      expect(factory.requests[0].url).assertEqual(
        'https://api.zhihu.com/notifications/v3/timeline/entry/comment/actions/readall');
      expect(factory.requests[0].method).assertEqual(ZhihuHttpMethod.POST);
    });

    it('sendsPrivateMessageWithEncryptedFormAndProtocolHeader', 0, async () => {
      const receiptBody =
        '{"id":"sent-1","type":"message","content_type":0,"content":"测试 & 消息",' +
        '"created_time":1785743000,"sender":{"id":"me","name":"我"},' +
        '"receiver":{"id":"peer-id","name":"关注者"}}';
      const factory = new RecordingTransportFactory([{ statusCode: 200, body: receiptBody }]);
      const repository = new DefaultMobileNotificationRepository(
        new ZhihuMobileHttpClient(new MobileSessionProvider(), factory));
      const receipt = await repository.sendPrivateMessage('peer-id', '测试 & 消息');

      expect(factory.requests.length).assertEqual(1);
      const request = factory.requests[0];
      expect(request.url).assertEqual('https://api.zhihu.com/messages');
      expect(request.method).assertEqual(ZhihuHttpMethod.POST);
      expect(JSON.stringify(request.headers).includes('"x-zse-93":"101_1_1.0"')).assertTrue();
      expect(JSON.stringify(request.headers).includes('"Content-Type":"application/x-www-form-urlencoded"')).assertTrue();      const expectedForm = 'receiver_id=peer-id' +
        `&content=${encodeURIComponent('测试 & 消息')}` +
        '&content_type=0&source_type=message_list';
      expect(request.body).assertEqual(encryptZhihuMessageBody(expectedForm));
      expect(receipt.id).assertEqual('sent-1');
      expect(receipt.sender?.name).assertEqual('我');
    });

    it('loadsPrivateMessagePageAndPeer', 0, async () => {
      const factory = new RecordingTransportFactory([
        { statusCode: 200, body: PRIVATE_MESSAGE_PAGE_JSON },
        { statusCode: 200, body: '{"id":"peer-id","name":"关注者","url_token":"peer-token",' +
          '"avatar_url":"https://picx.zhimg.com/a.jpg"}' }
      ]);
      const repository = new DefaultMobileNotificationRepository(
        new ZhihuMobileHttpClient(new MobileSessionProvider(), factory));
      const page = await repository.getPrivateMessagePage('peer-id');
      const peer = await repository.getPrivateMessagePeer('peer-id');

      expect(factory.requests[0].url).assertEqual(
        'https://api.zhihu.com/messages?limit=20&sender_id=peer-id');
      expect(factory.requests[1].url).assertEqual('https://api.zhihu.com/messages/user/peer-id');
      expect(page.items.length).assertEqual(2);
      expect(page.items[0].id).assertEqual('m2');
      expect(page.items[1].id).assertEqual('m1');
      expect(peer.name).assertEqual('关注者');
    });

    it('cancelsPendingMobileRequestAndDestroysTransport', 0, async () => {
      const factory = new PendingMobileTransportFactory();
      const repository = new DefaultMobileNotificationRepository(
        new ZhihuMobileHttpClient(new MobileSessionProvider(), factory));
      const pending = repository.getMessagePage();
      repository.cancel();
      let cancelled = false;
      try {
        await pending;
      } catch (_error) {
        cancelled = true;
      }
      expect(cancelled).assertTrue();
      expect(factory.transport.destroyed).assertTrue();
    });

    it('decodesDisplayHelpersForTimelineItems', 0, () => {
      const page = decodeMobileTimelinePage(TIMELINE_PAGE_JSON);
      const first = page.items[0];
      expect(mobileNotificationDisplayTitle(first)).assertEqual('李四');
      const item = decodeMobileMessagePage(MESSAGE_OVERVIEW_JSON).items[0];
      expect(mobileNotificationDisplayTitle(item)).assertEqual('张三');
      const preferences = defaultNotificationPreferences();
      expect(shouldShowMobileNotification(item, preferences)).assertTrue();
      expect(MobileNotificationCategory.COMMENT).assertEqual('comment');
      expect(mobileNotificationCategoryInfo(MobileNotificationCategory.FAVORITE).detailTitle)
        .assertEqual('收藏了我');
    });

    it('rejectsInvalidEntryAndPeerIdentifiers', 0, () => {
      let failure: MobileNotificationRepositoryFailure | undefined = undefined;
      try {
        buildMobileTimelineListUrl('BAD ENTRY');
      } catch (error) {
        if (error instanceof MobileNotificationRepositoryFailure) {
          failure = error;
        }
      }
      expect(failure?.kind).assertEqual(MobileNotificationRepositoryFailureKind.INVALID_ENTRY);
      failure = undefined;
      try {
        buildPrivateMessageListUrl('not valid');
      } catch (error) {
        if (error instanceof MobileNotificationRepositoryFailure) {
          failure = error;
        }
      }
      expect(failure?.kind).assertEqual(MobileNotificationRepositoryFailureKind.INVALID_PEER);
    });

    it('decodesPrivateMessagePeerAndReceiptStrictly', 0, () => {
      const peer = decodePrivateMessagePeer(
        '{"id":"p1","name":"甲","url_token":"token-a","avatar_url":"https://picx.zhimg.com/x.jpg"}');
      expect(peer.name).assertEqual('甲');
      const receipt = decodePrivateMessageReceipt('{"id":"r1","content":"hi","created_time":1}');
      expect(receipt.content).assertEqual('hi');
      let failed = false;
      try {
        decodePrivateMessagePage('not-json');
      } catch (_error) {
        failed = true;
      }
      expect(failed).assertTrue();
    });
  });
}

const MESSAGE_OVERVIEW_JSON =
  '{"head":[' +
  '{"detail_title":"评论转发@","unread_count":1},' +
  '{"detail_title":"赞同喜欢","unread_count":3}],' +
  '"column_head":[{"id":"col1","title":"邀请回答","text_prefix":"text_prefix","text":" 有人邀请你回答",' +
  '"target_link":"https://www.zhihu.com/notifications/v3/timeline/entry/invite?title=邀请回答",' +
  '"unread_count":2,"created":1760000000}],' +
  '"data":[' +
  '{"id":"c1","unique_id":"c1","type":"message","card_type":"chat","detail_title":"消息",' +
  '"is_read":false,"unread_count":2,"created":1760000000,"created_str":"2025-10-09",' +
  '"head":{"avatar_url":"https://picx.zhimg.com/a.jpg","target_link":"https://www.zhihu.com/inbox/c1?title=张三"},' +
  '"content":{"title":"张三","text":"你好呀","target_link":"https://www.zhihu.com/inbox/c1?title=张三"}},' +
  '{"id":"c2","unique_id":"c2","type":"empty","empty_info":{"text":"没有更多了","number":0}},' +
  '{"id":"c3","unique_id":"c3","type":"message","card_type":"chat","detail_title":"消息",' +
  '"is_read":true,"unread_count":0,"created":1750000000,' +
  '"content":{"title":"李四","text":"早点休息"}}],' +
  '"paging":{"is_end":false,"next":"https://api.zhihu.com/notifications/v3/message/v3?limit=20&after=abc"}}';

const TIMELINE_PAGE_JSON =
  '{"data":[' +
      '{"id":"t1","unique_id":"t1","type":"notification","detail_title":"赞同喜欢",' +
      '"is_read":false,"unread_count":1,"created":1760000000,' +
      '"head":{"author":{"id":"1001","name":"李四","url_token":"lisi","avatar_url":"https://pic1.zhimg.com/b.jpg"},' +
      '"labels":[{"text":"答主"}]},' +
      '"content":{"title":"李四","sub_title":"赞同了你的回答","text":"<a href=\\"https://www.zhihu.com/question/1/answer/2\\">查看</a>",' +
      '"target_link":"https://www.zhihu.com/question/1/answer/2"}},' +
      '{"id":"","unique_id":"","type":"notification","is_read":true},' +
  '{"id":"t2","unique_id":"t2","type":"notification","detail_title":"赞同喜欢",' +
  '"is_read":true,"created":1750000000,' +
  '"target":{"id":"1","type":"question","title":"如何学习 ArkTS","url":"https://www.zhihu.com/question/1"},' +
  '"target_source":{"text":"问题：如何学习 ArkTS","sub_text":"3 个回答"}}],' +
  '"paging":{"is_end":true,"next":null}}';

const PRIVATE_MESSAGE_PAGE_JSON =
  '{"data":[' +
  '{"id":"m2","type":"message","content_type":0,"content":"第二条","created_time":1760001000,' +
  '"sender":{"id":"peer-id","name":"关注者","url_token":"peer-token","avatar_url":"https://picx.zhimg.com/p.jpg"}},' +
  '{"id":"m1","type":"message","content_type":0,"content":"第一条","created_time":1760000000,' +
  '"sender":{"id":"peer-id","name":"关注者"}}],' +
  '"paging":{"is_end":true,"next":null}}';
