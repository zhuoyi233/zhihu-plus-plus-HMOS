import { describe, expect, it } from '@ohos/hypium';
import {
  ContentDestination,
  findP1DestinationStackIndex,
  InfrastructureDestination,
  P1DestinationName,
  P1StackEntry,
  SearchDestination
} from 'core';
import {
  CollectionContentItem,
  CollectionContentKind,
  CollectionContentPage,
  CollectionPage,
  CollectionRepository,
  CollectionSummary,
  FeedItem,
  FeedPage,
  FeedRepository,
  FeedTargetKind,
  LoginSessionGateway,
  SearchRepository,
  SearchResultItem,
  SearchResultPage,
  SessionCookie,
  SessionLoginOperation,
  SessionState,
  SessionStatus
} from 'data';
import {
  HomeFeedController,
  HomeFeedPhase
} from '../main/ets/pages/HomeFeedState';
import {
  CollectionController,
  CollectionPhase
} from '../main/ets/pages/CollectionState';
import {
  CollectionContentController,
  CollectionContentPhase
} from '../main/ets/pages/CollectionContentState';
import {
  SearchController,
  SearchPhase
} from '../main/ets/pages/SearchState';

class UnusedSessionLoginOperation implements SessionLoginOperation {
  readonly result: Promise<SessionState>;

  constructor(state: SessionState) {
    this.result = Promise.resolve(state);
  }

  cancel(): void {
  }
}

class AuthenticatedSessionGateway implements LoginSessionGateway {
  getState(): SessionState {
    return {
      status: SessionStatus.AUTHENTICATED,
      message: '已登录',
      hasRetainedCredentials: true,
      profile: {
        id: 'user-1',
        name: '测试用户',
        urlToken: 'alice-token',
        userType: 'people',
        avatarUrl: undefined
      }
    };
  }

  retryRetainedSession(): Promise<SessionState> {
    return Promise.resolve(this.getState());
  }

  beginLoginWithCookieHeader(_rawCookie: string): SessionLoginOperation {
    return new UnusedSessionLoginOperation(this.getState());
  }

  beginLoginWithCookies(_cookies: Array<SessionCookie>): SessionLoginOperation {
    return new UnusedSessionLoginOperation(this.getState());
  }

  logout(): Promise<SessionState> {
    return Promise.resolve(this.getState());
  }
}

class CountingFeedRepository implements FeedRepository {
  loadCount: number = 0;
  private readonly page: FeedPage;

  constructor(page: FeedPage) {
    this.page = page;
  }

  loadHomePage(_cursor?: string): Promise<FeedPage> {
    this.loadCount += 1;
    return Promise.resolve(this.page);
  }

  cancel(): void {
  }
}

class CountingSearchRepository implements SearchRepository {
  searchCount: number = 0;
  private readonly page: SearchResultPage;

  constructor(page: SearchResultPage) {
    this.page = page;
  }

  search(_query: string, _cursor?: string): Promise<SearchResultPage> {
    this.searchCount += 1;
    return Promise.resolve(this.page);
  }

  cancel(): void {
  }
}

class CountingCollectionRepository implements CollectionRepository {
  listLoadCount: number = 0;
  detailLoadCount: number = 0;
  itemsLoadCount: number = 0;
  private readonly listPage: CollectionPage;
  private readonly detail: CollectionSummary;
  private readonly itemsPage: CollectionContentPage;

  constructor(listPage: CollectionPage, detail: CollectionSummary, itemsPage: CollectionContentPage) {
    this.listPage = listPage;
    this.detail = detail;
    this.itemsPage = itemsPage;
  }

  getCollectionsPage(_urlToken: string, _cursor?: string): Promise<CollectionPage> {
    this.listLoadCount += 1;
    return Promise.resolve(this.listPage);
  }

  getCollection(_collectionId: string): Promise<CollectionSummary> {
    this.detailLoadCount += 1;
    return Promise.resolve(this.detail);
  }

  getCollectionItemsPage(_collectionId: string, _cursor?: string): Promise<CollectionContentPage> {
    this.itemsLoadCount += 1;
    return Promise.resolve(this.itemsPage);
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
  }
}

interface TestDestinationParam {
  name: string;
  id?: string;
  query?: string;
}

function contentEntry(name: P1DestinationName, id: string): P1StackEntry {
  const param: TestDestinationParam = { name: name, id: id };
  return { name: name, param: param };
}

function question(id: string): ContentDestination {
  return { name: P1DestinationName.QUESTION, id: id };
}

