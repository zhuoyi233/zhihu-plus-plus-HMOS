import { describe, expect, it } from '@ohos/hypium';
import {
  CollectionContentItem,
  CollectionContentKind,
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
  CollectionContentController,
  CollectionContentPhase,
  mergeCollectionItems
} from '../main/ets/pages/CollectionContentState';

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

class ControlledContentRepository implements CollectionRepository {
  readonly detailRequests: Array<string> = [];
  readonly itemRequests: Array<string | undefined> = [];
  cancelCount: number = 0;
  failDetail: boolean = false;
  failItems: boolean = false;
  private detail?: CollectionSummary;
  private itemsPage?: CollectionContentPage;

  setDetail(detail: CollectionSummary): void {
    this.detail = detail;
  }

  setItemsPage(page: CollectionContentPage): void {
    this.itemsPage = page;
  }

  getCollectionsPage(_urlToken: string, _cursor?: string): Promise<CollectionPage> {
    return Promise.reject(new Error('not used'));
  }

  getCollection(collectionId: string): Promise<CollectionSummary> {
    this.detailRequests.push(collectionId);
    if (this.failDetail) {
      return Promise.reject(new HttpFailure(HttpFailureKind.NETWORK));
    }
    return Promise.resolve(this.detail ?? {
      id: collectionId,
      title: '收藏夹',
      description: '',
      isPublic: true,
      answerCount: 0,
      followerCount: 0,
      itemCount: 0,
      likeCount: 0,
      commentCount: 0,
      isFavorited: false,
      updatedAt: 0
    });
  }

  getCollectionItemsPage(_collectionId: string, cursor?: string): Promise<CollectionContentPage> {
    this.itemRequests.push(cursor);
    if (this.failItems) {
      return Promise.reject(new HttpFailure(HttpFailureKind.NETWORK));
    }
    return Promise.resolve(this.itemsPage ?? {
      items: [],
      cursor: { isEnd: true, isStart: true, page: 0, total: 0 }
    });
  }

  getContentCollections(_contentType: string, _contentId: string): Promise<Array<CollectionSummary>> {
    return Promise.resolve([]);
  }

  createCollection(_title: string, _description: string, _isPublic: boolean): Promise<void> {
    return Promise.resolve();
  }

  deleteCollection(_collectionId: string): Promise<void> {
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

function item(kind: CollectionContentKind, id: string, title: string): CollectionContentItem {
  return {
    kind: kind,
    id: id,
    title: title,
    excerpt: '',
    details: '',
    voteupCount: 0,
    commentCount: 0,
    createdAt: 0
  };
}

export default function collectionContentStateTest(): void {
  describe('collectionContentStateTest', () => {
    it('requiresLoginWhenGuest', 0, async () => {
      const repository = new ControlledContentRepository();
      const controller = new CollectionContentController('100', repository, new FixedSessionGateway(SessionStatus.GUEST));
      controller.activate();
      await controller.loadInitial();
      expect(controller.snapshot().phase).assertEqual(CollectionContentPhase.ERROR);
      expect(controller.snapshot().requiresLogin).assertTrue();
      expect(repository.detailRequests.length).assertEqual(0);
    });

    it('loadsDetailAndItemsAndDeduplicates', 0, async () => {
      const repository = new ControlledContentRepository();
      repository.setDetail({
        id: '100',
        title: '我的收藏',
        description: '常用内容',
        isPublic: true,
        answerCount: 2,
        followerCount: 3,
        itemCount: 2,
        likeCount: 5,
        commentCount: 1,
        isFavorited: false,
        updatedAt: 1700000000
      });
      repository.setItemsPage({
        items: [
          item(CollectionContentKind.ANSWER, '1', '回答一'),
          item(CollectionContentKind.ANSWER, '1', '回答一'),
          item(CollectionContentKind.ARTICLE, '2', '文章二')
        ],
        cursor: { isEnd: true, isStart: true, page: 0, total: 0 }
      });
      const controller = new CollectionContentController('100', repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      expect(repository.detailRequests[0]).assertEqual('100');
      expect(repository.itemRequests[0]).assertUndefined();
      expect(controller.snapshot().phase).assertEqual(CollectionContentPhase.READY);
      expect(controller.snapshot().collection?.title).assertEqual('我的收藏');
      expect(controller.snapshot().items.length).assertEqual(2);
    });

    it('loadsMoreWithCursor', 0, async () => {
      const repository = new ControlledContentRepository();
      repository.setItemsPage({
        items: [item(CollectionContentKind.ANSWER, '1', '回答一')],
        cursor: { isEnd: false, isStart: true, next: 'https://www.zhihu.com/api/v4/collections/100/items?limit=20&offset=20', page: 0, total: 0 }
      });
      const controller = new CollectionContentController('100', repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      repository.setItemsPage({
        items: [item(CollectionContentKind.ANSWER, '2', '回答二')],
        cursor: { isEnd: true, isStart: false, page: 0, total: 0 }
      });
      await controller.loadMore();
      expect(repository.itemRequests[1]).assertEqual(
        'https://www.zhihu.com/api/v4/collections/100/items?limit=20&offset=20'
      );
      expect(controller.snapshot().items.length).assertEqual(2);
    });

    it('mapsDetailFailureToErrorAndRetries', 0, async () => {
      const repository = new ControlledContentRepository();
      repository.failDetail = true;
      const controller = new CollectionContentController('100', repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      expect(controller.snapshot().phase).assertEqual(CollectionContentPhase.ERROR);
      repository.failDetail = false;
      repository.setItemsPage({ items: [item(CollectionContentKind.ANSWER, '1', '回答一')], cursor: { isEnd: true, isStart: true, page: 0, total: 0 } });
      await controller.retry();
      expect(controller.snapshot().phase).assertEqual(CollectionContentPhase.READY);
    });

    it('treatsEmptyItemsAsEmptyPhase', 0, async () => {
      const repository = new ControlledContentRepository();
      repository.setItemsPage({ items: [], cursor: { isEnd: true, isStart: true, page: 0, total: 0 } });
      const controller = new CollectionContentController('100', repository,
        new FixedSessionGateway(SessionStatus.AUTHENTICATED));
      controller.activate();
      await controller.loadInitial();
      expect(controller.snapshot().phase).assertEqual(CollectionContentPhase.EMPTY);
    });

    it('mergesItemsDeduplicatedByKindAndId', 0, () => {
      const merged = mergeCollectionItems(
        [item(CollectionContentKind.ANSWER, '1', 'a'), item(CollectionContentKind.ARTICLE, '2', 'b')],
        [item(CollectionContentKind.ARTICLE, '2', 'b'), item(CollectionContentKind.PIN, '3', 'c')]
      );
      expect(merged.length).assertEqual(3);
      expect(merged[0].kind).assertEqual(CollectionContentKind.ANSWER);
      expect(merged[2].kind).assertEqual(CollectionContentKind.PIN);
    });
  });
}
