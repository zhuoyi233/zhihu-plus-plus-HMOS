import { P1Destination, P1DestinationName } from 'core';
import {
  AppPreferencesStore,
  BlockedFeedHistoryStore,
  BlockingRuleMatcher,
  BlockingRuleStore,
  ChannelFeedRepository,
  ChannelFeedSource,
  CollectionRepository,
  ContentRepository,
  DefaultChannelFeedRepository,
  DefaultCollectionRepository,
  DefaultContentRepository,
  DefaultDailyStoryRepository,
  DefaultFeedRepository,
  DefaultFollowRepository,
  DefaultPeopleContentRepository,
  DefaultPeopleRepository,
  DefaultPinRepository,
  DefaultSearchRepository,
  DefaultOnlineHistoryRepository,
  DefaultNotificationRepository,
  DefaultVoteRepository,
  FeedRepository,
  FollowRepository,
  getAppDatabase,
  getAppSessionOwner,
  NotificationRepository,
  NotificationSettingsGateway,
  OpenedContentStore,
  OnlineHistoryRepository,
  PeopleContentRepository,
  PeopleDetailRepository,
  PinRepository,
  SearchRepository,
  SessionRepository,
  DailyStoryRepository,
  VoteRepository,
  ZhihuHttpClient
} from 'data';
import { BackgroundTaskProbePage } from './BackgroundTaskProbe';
import { DatabaseProbePage } from './DatabaseProbe';
import { DeepLinkProbePage } from './DeepLinkProbe';
import { DomainFixtureProbe } from './DomainFixtureProbe';
import { P1Shell } from './P1Shell';
import { QrScanProbePage } from './QrScanProbe';
import { ReaderProbe } from './ReaderProbe';
import { ImageProbe } from './ImageProbe';
import { TechnicalLabPage } from './TechnicalLabPage';
import { HomeFeedPage } from './HomeFeedPage';
import { SearchPage } from './SearchPage';
import { AnswerDetailPage, ArticleDetailPage, QuestionDetailPage } from './ContentDetailPages';
import { LoginPage } from './LoginPage';
import { ChannelFeedPage } from './ChannelFeedPage';
import { DailyStoryDetailPage } from './DailyStoryDetailPage';
import { PeopleDetailPage, PinDetailPage } from './PeoplePinDetailPages';
import { BlockingRulesPage } from './BlockingRulesPage';
import { BlockedFeedHistoryPage } from './BlockedFeedHistoryPage';
import { ReadHistoryPage } from './ReadHistoryPage';
import { CollectionPage } from './CollectionPage';
import { CollectionContentPage } from './CollectionContentPage';
import { NotificationPage } from './NotificationPage';
import { NotificationSettingsPage } from './NotificationSettingsPage';
import { ReadHistoryContentKind, ReadHistoryOpenTarget } from './ReadHistoryState';

@Entry
@Component
struct Index {
  @State private compositionReady: boolean = false;
  @State private compositionPreparing: boolean = false;
  @State private session?: SessionRepository = undefined;
  @State private openedContentStore?: OpenedContentStore = undefined;
  @State private blockingRuleStore?: BlockingRuleStore = undefined;
  @State private blockedFeedHistoryStore?: BlockedFeedHistoryStore = undefined;
  @State private preferencesStore?: AppPreferencesStore = undefined;
  @State private homeRepository?: FeedRepository = undefined;
  @State private searchRepository?: SearchRepository = undefined;
  @State private followingRepository?: ChannelFeedRepository = undefined;
  @State private hotRepository?: ChannelFeedRepository = undefined;
  @State private dailyRepository?: ChannelFeedRepository = undefined;
  @State private dailyStoryRepository?: DailyStoryRepository = undefined;
  @State private questionRepository?: ContentRepository = undefined;
  @State private answerRepository?: ContentRepository = undefined;
  @State private articleRepository?: ContentRepository = undefined;
  @State private peopleRepository?: PeopleDetailRepository = undefined;
  @State private peopleContentRepository?: PeopleContentRepository = undefined;
  @State private pinRepository?: PinRepository = undefined;
  @State private onlineHistoryRepository?: OnlineHistoryRepository = undefined;
  @State private voteRepository?: VoteRepository = undefined;
  @State private followRepository?: FollowRepository = undefined;
  @State private collectionRepository?: CollectionRepository = undefined;
  @State private notificationRepository?: NotificationRepository = undefined;
  @State private notificationSettings?: NotificationSettingsGateway = undefined;