function answer(id: string): ContentDestination {
  return { name: P1DestinationName.ANSWER, id: id };
}

function people(id: string): ContentDestination {
  return { name: P1DestinationName.PEOPLE, id: id };
}

function feedItem(id: string, kind: FeedTargetKind = FeedTargetKind.ANSWER): FeedItem {
  return {
    id: id,
    verb: '推荐了',
    createdAt: 1,
    updatedAt: 1,
    target: {
      kind: kind,
      id: `${id}-target`,
      title: `${id} title`,
      excerpt: `${id} excerpt`,
      url: `https://www.zhihu.com/${id}`,
      voteupCount: 2,
      commentCount: 1,
      topicIds: []
    }
  };
}

function feedPage(items: Array<FeedItem>, next?: string, isEnd: boolean = false): FeedPage {
  return {
    items: items,
    cursor: {
      isEnd: isEnd,
      isStart: true,
      next: next,
      page: 0,
      total: items.length
    }
  };
}

function searchResult(contentId: string, kind: FeedTargetKind = FeedTargetKind.ANSWER): SearchResultItem {
  return {
    wrapperId: `wrapper-${contentId}`,
    kind: kind,
    contentId: contentId,
    title: `${contentId} title`,
    excerpt: `${contentId} excerpt`,
    voteupCount: 1,
    commentCount: 2,
    topicIds: []
  };
}

function searchPage(items: Array<SearchResultItem>, next?: string, isEnd: boolean = false): SearchResultPage {
  return {
    items: items,
    cursor: {
      isEnd: isEnd,
      isStart: true,
      next: next,
      page: 0,
      total: items.length
    }
  };
}

