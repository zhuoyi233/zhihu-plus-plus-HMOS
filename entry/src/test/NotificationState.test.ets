import { describe, expect, it } from '@ohos/hypium';
import {
  HttpFailure,
  HttpFailureKind,
  LoginSessionGateway,
  MobileNotificationAuthor,
  MobileNotificationMessagePage,
  MobileNotificationRepository,
  MobileNotificationTimelineItem,
  MobileNotificationTimelinePage,
  NotificationPreferences,
  defaultNotificationPreferences,
  SessionCookie,
  SessionLoginOperation,
  SessionState,
  SessionStatus,
  ZhihuPrivateMessage,
  ZhihuPrivateMessagePage
} from 'data';
import { NotificationController, NotificationPhase } from '../main/ets/pages/NotificationState';
import { NotificationTimelineController, NotificationTimelinePhase } from '../main/ets/pages/NotificationTimelineState';
import { PrivateMessageController, PrivateMessagePhase } from '../main/ets/pages/PrivateMessageState';

class UnusedLoginOperation implements SessionLoginOperation {
  readonly result: Promise<SessionState>;

  constructor(state: SessionState) {
    this.result = Promise.resolve(state);
  }

  cancel(): void {
  }
}

class FixedSessionGateway implements LoginSessionGateway {
  private readonly state: SessionState;

  constructor(status: SessionStatus) {
    this.state = {
      status: status,
      message: status === SessionStatus.AUTHENTICATED ? '已登录' : '游客模式',
      hasRetainedCredentials: status === SessionStatus.AUTHENTICATED,
      profile: status === SessionStatus.AUTHENTICATED ? {
        id: 'user-1',
        name: '测试用户',
        urlToken: 'alice-token',
        userType: 'people',
        avatarUrl: undefined
      } : undefined
    };
  }

  getState(): SessionState {
    return this.state;
  }

  retryRetainedSession(): Promise<SessionState> {
    return Promise.resolve(this.state);
  }

  beginLoginWithCookieHeader(_rawCookie: string): SessionLoginOperation {
    return new UnusedLoginOperation(this.state);
  }

  beginLoginWithCookies(_cookies: Array<SessionCookie>): SessionLoginOperation {
    return new UnusedLoginOperation(this.state);
  }

  logout(): Promise<SessionState> {
    return Promise.resolve(this.state);
  }
}

class FakeMobileNotificationRepository implements MobileNotificationRepository {
  messagePages: Array<MobileNotificationMessagePage> = [];
  timelinePages: Array<MobileNotificationTimelinePage> = [];
  privateMessagePages: Array<ZhihuPrivateMessagePage> = [];
  peer?: MobileNotificationAuthor = undefined;
  readAllEntries: Array<string> = [];
  sentMessages: Array<string> = [];
  markReadFailure?: HttpFailure = undefined;

  async getMessagePage(_cursor?: string): Promise<MobileNotificationMessagePage> {
    if (this.messagePages.length === 0) {
      throw new HttpFailure(HttpFailureKind.SERVER);
    }
    return this.messagePages.shift() as MobileNotificationMessagePage;
  }

  async getTimelinePage(_entryName: string, _cursor?: string): Promise<MobileNotificationTimelinePage> {
    if (this.timelinePages.length === 0) {
      throw new HttpFailure(HttpFailureKind.SERVER);
    }
    return this.timelinePages.shift() as MobileNotificationTimelinePage;
  }

  async markEntryAsRead(entryName: string): Promise<void> {
    this.readAllEntries.push(entryName);
    if (this.markReadFailure !== undefined) {
      throw this.markReadFailure;
    }
  }

  async getPrivateMessagePage(_peerId: string, _cursor?: string): Promise<ZhihuPrivateMessagePage> {
    if (this.privateMessagePages.length === 0) {
      throw new HttpFailure(HttpFailureKind.SERVER);
    }
    return this.privateMessagePages.shift() as ZhihuPrivateMessagePage;
  }

  async getPrivateMessagePeer(_peerId: string): Promise<MobileNotificationAuthor> {
    if (this.peer === undefined) {
      throw new HttpFailure(HttpFailureKind.SERVER);
    }
    return this.peer;
  }

  async sendPrivateMessage(peerId: string, content: string): Promise<ZhihuPrivateMessage> {
    this.sentMessages.push(`${peerId}:${content}`);
    return {
      id: `sent-${this.sentMessages.length}`,
      type: 'message',
      contentType: 0,
      content: content,
      createdTime: 1760002000,
      pluginExcerpt: '',
      sender: undefined,
      receiver: undefined
    };
  }