  aboutToAppear(): void {
    if (this.compositionReady || this.compositionPreparing) {
      return;
    }
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    this.compositionPreparing = true;
    const sessionOwner = getAppSessionOwner(context);
    const session = sessionOwner.getRepository();
    const openedContentStore = new OpenedContentStore(getAppDatabase(context));
    const blockingRuleStore = new BlockingRuleStore(getAppDatabase(context));
    const blockedFeedHistoryStore = new BlockedFeedHistoryStore(getAppDatabase(context));
    const preferencesStore = new AppPreferencesStore(context);
    const blockingMatcher = new BlockingRuleMatcher(blockingRuleStore, preferencesStore);
    sessionOwner.restoreDeferred().catch((_error: Error): void => {
    }).then((): void => {
      this.session = session;
      this.openedContentStore = openedContentStore;
      this.blockingRuleStore = blockingRuleStore;
      this.blockedFeedHistoryStore = blockedFeedHistoryStore;
      this.preferencesStore = preferencesStore;
      this.homeRepository = new DefaultFeedRepository(new ZhihuHttpClient(session), blockingMatcher);
      this.searchRepository = new DefaultSearchRepository(new ZhihuHttpClient(session), blockingMatcher);
      this.followingRepository = new DefaultChannelFeedRepository(new ZhihuHttpClient(session), blockingMatcher);
      this.hotRepository = new DefaultChannelFeedRepository(new ZhihuHttpClient(session), blockingMatcher);
      this.dailyRepository = new DefaultChannelFeedRepository(new ZhihuHttpClient(), blockingMatcher);
      this.dailyStoryRepository = new DefaultDailyStoryRepository(new ZhihuHttpClient());
      this.questionRepository = new DefaultContentRepository(new ZhihuHttpClient(session));
      this.answerRepository = new DefaultContentRepository(new ZhihuHttpClient(session));
      this.articleRepository = new DefaultContentRepository(new ZhihuHttpClient(session));
      this.peopleRepository = new DefaultPeopleRepository(new ZhihuHttpClient(session));
      this.peopleContentRepository = new DefaultPeopleContentRepository(new ZhihuHttpClient(session));
      this.pinRepository = new DefaultPinRepository(new ZhihuHttpClient(session));
      this.onlineHistoryRepository = new DefaultOnlineHistoryRepository(new ZhihuHttpClient(session));
      this.voteRepository = new DefaultVoteRepository(new ZhihuHttpClient(session));
      this.followRepository = new DefaultFollowRepository(new ZhihuHttpClient(session));
      this.collectionRepository = new DefaultCollectionRepository(new ZhihuHttpClient(session));
      this.notificationRepository = new DefaultNotificationRepository(new ZhihuHttpClient(session));
      this.notificationSettings = new AppPreferencesStore(context);
      this.compositionPreparing = false;
      this.compositionReady = true;
    });
  }