function collectionSummary(id: string, title: string): CollectionSummary {
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

function contentItem(kind: CollectionContentKind, id: string, title: string): CollectionContentItem {
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

export default function backStackStateTest(): void {
  describe('backStackStateTest', () => {
    it('deduplicatesSameTargetAtAnyStackPosition', 0, () => {
      const entries: Array<P1StackEntry> = [
        contentEntry(P1DestinationName.QUESTION, '111'),
        contentEntry(P1DestinationName.ANSWER, '222'),
        contentEntry(P1DestinationName.PEOPLE, 'alice')
      ];
      expect(findP1DestinationStackIndex(entries, question('111'))).assertEqual(0);
      expect(findP1DestinationStackIndex(entries, answer('222'))).assertEqual(1);
      expect(findP1DestinationStackIndex(entries, people('alice'))).assertEqual(2);
    });

    it('allowsDifferentParameterizedTargets', 0, () => {
      const entries: Array<P1StackEntry> = [
        contentEntry(P1DestinationName.PEOPLE, 'alice'),
        contentEntry(P1DestinationName.QUESTION, '111')
      ];
      expect(findP1DestinationStackIndex(entries, people('bob'))).assertEqual(-1);
      expect(findP1DestinationStackIndex(entries, question('222'))).assertEqual(-1);
      expect(findP1DestinationStackIndex(entries, answer('111'))).assertEqual(-1);
    });

    it('distinguishesSearchQueriesByIdentity', 0, () => {
      const arktsParam: TestDestinationParam = { name: P1DestinationName.SEARCH, query: 'arkts' };
      const entries: Array<P1StackEntry> = [
        { name: P1DestinationName.SEARCH, param: arktsParam }
      ];
      const arkts: SearchDestination = { name: P1DestinationName.SEARCH, query: 'arkts' };
      const harmonyos: SearchDestination = { name: P1DestinationName.SEARCH, query: 'harmonyos' };
      expect(findP1DestinationStackIndex(entries, arkts)).assertEqual(0);
      expect(findP1DestinationStackIndex(entries, harmonyos)).assertEqual(-1);
    });

    it('ignoresUndecodableStackEntries', 0, () => {
      const malformedParam: TestDestinationParam = { name: P1DestinationName.ANSWER };
      const entries: Array<P1StackEntry> = [
        { name: P1DestinationName.ANSWER, param: malformedParam },
        contentEntry(P1DestinationName.QUESTION, '111')
      ];
      expect(findP1DestinationStackIndex(entries, answer('missing'))).assertEqual(-1);
      expect(findP1DestinationStackIndex(entries, question('111'))).assertEqual(1);
    });

    it('deduplicatesStatelessInfrastructureDestinations', 0, () => {
      const settingsParam: TestDestinationParam = { name: P1DestinationName.SETTINGS };
      const loginParam: TestDestinationParam = { name: P1DestinationName.LOGIN };
      const entries: Array<P1StackEntry> = [
        { name: P1DestinationName.SETTINGS, param: settingsParam },
        { name: P1DestinationName.LOGIN, param: loginParam }
      ];
      const settings: InfrastructureDestination = { name: P1DestinationName.SETTINGS };
      const login: InfrastructureDestination = { name: P1DestinationName.LOGIN };
      expect(findP1DestinationStackIndex(entries, settings)).assertEqual(0);
      expect(findP1DestinationStackIndex(entries, login)).assertEqual(1);
    });

    it('returnsMinusOneForEmptyOrClearedStack', 0, () => {
      expect(findP1DestinationStackIndex([], question('111'))).assertEqual(-1);
    });

    it('keepsHomeFeedItemsAcrossReappearanceWithoutReload', 0, async () => {
      const repository = new CountingFeedRepository(feedPage([feedItem('first'), feedItem('second')], 'next'));
      const controller = new HomeFeedController(repository);
      controller.activate();
      await controller.loadInitial();
      expect(controller.snapshot().phase).assertEqual(HomeFeedPhase.READY);
      expect(controller.snapshot().items.length).assertEqual(2);

      controller.deactivate();
      controller.activate();

      expect(controller.snapshot().phase).assertEqual(HomeFeedPhase.READY);
      expect(controller.snapshot().items.length).assertEqual(2);
      expect(repository.loadCount).assertEqual(1);
    });

    it('keepsCollectionListItemsAcrossReappearanceWithoutReload', 0, async () => {
      const listPage: CollectionPage = {
        items: [collectionSummary('1', '收藏夹一'), collectionSummary('2', '收藏夹二')],
        cursor: { isEnd: true, isStart: true, page: 0, total: 2 }
      };
      const itemsPage: CollectionContentPage = {
        items: [],
        cursor: { isEnd: true, isStart: true, page: 0, total: 0 }
      };
      const repository = new CountingCollectionRepository(listPage, collectionSummary('1', '收藏夹一'), itemsPage);
      const controller = new CollectionController('alice-token', repository, new AuthenticatedSessionGateway());
      controller.activate();
      await controller.loadInitial();
      expect(controller.snapshot().phase).assertEqual(CollectionPhase.READY);
      expect(controller.snapshot().items.length).assertEqual(2);

      controller.deactivate();
      controller.activate();

      expect(controller.snapshot().phase).assertEqual(CollectionPhase.READY);
      expect(controller.snapshot().items.length).assertEqual(2);
      expect(repository.listLoadCount).assertEqual(1);
    });

    it('keepsCollectionContentItemsAcrossReappearanceWithoutReload', 0, async () => {
      const listPage: CollectionPage = {
        items: [],
        cursor: { isEnd: true, isStart: true, page: 0, total: 0 }
      };
      const itemsPage: CollectionContentPage = {
        items: [contentItem(CollectionContentKind.ANSWER, '1', '回答一')],
        cursor: { isEnd: true, isStart: true, page: 0, total: 1 }
      };
      const repository = new CountingCollectionRepository(listPage, collectionSummary('100', '我的收藏'), itemsPage);
      const controller = new CollectionContentController('100', repository, new AuthenticatedSessionGateway());
      controller.activate();
      await controller.loadInitial();
      expect(controller.snapshot().phase).assertEqual(CollectionContentPhase.READY);
      expect(controller.snapshot().items.length).assertEqual(1);

      controller.deactivate();
      controller.activate();

      expect(controller.snapshot().phase).assertEqual(CollectionContentPhase.READY);
      expect(controller.snapshot().items.length).assertEqual(1);
      expect(repository.detailLoadCount).assertEqual(1);
      expect(repository.itemsLoadCount).assertEqual(1);
    });

    it('keepsSearchResultsAcrossReappearanceWithoutReload', 0, async () => {
      const repository = new CountingSearchRepository(searchPage([searchResult('answer-1')], undefined, true));
      const controller = new SearchController(repository);
      controller.activate();
      await controller.submit('arkts');
      expect(controller.snapshot().phase).assertEqual(SearchPhase.READY);
      expect(controller.snapshot().items.length).assertEqual(1);

      controller.deactivate();
      controller.activate();

      expect(controller.snapshot().phase).assertEqual(SearchPhase.READY);
      expect(controller.snapshot().items.length).assertEqual(1);
      expect(repository.searchCount).assertEqual(1);
    });
  });
}

