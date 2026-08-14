import { describe, expect, it } from '@ohos/hypium';
import {
  HttpFailure,
  HttpFailureKind,
  LoginSessionGateway,
  PeopleDetailRepository,
  PeopleContentItem,
  PeopleContentKind,
  PeopleContentPage,
  PeopleContentRepository,
  PeopleContentSection,
  PeopleProfile,
  PinDetail,
  PinRepository,
  SessionCookie,
  SessionLoginOperation,
  SessionState,
  SessionStatus
} from 'data';
import {
  PeopleDetailController,
  PinDetailController,
  ReadOnlyDetailPhase
} from '../main/ets/pages/PeoplePinDetailState';
import { PeopleContentController, PeopleContentPhase } from '../main/ets/pages/PeopleContentState';
import { parseZhihuHtml, ReaderInlineKind } from 'reader';

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
      hasRetainedCredentials: status === SessionStatus.AUTHENTICATED
    };
  }

  getState(): SessionState {
    return {
      status: this.state.status,
      message: this.state.message,
      hasRetainedCredentials: this.state.hasRetainedCredentials
    };
  }

  retryRetainedSession(): Promise<SessionState> {
    return Promise.resolve(this.getState());
  }

  setStatus(status: SessionStatus): void {
    this.state = {
      status: status,
      message: status === SessionStatus.AUTHENTICATED ? '已登录' : '游客模式',
      hasRetainedCredentials: status === SessionStatus.AUTHENTICATED
    };
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

interface PendingPeople {
  resolve: (profile: PeopleProfile) => void;
}

class ControlledPeopleRepository implements PeopleDetailRepository {
  readonly pending: Array<PendingPeople> = [];
  requestCount: number = 0;
  cancelCount: number = 0;

  getUser(_identifier: string): Promise<PeopleProfile> {
    this.requestCount += 1;
    return new Promise<PeopleProfile>((resolve: (profile: PeopleProfile) => void): void => {
      this.pending.push({ resolve: resolve });
    });
  }

  cancel(): void {
    this.cancelCount += 1;
  }
}

class FixedPinRepository implements PinRepository {
  requestCount: number = 0;
  cancelCount: number = 0;
  failure?: HttpFailure;

  async getPin(_id: string): Promise<PinDetail> {
    this.requestCount += 1;
    if (this.failure !== undefined) {
      throw this.failure;
    }
    return pinFixture();
  }

  cancel(): void {
    this.cancelCount += 1;
  }
}

class FixedPeopleContentRepository implements PeopleContentRepository {
  requestCount: number = 0;
  cancelCount: number = 0;
  pages: Array<PeopleContentPage> = [];

  async getContentPage(_identifier: string, _section: PeopleContentSection, _cursor?: string): Promise<PeopleContentPage> {
    this.requestCount += 1;
    const page = this.pages.shift();
    if (page === undefined) {
      throw new Error('missing fixture');
    }
    return page;
  }

  cancel(): void {
    this.cancelCount += 1;
  }
}

export default function peoplePinDetailStateTest(): void {
  describe('peoplePinDetailStateTest', () => {
    it('gatesBothDetailsBeforeNetworkWhenSessionIsGuest', 0, async () => {
      const peopleRepository = new ControlledPeopleRepository();
      const pinRepository = new FixedPinRepository();
      const guest = new FixedSessionGateway(SessionStatus.GUEST);
      const people = new PeopleDetailController(peopleRepository, guest);
      const pin = new PinDetailController(pinRepository, guest);
      people.activate();
      pin.activate();
      await people.load('alice-token');
      await pin.load('1');

      expect(peopleRepository.requestCount).assertEqual(0);
      expect(pinRepository.requestCount).assertEqual(0);
      expect(people.snapshot().requiresLogin).assertTrue();
      expect(pin.snapshot().requiresLogin).assertTrue();
      expect(people.snapshot().errorMessage).assertEqual('用户主页需要登录，请登录后重试');
      expect(pin.snapshot().errorMessage).assertEqual('想法详情需要登录，请登录后重试');
    });

    it('loadsProfileAndReturnsDefensiveCopy', 0, async () => {
      const repository = new ControlledPeopleRepository();
      const controller = new PeopleDetailController(
        repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED)
      );
      controller.activate();
      const pending = controller.load('alice-token');
      expect(controller.snapshot().phase).assertEqual(ReadOnlyDetailPhase.LOADING);
      repository.pending[0].resolve(peopleFixture());
      await pending;

      const state = controller.snapshot();
      expect(state.phase).assertEqual(ReadOnlyDetailPhase.READY);
      expect(state.profile?.answerCount).assertEqual(34);
      if (state.profile !== undefined) {
        state.profile.name = 'changed';
      }
      expect(controller.snapshot().profile?.name).assertEqual('Alice');
    });

    it('cancelsOnLeaveAndBlocksLatePeopleWriteBack', 0, async () => {
      const repository = new ControlledPeopleRepository();
      const controller = new PeopleDetailController(
        repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED)
      );
      controller.activate();
      const pending = controller.load('alice-token');
      controller.deactivate();
      repository.pending[0].resolve(peopleFixture());
      await pending;
      expect(repository.cancelCount).assertEqual(1);
      expect(controller.snapshot().phase).assertEqual(ReadOnlyDetailPhase.LOADING);
    });

    it('doesNotPublishProtectedProfileAfterLogoutRace', 0, async () => {
      const repository = new ControlledPeopleRepository();
      const session = new FixedSessionGateway(SessionStatus.AUTHENTICATED);
      const controller = new PeopleDetailController(repository, session);
      controller.activate();
      const pending = controller.load('alice-token');
      session.setStatus(SessionStatus.GUEST);
      repository.pending[0].resolve(peopleFixture());
      await pending;

      expect(controller.snapshot().phase).assertEqual(ReadOnlyDetailPhase.ERROR);
      expect(controller.snapshot().profile).assertUndefined();
      expect(controller.snapshot().requiresLogin).assertTrue();
    });

    it('loadsPinAndClonesAuthorTopics', 0, async () => {
      const controller = new PinDetailController(
        new FixedPinRepository(),
        new FixedSessionGateway(SessionStatus.AUTHENTICATED)
      );
      controller.activate();
      await controller.load('1');
      const state = controller.snapshot();
      expect(state.phase).assertEqual(ReadOnlyDetailPhase.READY);
      expect(state.pin?.author.name).assertEqual('Pin Author');
      expect(state.pin?.topics[0].name).assertEqual('HarmonyOS');
      if (state.pin !== undefined) {
        state.pin.author.name = 'changed';
        state.pin.topics[0].name = 'changed';
      }
      expect(controller.snapshot().pin?.author.name).assertEqual('Pin Author');
      expect(controller.snapshot().pin?.topics[0].name).assertEqual('HarmonyOS');
    });

    it('separates401LoginActionFrom403RiskRetry', 0, async () => {
      const repository401 = new FixedPinRepository();
      repository401.failure = new HttpFailure(HttpFailureKind.AUTHENTICATION, 401);
      const controller401 = new PinDetailController(
        repository401,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED)
      );
      controller401.activate();
      await controller401.load('1');
      expect(controller401.snapshot().requiresLogin).assertTrue();
      expect(controller401.snapshot().errorMessage).assertEqual('想法详情需要登录，请登录后重试');

      const repository403 = new FixedPinRepository();
      repository403.failure = new HttpFailure(HttpFailureKind.AUTHENTICATION, 403);
      const controller403 = new PinDetailController(
        repository403,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED)
      );
      controller403.activate();
      await controller403.load('1');
      expect(controller403.snapshot().requiresLogin).assertFalse();
      expect(controller403.snapshot().errorMessage).assertEqual('想法请求被拒绝，可能需要完成知乎风控验证');
    });

    it('feedsPinHtmlThroughNativeReaderFormulaContract', 0, () => {
      const blocks = parseZhihuHtml('<p>公式 <img eeimg="1" alt="x+y" ' +
        'src="https://www.zhihu.com/equation?tex=x%2By"></p>');
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].inlineRuns[1].kind).assertEqual(ReaderInlineKind.FORMULA);
      expect(blocks[0].inlineRuns[1].text).assertEqual('x+y');
    });

    it('loadsPeopleContentPagesAndDeduplicatesItems', 0, async () => {
      const repository = new FixedPeopleContentRepository();
      repository.pages = [
        peopleContentPage([peopleAnswer('101')], false, 'next'),
        peopleContentPage([peopleAnswer('101'), peopleAnswer('102')], true)
      ];
      const controller = new PeopleContentController('alice-token', PeopleContentSection.ANSWERS, repository);
      controller.activate();
      await controller.loadInitial();
      expect(controller.snapshot().phase).assertEqual(PeopleContentPhase.READY);
      expect(controller.snapshot().canLoadMore).assertTrue();
      await controller.loadMore();
      expect(controller.snapshot().items.length).assertEqual(2);
      expect(controller.snapshot().items[1].id).assertEqual('102');
      expect(controller.snapshot().canLoadMore).assertFalse();
    });

    it('cancelsPeopleContentWhenLeavingPage', 0, async () => {
      const repository = new FixedPeopleContentRepository();
      repository.pages = [peopleContentPage([peopleAnswer('101')], true)];
      const controller = new PeopleContentController('alice-token', PeopleContentSection.ANSWERS, repository);
      controller.activate();
      await controller.loadInitial();
      controller.deactivate();
      expect(repository.cancelCount).assertEqual(2);
    });
  });
}

