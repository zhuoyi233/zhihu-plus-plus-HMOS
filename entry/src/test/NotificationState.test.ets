import { describe, expect, it } from '@ohos/hypium';
import {
  HttpFailure,
  HttpFailureKind,
  LoginSessionGateway,
  NotificationCategory,
  NotificationItem,
  NotificationPage,
  NotificationPreferences,
  NotificationRepository,
  NotificationSettingsGateway,
  NotificationUnreadCounts,
  SessionCookie,
  SessionLoginOperation,
  SessionState,
  SessionStatus
} from 'data';
import {
  mergeNotifications,
  NotificationController,
  NotificationPhase
} from '../main/ets/pages/NotificationState';

class UnusedLoginOperation implements SessionLoginOperation {
  readonly result: Promise<SessionState>;

  constructor(state: SessionState) {
    this.result = Promise.resolve(state);
  }

  cancel(): void {
  }
}

class FixedSessionGateway implements LoginSessionGateway {
  private state: SessionState;

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
    return {
      status: this.state.status,
      message: this.state.message,
      hasRetainedCredentials: this.state.hasRetainedCredentials,
      profile: this.state.profile === undefined ? undefined : {
        id: this.state.profile.id,
        name: this.state.profile.name,
        urlToken: this.state.profile.urlToken,
        userType: this.state.profile.userType,
        avatarUrl: this.state.profile.avatarUrl
      }
    };
  }

  retryRetainedSession(): Promise<SessionState> {
    return Promise.resolve(this.getState());
  }

  beginLoginWithCookieHeader(_rawCookie: string): SessionLoginOperation {
    return new UnusedLoginOperation(this.getState());
  }

  beginLoginWithCookies(_cookies: Array<SessionCookie>): SessionLoginOperation {
    return new UnusedLoginOperation(this.getState());
  }

  logout(): Promise<SessionState> {
    return Promise.resolve(this.getState());
  }
}

interface NotificationListRequest {
  category: NotificationCategory;
  cursor?: string;
}

class ControlledNotificationRepository implements NotificationRepository {
  readonly listRequests: Array<NotificationListRequest> = [];
  readAllCalls: number = 0;
  failList: boolean = false;
  failUnread: boolean = false;
  failReadAll: boolean = false;
  unreadCountsRequested: number = 0;
  cancelCount: number = 0;
  private pageByCursor: Map<string, NotificationPage> = new Map();
  private pageByCategory: Map<NotificationCategory, NotificationPage> = new Map();
  private defaultPage?: NotificationPage;

  setPage(page: NotificationPage): void {
    this.defaultPage = page;
  }

  setPageForCursor(cursor: string, page: NotificationPage): void {
    this.pageByCursor.set(cursor, page);
  }

  setPageForCategory(category: NotificationCategory, page: NotificationPage): void {
    this.pageByCategory.set(category, page);
  }

  getNotificationsPage(category: NotificationCategory, cursor?: string): Promise<NotificationPage> {
    this.listRequests.push({ category: category, cursor: cursor });
    if (this.failList) {
      return Promise.reject(new HttpFailure(HttpFailureKind.NETWORK));
    }
    if (cursor !== undefined && this.pageByCursor.has(cursor)) {
      return Promise.resolve(this.pageByCursor.get(cursor) ?? emptyPage());
    }
    if (this.pageByCategory.has(category)) {
      return Promise.resolve(this.pageByCategory.get(category) ?? emptyPage());
    }
    return Promise.resolve(this.defaultPage ?? emptyPage());
  }

  getUnreadCounts(): Promise<NotificationUnreadCounts> {
    this.unreadCountsRequested += 1;
    if (this.failUnread) {
      return Promise.reject(new HttpFailure(HttpFailureKind.NETWORK));
    }
    const counts: NotificationUnreadCounts = { defaultCount: 1, followCount: 2, voteThankCount: 3 };
    return Promise.resolve(counts);
  }

  markAllAsRead(): Promise<void> {
    this.readAllCalls += 1;
    if (this.failReadAll) {
      return Promise.reject(new HttpFailure(HttpFailureKind.NETWORK));
    }
    return Promise.resolve();
  }

  cancel(): void {
    this.cancelCount += 1;
  }
}

class RecordingSettingsGateway implements NotificationSettingsGateway {
  readonly saved: Array<NotificationPreferences> = [];
  failLoad: boolean = false;
  failSave: boolean = false;
  private preferences: NotificationPreferences;

  constructor(preferences: NotificationPreferences) {
    this.preferences = preferences;
  }