  build() {
    Stack() {
      if (this.compositionReady) {
        P1Shell({
          session: this.session,
          homeContent: (reloadToken: number, navigate: (destination: P1Destination) => void): void =>
            this.homeContent(reloadToken, navigate),
          followingContent: (navigate: (destination: P1Destination) => void): void => this.followingContent(navigate),
          hotContent: (navigate: (destination: P1Destination) => void): void => this.hotContent(navigate),
          dailyContent: (navigate: (destination: P1Destination) => void): void => this.dailyContent(navigate),
          dailyStoryContent: (id: string, navigate: (destination: P1Destination) => void): void =>
            this.dailyStoryContent(id, navigate),
          searchContent: (query: string, navigate: (destination: P1Destination) => void): void =>
            this.searchContent(query, navigate),
          questionContent: (id: string, navigate: (destination: P1Destination) => void): void =>
            this.questionContent(id, navigate),
          answerContent: (id: string, navigate: (destination: P1Destination) => void): void =>
            this.answerContent(id, navigate),
          articleContent: (id: string, navigate: (destination: P1Destination) => void): void =>
            this.articleContent(id, navigate),
          peopleContent: (id: string, navigate: (destination: P1Destination) => void): void =>
            this.peopleContent(id, navigate),
          pinContent: (id: string, navigate: (destination: P1Destination) => void): void => this.pinContent(id, navigate),
          collectionsContent: (id: string, navigate: (destination: P1Destination) => void): void =>
            this.collectionsContent(id, navigate),
          collectionContentContent: (id: string, navigate: (destination: P1Destination) => void): void =>
            this.collectionContentContent(id, navigate),
          notificationContent: (navigate: (destination: P1Destination) => void): void =>
            this.notificationContent(navigate),
          notificationSettingsContent: (navigate: (destination: P1Destination) => void): void =>
            this.notificationSettingsContent(navigate),
          blockingRulesContent: (): void => this.blockingRulesContent(),
          blockedFeedHistoryContent: (): void => this.blockedFeedHistoryContent(),
          readHistoryContent: (navigate: (destination: P1Destination) => void): void => this.readHistoryContent(navigate),
          loginContent: (onBack: () => void, onAuthenticated: () => void): void =>
            this.loginContent(onBack, onAuthenticated),
          technicalLabContent: (navigate: (destination: P1Destination) => void): void =>
            this.technicalLabContent(navigate),
          readerProbeContent: (onBack: () => void): void => this.readerProbeContent(onBack),
          imageProbeContent: (onBack: () => void): void => this.imageProbeContent(onBack),
          databaseProbeContent: (onBack: () => void): void => this.databaseProbeContent(onBack),
          deepLinkProbeContent: (onBack: () => void): void => this.deepLinkProbeContent(onBack),
          qrScanProbeContent: (onBack: () => void): void => this.qrScanProbeContent(onBack),
          backgroundTaskProbeContent: (onBack: () => void): void => this.backgroundTaskProbeContent(onBack),
          domainFixtureProbeContent: (onBack: () => void): void => this.domainFixtureProbeContent(onBack)
        });
      } else {
        Text('正在恢复登录状态');
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  homeContent(reloadToken: number, navigate: (destination: P1Destination) => void) {
    HomeFeedPage({
      repository: this.homeRepository,
      reloadToken: reloadToken,
      navigate: navigate,
      rules: this.blockingRuleStore,
      history: this.blockedFeedHistoryStore
    });
  }

  @Builder
  followingContent(navigate: (destination: P1Destination) => void) {
    ChannelFeedPage({
      source: ChannelFeedSource.FOLLOWING,
      repository: this.followingRepository,
      navigate: navigate,
      rules: this.blockingRuleStore,
      history: this.blockedFeedHistoryStore
    });
  }

  @Builder
  hotContent(navigate: (destination: P1Destination) => void) {
    ChannelFeedPage({
      source: ChannelFeedSource.HOT,
      repository: this.hotRepository,
      navigate: navigate,
      rules: this.blockingRuleStore,
      history: this.blockedFeedHistoryStore
    });
  }

  @Builder
  dailyContent(navigate: (destination: P1Destination) => void) {
    ChannelFeedPage({
      source: ChannelFeedSource.DAILY,
      repository: this.dailyRepository,
      navigate: navigate,
      rules: this.blockingRuleStore,
      history: this.blockedFeedHistoryStore
    });
  }

  @Builder
  dailyStoryContent(id: string, navigate: (destination: P1Destination) => void) {
    DailyStoryDetailPage({ storyId: id, repository: this.dailyStoryRepository, navigate: navigate });
  }

  @Builder
  searchContent(query: string, navigate: (destination: P1Destination) => void) {
    SearchPage({
      initialQuery: query,
      repository: this.searchRepository,
      navigate: navigate
    });
  }

  @Builder
  questionContent(id: string, navigate: (destination: P1Destination) => void) {
    QuestionDetailPage({
      contentId: id,
      repository: this.questionRepository,
      openedContentStore: this.openedContentStore,
      navigate: navigate,
      rules: this.blockingRuleStore,
      history: this.blockedFeedHistoryStore,
      voteRepository: this.voteRepository,
      followRepository: this.followRepository,
      collectionRepository: this.collectionRepository,
      session: this.session
    });
  }

  @Builder
  answerContent(id: string, navigate: (destination: P1Destination) => void) {
    AnswerDetailPage({
      contentId: id,
      repository: this.answerRepository,
      openedContentStore: this.openedContentStore,
      navigate: navigate,
      rules: this.blockingRuleStore,
      history: this.blockedFeedHistoryStore,
      voteRepository: this.voteRepository,
      followRepository: this.followRepository,
      collectionRepository: this.collectionRepository,
      session: this.session
    });
  }

  @Builder
  articleContent(id: string, navigate: (destination: P1Destination) => void) {
    ArticleDetailPage({
      contentId: id,
      repository: this.articleRepository,
      openedContentStore: this.openedContentStore,
      navigate: navigate,
      rules: this.blockingRuleStore,
      history: this.blockedFeedHistoryStore,
      voteRepository: this.voteRepository,
      followRepository: this.followRepository,
      collectionRepository: this.collectionRepository,
      session: this.session
    });
  }

  @Builder
  peopleContent(id: string, navigate: (destination: P1Destination) => void) {
    PeopleDetailPage({
      identifier: id,
      repository: this.peopleRepository,
      contentRepository: this.peopleContentRepository,
      followRepository: this.followRepository,
      session: this.session,
      navigate: navigate,
      rules: this.blockingRuleStore,
      history: this.blockedFeedHistoryStore
    });
  }

  @Builder
  pinContent(id: string, navigate: (destination: P1Destination) => void) {
    PinDetailPage({
      contentId: id,
      repository: this.pinRepository,
      session: this.session,
      openedContentStore: this.openedContentStore,
      navigate: navigate,
      rules: this.blockingRuleStore,
      history: this.blockedFeedHistoryStore
    });
  }

  @Builder
  collectionsContent(id: string, navigate: (destination: P1Destination) => void) {
    CollectionPage({
      identifier: id,
      repository: this.collectionRepository,
      session: this.session,
      navigate: navigate
    });
  }

  @Builder
  collectionContentContent(id: string, navigate: (destination: P1Destination) => void) {
    CollectionContentPage({
      collectionId: id,
      repository: this.collectionRepository,
      session: this.session,
      navigate: navigate
    });
  }

  @Builder
  notificationContent(navigate: (destination: P1Destination) => void) {
    NotificationPage({
      repository: this.notificationRepository,
      settings: this.notificationSettings,
      session: this.session,
      navigate: navigate
    });
  }

  @Builder
  notificationSettingsContent(_navigate: (destination: P1Destination) => void) {
    NotificationSettingsPage({
      settings: this.notificationSettings
    });
  }

  @Builder
  blockingRulesContent() {
    BlockingRulesPage({ rules: this.blockingRuleStore, preferences: this.preferencesStore });
  }

  @Builder
  blockedFeedHistoryContent() {
    BlockedFeedHistoryPage({ history: this.blockedFeedHistoryStore });
  }

  @Builder
  readHistoryContent(navigate: (destination: P1Destination) => void) {
    ReadHistoryPage({
      history: this.openedContentStore,
      onlineHistory: this.onlineHistoryRepository,
      session: this.session,
      onOpen: (target: ReadHistoryOpenTarget): void => {
        if (target.kind === ReadHistoryContentKind.QUESTION) {
          navigate({ name: P1DestinationName.QUESTION, id: target.id });
        } else if (target.kind === ReadHistoryContentKind.ANSWER) {
          navigate({ name: P1DestinationName.ANSWER, id: target.id });
        } else if (target.kind === ReadHistoryContentKind.ARTICLE) {
          navigate({ name: P1DestinationName.ARTICLE, id: target.id });
        } else {
          navigate({ name: P1DestinationName.PIN, id: target.id });
        }
      },
      onGoLogin: (): void => {
        navigate({ name: P1DestinationName.LOGIN });
      }
    });
  }

  @Builder
  loginContent(onBack: () => void, onAuthenticated: () => void) {
    LoginPage({ onBack: onBack, onAuthenticated: onAuthenticated });
  }

  @Builder
  technicalLabContent(navigate: (destination: P1Destination) => void) {
    TechnicalLabPage({ navigate: navigate });
  }

  @Builder
  readerProbeContent(onBack: () => void) {
    ReaderProbe({ onBack: onBack });
  }

  @Builder
  imageProbeContent(onBack: () => void) {
    ImageProbe({ onBack: onBack });
  }

  @Builder
  databaseProbeContent(onBack: () => void) {
    DatabaseProbePage({ onBack: onBack });
  }

  @Builder
  deepLinkProbeContent(onBack: () => void) {
    DeepLinkProbePage({ onBack: onBack });
  }

  @Builder
  qrScanProbeContent(onBack: () => void) {
    QrScanProbePage({ onBack: onBack });
  }

  @Builder
  backgroundTaskProbeContent(onBack: () => void) {
    BackgroundTaskProbePage({ onBack: onBack });
  }

  @Builder
  domainFixtureProbeContent(onBack: () => void) {
    DomainFixtureProbe({ onBack: onBack });
  }

}
