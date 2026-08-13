import { P1Destination, P1DestinationName } from 'core';
import {
  AppPreferencesStore,
  BlockingRuleMatcher,
  BlockingRuleStore,
  ChannelFeedRepository,
  ChannelFeedSource,
  ContentRepository,
  DefaultChannelFeedRepository,
  DefaultContentRepository,
  DefaultDailyStoryRepository,
  DefaultFeedRepository,
  DefaultPeopleContentRepository,
  DefaultPeopleRepository,
  DefaultPinRepository,
  DefaultSearchRepository,
  FeedRepository,
  getAppDatabase,
  getAppSessionOwner,
  OpenedContentStore,
  PeopleContentRepository,
  PeopleDetailRepository,
  PinRepository,
  SearchRepository,
  SessionRepository,
  DailyStoryRepository,
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
import { ReadHistoryPage } from './ReadHistoryPage';
import { ReadHistoryContentKind, ReadHistoryOpenTarget } from './ReadHistoryState';

@Entry
@Component
struct Index {
  private session?: SessionRepository;
  private openedContentStore?: OpenedContentStore;
  private blockingRuleStore?: BlockingRuleStore;
  private preferencesStore?: AppPreferencesStore;
  private homeRepository?: FeedRepository;
  private searchRepository?: SearchRepository;
  private followingRepository?: ChannelFeedRepository;
  private hotRepository?: ChannelFeedRepository;
  private dailyRepository?: ChannelFeedRepository;
  private dailyStoryRepository?: DailyStoryRepository;
  private questionRepository?: ContentRepository;
  private answerRepository?: ContentRepository;
  private articleRepository?: ContentRepository;
  private peopleRepository?: PeopleDetailRepository;
  private peopleContentRepository?: PeopleContentRepository;
  private pinRepository?: PinRepository;

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const session = getAppSessionOwner(context).getRepository();
    const openedContentStore = new OpenedContentStore(getAppDatabase(context));
    const blockingRuleStore = new BlockingRuleStore(getAppDatabase(context));
    const preferencesStore = new AppPreferencesStore(context);
    const blockingMatcher = new BlockingRuleMatcher(blockingRuleStore, preferencesStore);
    this.session = session;
    this.openedContentStore = openedContentStore;
    this.blockingRuleStore = blockingRuleStore;
    this.preferencesStore = preferencesStore;
    this.homeRepository = new DefaultFeedRepository(new ZhihuHttpClient(), blockingMatcher);
    this.searchRepository = new DefaultSearchRepository(new ZhihuHttpClient(session), blockingMatcher);
    this.followingRepository = new DefaultChannelFeedRepository(new ZhihuHttpClient(session), blockingMatcher);
    this.hotRepository = new DefaultChannelFeedRepository(new ZhihuHttpClient(), blockingMatcher);
    this.dailyRepository = new DefaultChannelFeedRepository(new ZhihuHttpClient(), blockingMatcher);
    this.dailyStoryRepository = new DefaultDailyStoryRepository(new ZhihuHttpClient());
    this.questionRepository = new DefaultContentRepository(new ZhihuHttpClient(session));
    this.answerRepository = new DefaultContentRepository(new ZhihuHttpClient(session));
    this.articleRepository = new DefaultContentRepository(new ZhihuHttpClient(session));
    this.peopleRepository = new DefaultPeopleRepository(new ZhihuHttpClient(session));
    this.peopleContentRepository = new DefaultPeopleContentRepository(new ZhihuHttpClient(session));
    this.pinRepository = new DefaultPinRepository(new ZhihuHttpClient(session));
  }

  build() {
    Stack() {
      P1Shell({
        homeContent: this.homeContent,
        followingContent: this.followingContent,
        hotContent: this.hotContent,
        dailyContent: this.dailyContent,
        dailyStoryContent: this.dailyStoryContent,
        searchContent: this.searchContent,
        questionContent: this.questionContent,
        answerContent: this.answerContent,
        articleContent: this.articleContent,
        peopleContent: this.peopleContent,
        pinContent: this.pinContent,
        blockingRulesContent: this.blockingRulesContent,
        readHistoryContent: this.readHistoryContent,
        loginContent: this.loginContent,
        technicalLabContent: this.technicalLabContent,
        readerProbeContent: this.readerProbeContent,
        imageProbeContent: this.imageProbeContent,
        databaseProbeContent: this.databaseProbeContent,
        deepLinkProbeContent: this.deepLinkProbeContent,
        qrScanProbeContent: this.qrScanProbeContent,
        backgroundTaskProbeContent: this.backgroundTaskProbeContent,
        domainFixtureProbeContent: this.domainFixtureProbeContent
      });
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  homeContent(navigate: (destination: P1Destination) => void) {
    HomeFeedPage({ repository: this.homeRepository, navigate: navigate });
  }

  @Builder
  followingContent(navigate: (destination: P1Destination) => void) {
    ChannelFeedPage({
      source: ChannelFeedSource.FOLLOWING,
      repository: this.followingRepository,
      navigate: navigate
    });
  }

  @Builder
  hotContent(navigate: (destination: P1Destination) => void) {
    ChannelFeedPage({ source: ChannelFeedSource.HOT, repository: this.hotRepository, navigate: navigate });
  }

  @Builder
  dailyContent(navigate: (destination: P1Destination) => void) {
    ChannelFeedPage({ source: ChannelFeedSource.DAILY, repository: this.dailyRepository, navigate: navigate });
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
      navigate: navigate
    });
  }

  @Builder
  answerContent(id: string, navigate: (destination: P1Destination) => void) {
    AnswerDetailPage({
      contentId: id,
      repository: this.answerRepository,
      openedContentStore: this.openedContentStore,
      navigate: navigate
    });
  }

  @Builder
  articleContent(id: string, navigate: (destination: P1Destination) => void) {
    ArticleDetailPage({
      contentId: id,
      repository: this.articleRepository,
      openedContentStore: this.openedContentStore,
      navigate: navigate
    });
  }

  @Builder
  peopleContent(id: string, navigate: (destination: P1Destination) => void) {
    PeopleDetailPage({
      identifier: id,
      repository: this.peopleRepository,
      contentRepository: this.peopleContentRepository,
      session: this.session,
      navigate: navigate
    });
  }

  @Builder
  pinContent(id: string, navigate: (destination: P1Destination) => void) {
    PinDetailPage({
      contentId: id,
      repository: this.pinRepository,
      session: this.session,
      openedContentStore: this.openedContentStore,
      navigate: navigate
    });
  }

  @Builder
  blockingRulesContent() {
    BlockingRulesPage({ rules: this.blockingRuleStore, preferences: this.preferencesStore });
  }

  @Builder
  readHistoryContent(navigate: (destination: P1Destination) => void) {
    ReadHistoryPage({
      history: this.openedContentStore,
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