  loadNotificationPreferences(): Promise<NotificationPreferences> {
    if (this.failLoad) {
      return Promise.reject(new HttpFailure(HttpFailureKind.NETWORK));
    }
    return Promise.resolve(this.preferences);
  }

  saveNotificationPreferences(value: NotificationPreferences): Promise<void> {
    if (this.failSave) {
      return Promise.reject(new HttpFailure(HttpFailureKind.NETWORK));
    }
    this.preferences = value;
    this.saved.push(value);
    return Promise.resolve();
  }
}

function notification(id: string, category: NotificationCategory = NotificationCategory.DEFAULT,
  isRead: boolean = false): NotificationItem {
  return {
    id: id,
    category: category,
    isRead: isRead,
    createTime: 1760000000,
    mergeCount: 1,
    verb: ' 邀请你回答问题',
    actors: [],
    contentText: '问题内容',
    contentLink: '',
    extendText: ''
  };
}

function emptyPage(): NotificationPage {
  return {
    items: [],
    cursor: { isEnd: true, isStart: true, page: 0, total: 0 }
  };
}

function defaultPreferences(): NotificationPreferences {
  return {
    likeAnswerDisplay: true,
    likeCommentDisplay: true,
    replyCommentDisplay: true,
    inviteAnswerDisplay: false,
    autoMarkAsRead: false,
    unreadBadge: true
  };
}