function peopleContentPage(items: Array<PeopleContentItem>, isEnd: boolean, next?: string): PeopleContentPage {
  return {
    items: items,
    cursor: { isEnd: isEnd, isStart: true, next: next, page: 0, total: 0 }
  };
}

function peopleAnswer(id: string): PeopleContentItem {
  return {
    kind: PeopleContentKind.ANSWER,
    id: id,
    title: `问题 ${id}`,
    excerpt: `摘要 ${id}`,
    voteupCount: 1,
    commentCount: 2,
    createdAt: 3
  };
}

function peopleFixture(): PeopleProfile {
  return {
    id: 'member-hash',
    urlToken: 'alice-token',
    name: 'Alice',
    headline: 'HarmonyOS developer',
    avatarUrl: 'https://picx.zhimg.com/avatar.png',
    followerCount: 78,
    followingCount: 12,
    answerCount: 34,
    articleCount: 5,
    isFollowing: true,
    isOrganization: false,
    canonicalUrl: 'https://www.zhihu.com/people/alice-token'
  };
}

function pinFixture(): PinDetail {
  return {
    id: '1',
    contentHtml: '<p>想法正文</p>',
    url: 'https://www.zhihu.com/pin/1',
    likeCount: 56,
    commentCount: 7,
    createdAt: 1,
    updatedAt: 2,
    author: {
      id: 'pin-author',
      urlToken: 'pin-author-token',
      name: 'Pin Author',
      headline: '作者签名',
      followerCount: 8,
      isFollowing: false,
      isOrganization: false
    },
    topics: [{ id: '19551275', name: 'HarmonyOS' }]
  };
}
