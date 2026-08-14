import { describe, expect, it } from '@ohos/hypium';
import {
  CollectionContentPage,
  CollectionPage,
  CollectionRepository,
  CollectionSummary,
  HttpFailure,
  HttpFailureKind,
  LoginSessionGateway,
  SessionCookie,
  SessionLoginOperation,
  SessionState,
  SessionStatus
} from 'data';
import {
  CollectionController,
  CollectionPhase,
  mergeCollections
} from '../main/ets/pages/CollectionState';

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

interface CreatedCollectionRecord {
  title: string;
  description: string;
  isPublic: boolean;
}

class ControlledCollectionRepository implements CollectionRepository {
  readonly listRequests: Array<string | undefined> = [];
  readonly created: Array<CreatedCollectionRecord> = [];
  readonly deleted: Array<string> = [];
  cancelCount: number = 0;
  failList: boolean = false;
  failCreate: boolean = false;
  failDelete: boolean = false;
  private listPage?: CollectionPage;

  setListPage(page: CollectionPage): void {
    this.listPage = page;
  }

  getCollectionsPage(_urlToken: string, cursor?: string): Promise<CollectionPage> {
    this.listRequests.push(cursor);
    if (this.failList) {
      return Promise.reject(new HttpFailure(HttpFailureKind.NETWORK));
    }
    return Promise.resolve(this.listPage ?? emptyPage());
  }

  getCollection(_collectionId: string): Promise<CollectionSummary> {
    return Promise.reject(new Error('not used'));
  }

  getCollectionItemsPage(_collectionId: string, _cursor?: string): Promise<CollectionContentPage> {
    return Promise.reject(new Error('not used'));
  }

  getContentCollections(_contentType: string, _contentId: string): Promise<Array<CollectionSummary>> {
    return Promise.resolve([]);
  }

  createCollection(title: string, description: string, isPublic: boolean): Promise<void> {
    this.created.push({ title: title, description: description, isPublic: isPublic });
    if (this.failCreate) {
      return Promise.reject(new HttpFailure(HttpFailureKind.NETWORK));
    }
    return Promise.resolve();
  }

  deleteCollection(collectionId: string): Promise<void> {
    this.deleted.push(collectionId);
    if (this.failDelete) {
      return Promise.reject(new HttpFailure(HttpFailureKind.NETWORK));
    }
    return Promise.resolve();
  }

  addContentToCollection(_collectionId: string, _contentType: string, _contentId: string): Promise<void> {
    return Promise.resolve();
  }

  removeContentFromCollection(_collectionId: string, _contentType: string, _contentId: string): Promise<void> {
    return Promise.resolve();
  }

  cancel(): void {
    this.cancelCount += 1;
  }
}

function collection(id: string, title: string): CollectionSummary {
  return {
    id: id,
    title: title,
    description: '',
    isPublic: true,
    answerCount: 0,
    followerCount: 0,
    itemCount: 1,
    likeCount: 0,
    commentCount: 0,
    isFavorited: false,
    updatedAt: 0
  };
}

function emptyPage(): CollectionPage {
  return {
    items: [],
    cursor: { isEnd: true, isStart: true, page: 0, total: 0 }
  };
}