export default function notificationStateTest(): void {
  describe('notificationStateTest', () => {
    it('requiresLoginAndOffersLoginWhenGuest', 0, async () => {
      const repository = new ControlledNotificationRepository();
      const controller = new NotificationController(repository, new FixedSessionGateway(SessionStatus.GUEST));
      controller.activate();
      await controller.loadInitial();
      expect(controller.snapshot().phase).assertEqual(NotificationPhase.ERROR);
      expect(controller.snapshot().requiresLogin).assertTrue();
      expect(repository.listRequests.length).assertEqual(0);
    });

    it('loadsFirstPageWithUnreadCountsAndDeduplicates', 0, async () => {
      const repository = new ControlledNotificationRepository();
      repository.setPage({
        items: [notification('1'), notification('1'), notification('2')],
        cursor: {
          isEnd: false,
          isStart: true,
          next: 'https://www.zhihu.com/api/v4/notifications/v2/default?limit=20&offset=20',
          page: 0,
          total: 0
        }
      });
      const controller = new NotificationController(repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      expect(repository.listRequests[0].cursor).assertUndefined();
      expect(controller.snapshot().phase).assertEqual(NotificationPhase.READY);
      expect(controller.snapshot().items.length).assertEqual(2);
      expect(controller.snapshot().canLoadMore).assertTrue();
      expect(repository.unreadCountsRequested).assertEqual(1);
      expect(controller.snapshot().unreadTotal).assertEqual(6);
    });

    it('loadsMoreWithCursorAndMergesWithoutDuplicates', 0, async () => {
      const repository = new ControlledNotificationRepository();
      const cursor = 'https://www.zhihu.com/api/v4/notifications/v2/default?limit=20&offset=20';
      repository.setPage({
        items: [notification('1'), notification('2')],
        cursor: { isEnd: false, isStart: true, next: cursor, page: 0, total: 0 }
      });
      const controller = new NotificationController(repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      repository.setPageForCursor(cursor, {
        items: [notification('2'), notification('3')],
        cursor: { isEnd: true, isStart: false, page: 0, total: 0 }
      });
      await controller.loadMore();
      expect(repository.listRequests[1].cursor).assertEqual(cursor);
      expect(controller.snapshot().items.length).assertEqual(3);
      expect(controller.snapshot().canLoadMore).assertFalse();
    });

    it('mapsNetworkFailureToErrorPhaseAndRetries', 0, async () => {
      const repository = new ControlledNotificationRepository();
      repository.failList = true;
      const controller = new NotificationController(repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      expect(controller.snapshot().phase).assertEqual(NotificationPhase.ERROR);
      expect(controller.snapshot().requiresLogin).assertFalse();
      repository.failList = false;
      repository.setPage({ items: [notification('1')], cursor: { isEnd: true, isStart: true, page: 0, total: 0 } });
      await controller.retry();
      expect(controller.snapshot().phase).assertEqual(NotificationPhase.READY);
    });

    it('switchesCategoryAndLoadsLazily', 0, async () => {
      const repository = new ControlledNotificationRepository();
      repository.setPage({
        items: [notification('1', NotificationCategory.DEFAULT)],
        cursor: { isEnd: true, isStart: true, page: 0, total: 0 }
      });
      repository.setPageForCategory(NotificationCategory.FOLLOW, emptyPage());
      const controller = new NotificationController(repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      await controller.selectCategory(NotificationCategory.FOLLOW);
      expect(controller.snapshot().selectedCategory).assertEqual(NotificationCategory.FOLLOW);
      expect(controller.snapshot().items.length).assertEqual(0);
      expect(controller.snapshot().phase).assertEqual(NotificationPhase.EMPTY);
      await controller.selectCategory(NotificationCategory.DEFAULT);
      expect(controller.snapshot().items.length).assertEqual(1);
      expect(repository.listRequests.length).assertEqual(2);
    });

    it('marksSingleItemReadLocally', 0, async () => {
      const repository = new ControlledNotificationRepository();
      repository.setPage({
        items: [notification('1'), notification('2')],
        cursor: { isEnd: true, isStart: true, page: 0, total: 0 }
      });
      const controller = new NotificationController(repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      controller.markItemRead('1');
      const items = controller.snapshot().items;
      expect(items[0].isRead).assertTrue();
      expect(items[1].isRead).assertFalse();
    });

    it('marksAllReadOptimisticallyAndKeepsOnSuccess', 0, async () => {
      const repository = new ControlledNotificationRepository();
      repository.setPage({
        items: [notification('1'), notification('2', NotificationCategory.DEFAULT, true)],
        cursor: { isEnd: true, isStart: true, page: 0, total: 0 }
      });
      const controller = new NotificationController(repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      const marked = await controller.markAllRead();
      expect(marked).assertTrue();
      const items = controller.snapshot().items;
      expect(items.every((item: NotificationItem): boolean => item.isRead)).assertTrue();
      expect(controller.snapshot().unreadTotal).assertEqual(0);
    });

    it('rollsBackUnreadStateWhenMarkAllReadFails', 0, async () => {
      const repository = new ControlledNotificationRepository();
      repository.setPage({
        items: [notification('1'), notification('2')],
        cursor: { isEnd: true, isStart: true, page: 0, total: 0 }
      });
      const controller = new NotificationController(repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      repository.failReadAll = true;
      const marked = await controller.markAllRead();
      expect(marked).assertFalse();
      const items = controller.snapshot().items;
      expect(items[0].isRead).assertFalse();
      expect(items[1].isRead).assertFalse();
      expect(controller.snapshot().unreadTotal).assertEqual(6);
    });

    it('rejectsMarkAllReadWhenGuestWithoutNetworkCall', 0, async () => {
      const repository = new ControlledNotificationRepository();
      const controller = new NotificationController(repository, new FixedSessionGateway(SessionStatus.GUEST));
      controller.activate();
      const marked = await controller.markAllRead();
      expect(marked).assertFalse();
      expect(controller.snapshot().requiresLogin).assertTrue();
      expect(repository.readAllCalls).assertEqual(0);
    });

    it('readsAndWritesNotificationPreferencesThroughGateway', 0, async () => {
      const settings = new RecordingSettingsGateway(defaultPreferences());
      const preferences = await settings.loadNotificationPreferences();
      expect(preferences.inviteAnswerDisplay).assertFalse();
      expect(preferences.likeAnswerDisplay).assertTrue();
      const updated: NotificationPreferences = {
        likeAnswerDisplay: preferences.likeAnswerDisplay,
        likeCommentDisplay: preferences.likeCommentDisplay,
        replyCommentDisplay: preferences.replyCommentDisplay,
        inviteAnswerDisplay: true,
        autoMarkAsRead: true,
        unreadBadge: preferences.unreadBadge
      };
      await settings.saveNotificationPreferences(updated);
      expect(settings.saved.length).assertEqual(1);
      expect(settings.saved[0].inviteAnswerDisplay).assertTrue();
      const reloaded = await settings.loadNotificationPreferences();
      expect(reloaded.autoMarkAsRead).assertTrue();
    });

    it('mergesNotificationsDeduplicatedByIdentity', 0, () => {
      const merged = mergeNotifications(
        [notification('1'), notification('2', NotificationCategory.FOLLOW)],
        [notification('2', NotificationCategory.FOLLOW), notification('3')]
      );
      expect(merged.length).assertEqual(3);
      expect(merged[0].id).assertEqual('1');
      expect(merged[1].id).assertEqual('2');
      expect(merged[2].id).assertEqual('3');
    });
  });
}