  cancel(): void {
  }
}

function preferencesWith(likeAnswerDisplay: boolean): NotificationPreferences {
  const defaults = defaultNotificationPreferences();
  return {
    likeAnswerDisplay: likeAnswerDisplay,
    likeCommentDisplay: defaults.likeCommentDisplay,
    replyCommentDisplay: defaults.replyCommentDisplay,
    inviteAnswerDisplay: defaults.inviteAnswerDisplay,
    autoMarkAsRead: defaults.autoMarkAsRead,
    unreadBadge: defaults.unreadBadge
  };
}

export default function notificationStateTest(): void {
  describe('notificationStateTest', () => {
    it('hubRequiresLoginWithoutAuthenticatedSession', 0, async () => {
      const repository = new FakeMobileNotificationRepository();
      const controller = new NotificationController(repository,
        new FixedSessionGateway(SessionStatus.GUEST));
      controller.activate();
      await controller.loadInitial();
      const state = controller.snapshot();
      expect(state.phase).assertEqual(NotificationPhase.ERROR);
      expect(state.requiresLogin).assertTrue();
    });

    it('hubAppliesOverviewCountsAndFiltersEmptyItems', 0, async () => {
      const repository = new FakeMobileNotificationRepository();
      repository.messagePages.push(makeMessagePage());
      const controller = new NotificationController(repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      const state = controller.snapshot();
      expect(state.phase).assertEqual(NotificationPhase.READY);
      expect(state.items.length).assertEqual(1);
      expect(state.items[0].uniqueId).assertEqual('c1');
      expect(state.categoryUnread.comment).assertEqual(1);
      expect(state.categoryUnread.like).assertEqual(3);
      expect(state.unreadTotal).assertEqual(4);
      expect(state.invitation?.title).assertEqual('邀请回答');
    });

    it('hubMarkAllReadPostsFourCategoriesAndRollsBackOnFailure', 0, async () => {
      const repository = new FakeMobileNotificationRepository();
      repository.messagePages.push(makeMessagePage());
      const controller = new NotificationController(repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();

      repository.markReadFailure = new HttpFailure(HttpFailureKind.AUTHENTICATION, 403);
      const failed = await controller.markAllRead();
      expect(failed).assertFalse();
      expect(repository.readAllEntries.length).assertEqual(1);
      expect(controller.snapshot().unreadTotal).assertEqual(4);
      expect((controller.snapshot().errorMessage ?? '').length).assertLarger(0);

      repository.markReadFailure = undefined;
      const succeeded = await controller.markAllRead();
      expect(succeeded).assertTrue();
      expect(repository.readAllEntries.length).assertEqual(5);
      expect(controller.snapshot().unreadTotal).assertEqual(0);
      expect(controller.snapshot().categoryUnread.comment).assertEqual(0);
      expect(controller.snapshot().categoryUnread.like).assertEqual(0);
    });

    it('timelineFiltersByPreferencesAndAutoMarksRead', 0, async () => {
      const repository = new FakeMobileNotificationRepository();
      repository.timelinePages.push(makeTimelinePage());
      const controller = new NotificationTimelineController('like', repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.setPreferences(preferencesWith(false));
      controller.activate();
      await controller.loadInitial();
      const state = controller.snapshot();
      expect(state.phase).assertEqual(NotificationTimelinePhase.READY);
      expect(state.items.length).assertEqual(1);
      expect(state.items[0].uniqueId).assertEqual('t2');
      expect(repository.readAllEntries.length).assertEqual(0);

      const autoController = new NotificationTimelineController('like', repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      const defaults = defaultNotificationPreferences();
      const autoPreferences: NotificationPreferences = {
        likeAnswerDisplay: defaults.likeAnswerDisplay,
        likeCommentDisplay: defaults.likeCommentDisplay,
        replyCommentDisplay: defaults.replyCommentDisplay,
        inviteAnswerDisplay: defaults.inviteAnswerDisplay,
        autoMarkAsRead: true,
        unreadBadge: defaults.unreadBadge
      };
      autoController.setPreferences(autoPreferences);
      autoController.activate();
      repository.timelinePages.push(makeTimelinePage());
      await autoController.loadInitial();
      expect(repository.readAllEntries).assertContain('like');
    });

    it('privateMessagePrependsOlderPagesOnLoadMore', 0, async () => {
      const repository = new FakeMobileNotificationRepository();
      repository.privateMessagePages.push({
        items: [makeMessage('m2', '较新', 1760002000), makeMessage('m1', '较旧', 1760001000)],
        cursor: { isEnd: false, isStart: false, next: 'cursor-1', previous: undefined, page: 0, total: 0 }
      });
      repository.privateMessagePages.push({
        items: [makeMessage('m0', '最旧', 1760000000)],
        cursor: { isEnd: true, isStart: false, next: undefined, previous: undefined, page: 0, total: 0 }
      });
      const controller = new PrivateMessageController('peer-id', repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      await controller.loadMore();
      const state = controller.snapshot();
      expect(state.items.length).assertEqual(3);
      expect(state.items[0].id).assertEqual('m0');
      expect(state.items[1].id).assertEqual('m1');
      expect(state.items[2].id).assertEqual('m2');
      expect(state.canLoadMore).assertFalse();
    });

    it('privateMessageLoadsChronologicallyAndSendsReceipt', 0, async () => {
      const repository = new FakeMobileNotificationRepository();
      repository.privateMessagePages.push(makePrivateMessagePage());
      repository.peer = {
        id: 'peer-id',
        name: '关注者',
        urlToken: 'peer-token',
        headline: '',
        avatarUrl: 'https://picx.zhimg.com/p.jpg'
      };
      const controller = new PrivateMessageController('peer-id', repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      const state = controller.snapshot();
      expect(state.phase).assertEqual(PrivateMessagePhase.READY);
      expect(state.items.length).assertEqual(2);
      expect(state.items[0].id).assertEqual('m1');
      expect(state.items[1].id).assertEqual('m2');
      expect(state.peer?.name).assertEqual('关注者');

      const sent = await controller.send('你好');
      expect(sent).assertTrue();
      const after = controller.snapshot();
      expect(after.items.length).assertEqual(3);
      expect(after.items[2].content).assertEqual('你好');
      expect(after.sending).assertFalse();
      expect(repository.sentMessages.length).assertEqual(1);
    });
  });
}

function makeTimelinePage(): MobileNotificationTimelinePage {
  return {
    items: [
      makeItem('t1', 'notification', '喜欢了你的回答', false),
      makeItem('t2', 'notification', '关注了你的提问', false)
    ],
    cursor: { isEnd: true, isStart: false, next: undefined, previous: undefined, page: 0, total: 0 }
  };
}

function makeMessagePage(): MobileNotificationMessagePage {
  return {
    overview: {
      head: [
        { detailTitle: '评论转发@', unreadCount: 1 },
        { detailTitle: '赞同喜欢', unreadCount: 3 }
      ],
      columnHead: [
        {
          id: 'col1',
          title: '邀请回答',
          textPrefix: '',
          text: '有人邀请你回答',
          targetLink: 'https://www.zhihu.com/notifications/v3/timeline/entry/invite?title=邀请回答',
          unreadCount: 2,
          created: 1760000000
        }
      ]
    },
    items: [makeItem('c1', 'message', '', false), makeItem('c2', 'empty', '', true)],
    cursor: { isEnd: true, isStart: false, next: undefined, previous: undefined, page: 0, total: 0 }
  };
}

function makePrivateMessagePage(): ZhihuPrivateMessagePage {
  return {
    items: [
      makeMessage('m2', '第二条', 1760001000),
      makeMessage('m1', '第一条', 1760000000)
    ],
    cursor: { isEnd: true, isStart: false, next: undefined, previous: undefined, page: 0, total: 0 }
  };
}

function makeItem(uniqueId: string, type: string, subTitle: string, isRead: boolean):
  MobileNotificationTimelineItem {
  const item: MobileNotificationTimelineItem = {
    id: uniqueId,
    uniqueId: uniqueId,
    type: type,
    cardType: 'chat',
    detailTitle: '消息',
    isRead: isRead,
    unreadCount: isRead ? 0 : 1,
    created: 1760000000,
    createdStr: '',
    head: undefined,
    content: {
      title: '',
      subTitle: subTitle,
      text: '正文',
      subText: '',
      abstractText: '',
      targetLink: '',
      subTargetLink: '',
      subIcon: '',
      isDeleted: false
    },
    targetSource: undefined,
    target: undefined,
    emptyInfo: type === 'empty' ? { text: '没有更多了', number: 0 } : undefined,
    additionalInfo: []
  };
  return item;
}

function makeMessage(id: string, content: string, createdTime: number): ZhihuPrivateMessage {
  const message: ZhihuPrivateMessage = {
    id: id,
    type: 'message',
    contentType: 0,
    content: content,
    createdTime: createdTime,
    pluginExcerpt: '',
    sender: { id: 'peer-id', name: '关注者', urlToken: 'peer-token', headline: '', avatarUrl: '' },
    receiver: undefined
  };
  return message;
}
