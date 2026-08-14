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
  CollectionFavoriteController,
  CollectionFavoritePhase
} from '../main/ets/pages/CollectionFavoriteState';

class UnusedLoginOperation implements SessionLoginOperation {
  readonly result: Promise<SessionState>;

  constructor(state: SessionState) {
    this.result = Promise.resolve(state);
  }

  cancel(): void {
  }
}

class FixedSessionGateway implements LoginSessionGateway {
  private status: SessionStatus;

  constructor(status: SessionStatus) {
    this.status = status;
  }

  getState(): SessionState {
    return {
      status: this.status,
      message: this.status === SessionStatus.AUTHENTICATED ? '已登录' : '游客模式',
      hasRetainedCredentials: this.status === SessionStatus.AUTHENTICATED,
      profile: this.status === SessionStatus.AUTHENTICATED ? {
        id: 'user-1',
        name: '测试用户',
        urlToken: 'alice-token',
        userType: 'people',
        avatarUrl: undefined
      } : undefined
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

interface FavoriteToggleRecord {
  collectionId: string;
  contentType: string;
  contentId: string;
}

interface CreatedCollectionRecord {
  title: string;
  description: string;
  isPublic: boolean;
}

class ControlledFavoriteRepository implements CollectionRepository {
  readonly added: Array<FavoriteToggleRecord> = [];
  readonly removed: Array<FavoriteToggleRecord> = [];
  readonly created: Array<CreatedCollectionRecord> = [];
  cancelCount: number = 0;
  failAdd: boolean = false;
  failRemove: boolean = false;
  failCreate: boolean = false;
  failLoad: boolean = false;
  private collections: Array<CollectionSummary> = [];

  setCollections(collections: Array<CollectionSummary>): void {
    this.collections = collections;
  }

  getCollectionsPage(_urlToken: string, _cursor?: string): Promise<CollectionPage> {
    return Promise.reject(new Error('not used'));
  }

  getCollection(_collectionId: string): Promise<CollectionSummary> {
    return Promise.reject(new Error('not used'));
  }

  getCollectionItemsPage(_collectionId: string, _cursor?: string): Promise<CollectionContentPage> {
    return Promise.reject(new Error('not used'));
  }

  getContentCollections(_contentType: string, _contentId: string): Promise<Array<CollectionSummary>> {
    if (this.failLoad) {
      return Promise.reject(new HttpFailure(HttpFailureKind.NETWORK));
    }
    return Promise.resolve(this.collections.slice());
  }

  createCollection(title: string, description: string, isPublic: boolean): Promise<void> {
    this.created.push({ title: title, description: description, isPublic: isPublic });
    if (this.failCreate) {
      return Promise.reject(new HttpFailure(HttpFailureKind.NETWORK));
    }
    return Promise.resolve();
  }

  deleteCollection(_collectionId: string): Promise<void> {
    return Promise.resolve();
  }

  addContentToCollection(collectionId: string, contentType: string, contentId: string): Promise<void> {
    this.added.push({ collectionId: collectionId, contentType: contentType, contentId: contentId });
    if (this.failAdd) {
      return Promise.reject(new HttpFailure(HttpFailureKind.NETWORK));
    }
    return Promise.resolve();
  }

  removeContentFromCollection(collectionId: string, contentType: string, contentId: string): Promise<void> {
    this.removed.push({ collectionId: collectionId, contentType: contentType, contentId: contentId });
    if (this.failRemove) {
      return Promise.reject(new HttpFailure(HttpFailureKind.NETWORK));
    }
    return Promise.resolve();
  }

  cancel(): void {
    this.cancelCount += 1;
  }
}

function collection(id: string, title: string, favorited: boolean): CollectionSummary {
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
    isFavorited: favorited,
    updatedAt: 0
  };
}

export default function collectionFavoriteStateTest(): void {
  describe('collectionFavoriteStateTest', () => {
    it('loadsCollectionsForContent', 0, async () => {
      const repository = new ControlledFavoriteRepository();
      repository.setCollections([collection('1', '收藏夹一', true), collection('2', '收藏夹二', false)]);
      const controller = new CollectionFavoriteController(repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.load('answer', '456');
      expect(controller.snapshot().phase).assertEqual(CollectionFavoritePhase.READY);
      expect(controller.snapshot().collections.length).assertEqual(2);
      expect(controller.snapshot().collections[0].isFavorited).assertTrue();
    });

    it('requiresLoginWhenGuest', 0, async () => {
      const repository = new ControlledFavoriteRepository();
      const controller = new CollectionFavoriteController(repository, new FixedSessionGateway(SessionStatus.GUEST));
      controller.activate();
      await controller.load('answer', '456');
      expect(controller.snapshot().phase).assertEqual(CollectionFavoritePhase.ERROR);
      expect(controller.snapshot().requiresLogin).assertTrue();
    });

    it('togglesFavoriteOptimisticallyAndAdds', 0, async () => {
      const repository = new ControlledFavoriteRepository();
      repository.setCollections([collection('1', '收藏夹一', false)]);
      const controller = new CollectionFavoriteController(repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.load('answer', '456');
      const before = controller.snapshot().collections[0];
      const ok = await controller.toggle(before, 'answer', '456');
      expect(ok).assertTrue();
      expect(repository.added.length).assertEqual(1);
      expect(repository.added[0].collectionId).assertEqual('1');
      expect(repository.added[0].contentType).assertEqual('answer');
      expect(repository.added[0].contentId).assertEqual('456');
      expect(controller.snapshot().collections[0].isFavorited).assertTrue();
    });

    it('togglesFavoriteOptimisticallyAndRemoves', 0, async () => {
      const repository = new ControlledFavoriteRepository();
      repository.setCollections([collection('1', '收藏夹一', true)]);
      const controller = new CollectionFavoriteController(repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.load('answer', '456');
      const before = controller.snapshot().collections[0];
      const ok = await controller.toggle(before, 'article', '789');
      expect(ok).assertTrue();
      expect(repository.removed.length).assertEqual(1);
      expect(repository.removed[0].contentType).assertEqual('article');
      expect(controller.snapshot().collections[0].isFavorited).assertFalse();
    });

    it('rollsBackFavoriteWhenAddFails', 0, async () => {
      const repository = new ControlledFavoriteRepository();
      repository.setCollections([collection('1', '收藏夹一', false)]);
      repository.failAdd = true;
      const controller = new CollectionFavoriteController(repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.load('answer', '456');
      const ok = await controller.toggle(controller.snapshot().collections[0], 'answer', '456');
      expect(ok).assertFalse();
      expect(controller.snapshot().collections[0].isFavorited).assertFalse();
      expect((controller.snapshot().message ?? '').length > 0).assertTrue();
    });

    it('rollsBackFavoriteWhenRemoveFails', 0, async () => {
      const repository = new ControlledFavoriteRepository();
      repository.setCollections([collection('1', '收藏夹一', true)]);
      repository.failRemove = true;
      const controller = new CollectionFavoriteController(repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.load('answer', '456');
      const ok = await controller.toggle(controller.snapshot().collections[0], 'answer', '456');
      expect(ok).assertFalse();
      expect(controller.snapshot().collections[0].isFavorited).assertTrue();
    });

    it('createsCollectionThenReloadsList', 0, async () => {
      const repository = new ControlledFavoriteRepository();
      repository.setCollections([collection('1', '收藏夹一', false)]);
      const controller = new CollectionFavoriteController(repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.load('answer', '456');
      repository.setCollections([collection('1', '收藏夹一', false), collection('9', '新收藏夹', false)]);
      const ok = await controller.createAndAdd('新收藏夹', '描述', true, 'answer', '456');
      expect(ok).assertTrue();
      expect(repository.created[0].title).assertEqual('新收藏夹');
      expect(controller.snapshot().collections.length).assertEqual(2);
    });

    it('rejectsBlankCreateTitle', 0, async () => {
      const repository = new ControlledFavoriteRepository();
      const controller = new CollectionFavoriteController(repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.load('answer', '456');
      const ok = await controller.createAndAdd('   ', '', false, 'answer', '456');
      expect(ok).assertFalse();
      expect(repository.created.length).assertEqual(0);
    });
  });
}