export default function collectionStateTest(): void {
  describe('collectionStateTest', () => {
    it('requiresLoginAndOffersLoginWhenGuest', 0, async () => {
      const repository = new ControlledCollectionRepository();
      const controller = new CollectionController('alice-token', repository, new FixedSessionGateway(SessionStatus.GUEST));
      controller.activate();
      await controller.loadInitial();
      expect(controller.snapshot().phase).assertEqual(CollectionPhase.ERROR);
      expect(controller.snapshot().requiresLogin).assertTrue();
      expect(repository.listRequests.length).assertEqual(0);
    });

    it('loadsFirstPageAndDeduplicatesItems', 0, async () => {
      const repository = new ControlledCollectionRepository();
      repository.setListPage({
        items: [collection('1', '收藏夹一'), collection('1', '收藏夹一'), collection('2', '收藏夹二')],
        cursor: { isEnd: false, isStart: true, next: 'https://www.zhihu.com/api/v4/people/alice-token/collections?limit=20&offset=20', page: 0, total: 0 }
      });
      const controller = new CollectionController('alice-token', repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      expect(repository.listRequests[0]).assertUndefined();
      expect(controller.snapshot().phase).assertEqual(CollectionPhase.READY);
      expect(controller.snapshot().items.length).assertEqual(2);
      expect(controller.snapshot().canLoadMore).assertTrue();
    });

    it('loadsMoreWithCursorAndMergesWithoutDuplicates', 0, async () => {
      const repository = new ControlledCollectionRepository();
      repository.setListPage({
        items: [collection('1', '收藏夹一'), collection('2', '收藏夹二')],
        cursor: { isEnd: false, isStart: true, next: 'https://www.zhihu.com/api/v4/people/alice-token/collections?limit=20&offset=20', page: 0, total: 0 }
      });
      const controller = new CollectionController('alice-token', repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      repository.setListPage({
        items: [collection('2', '收藏夹二'), collection('3', '收藏夹三')],
        cursor: { isEnd: true, isStart: false, page: 0, total: 0 }
      });
      await controller.loadMore();
      expect(repository.listRequests[1]).assertEqual(
        'https://www.zhihu.com/api/v4/people/alice-token/collections?limit=20&offset=20'
      );
      expect(controller.snapshot().items.length).assertEqual(3);
      expect(controller.snapshot().canLoadMore).assertFalse();
    });

    it('mapsNetworkFailureToErrorPhaseAndRetries', 0, async () => {
      const repository = new ControlledCollectionRepository();
      repository.failList = true;
      const controller = new CollectionController('alice-token', repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      expect(controller.snapshot().phase).assertEqual(CollectionPhase.ERROR);
      expect(controller.snapshot().requiresLogin).assertFalse();
      repository.failList = false;
      repository.setListPage({ items: [collection('1', '收藏夹一')], cursor: { isEnd: true, isStart: true, page: 0, total: 0 } });
      await controller.retry();
      expect(controller.snapshot().phase).assertEqual(CollectionPhase.READY);
    });

    it('createsCollectionThenReloadsList', 0, async () => {
      const repository = new ControlledCollectionRepository();
      repository.setListPage({
        items: [collection('1', '收藏夹一')],
        cursor: { isEnd: true, isStart: true, page: 0, total: 0 }
      });
      const controller = new CollectionController('alice-token', repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      repository.setListPage({
        items: [collection('1', '收藏夹一'), collection('9', '新收藏夹')],
        cursor: { isEnd: true, isStart: true, page: 0, total: 0 }
      });
      const created = await controller.createCollection('新收藏夹', '描述', true);
      expect(created).assertTrue();
      expect(repository.created[0].title).assertEqual('新收藏夹');
      expect(repository.created[0].isPublic).assertTrue();
      expect(controller.snapshot().items.length).assertEqual(2);
    });

    it('rejectsBlankTitleWithoutNetworkCall', 0, async () => {
      const repository = new ControlledCollectionRepository();
      const controller = new CollectionController('alice-token', repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      const created = await controller.createCollection('   ', '', false);
      expect(created).assertFalse();
      expect(repository.created.length).assertEqual(0);
    });

    it('deletesOptimisticallyAndRollsBackOnFailure', 0, async () => {
      const repository = new ControlledCollectionRepository();
      repository.setListPage({
        items: [collection('1', '收藏夹一'), collection('2', '收藏夹二')],
        cursor: { isEnd: true, isStart: true, page: 0, total: 0 }
      });
      const controller = new CollectionController('alice-token', repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();

      repository.failDelete = true;
      const failed = await controller.deleteCollection('1');
      expect(failed).assertFalse();
      expect(repository.deleted[0]).assertEqual('1');
      expect(controller.snapshot().items.length).assertEqual(2);
      expect(controller.snapshot().items[0].id).assertEqual('1');

      repository.failDelete = false;
      const removed = await controller.deleteCollection('2');
      expect(removed).assertTrue();
      expect(controller.snapshot().items.length).assertEqual(1);
      expect(controller.snapshot().items[0].id).assertEqual('1');
    });

    it('mergesCollectionsDeduplicatedByIdentity', 0, () => {
      const merged = mergeCollections([collection('1', 'a'), collection('2', 'b')],
        [collection('2', 'b'), collection('3', 'c')]);
      expect(merged.length).assertEqual(3);
      expect(merged[0].id).assertEqual('1');
      expect(merged[1].id).assertEqual('2');
      expect(merged[2].id).assertEqual('3');
    });
  });
}
