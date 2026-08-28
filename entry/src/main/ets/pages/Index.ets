import { P1Destination, P1DestinationName } from 'core';
import {
  AppPreferencesStore,
  BlockedFeedHistoryStore,
  BlockingRuleMatcher,
  BlockingRuleStore,
  ChannelFeedRepository,
  ChannelFeedSource,
  CollectionRepository,
  CommentRepository,
  ContentDraftStore,
  ContentRepository,
  DefaultChannelFeedRepository,
  DefaultCollectionRepository,
  DefaultCommentRepository,
  DefaultCreationPublishRepository,
  DefaultContentRepository,
  DefaultDailyStoryRepository,
  DefaultFeedRepository,
  DefaultFollowRepository,
  DefaultPeopleContentRepository,
  DefaultPeopleRepository,
  DefaultPinRepository,
  DefaultPinPublishRepository,
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
  DraftRepository,
  EncryptedDraftBodyStore,
  ExistingAnswerForEditing,
  ImageUploadSource,
  AnswerPublishRepository,
  PinPublishRepository,
  VoteRepository,
  ZhihuHttpClient
} from 'data';
import { BackgroundTaskProbePage } from './BackgroundTaskProbe';
import { DatabaseProbePage } from './DatabaseProbe';
import { DeepLinkProbePage } from './DeepLinkProbe';
import { DomainFixtureProbe } from './DomainFixtureProbe';
import { P1Shell } from './P1Shell';
import { QrScanProbePage } from './QrScanProbe';
import { QrDesktopLoginScanPage } from './QrDesktopLoginScanPage';
import { ReaderProbe } from './ReaderProbe';
import { ImageProbe } from './ImageProbe';
import { TechnicalLabPage } from './TechnicalLabPage';
import { HomeFeedPage } from './HomeFeedPage';
import { SearchPage } from './SearchPage';
import { AnswerDetailPage, ArticleDetailPage, QuestionDetailPage } from './ContentDetailPages';
import { VideoPlaybackPage } from './VideoPlaybackPage';
import {
  AnswerPublishPage,
  AnswerPublishImageUploaderFactory,
  AnswerPublishPageControllerFactory,
  LocalDraftAnswerPublishControllerFactory,
  SeededAnswerPublishRepository
} from './AnswerPublishPage';
import {
  LocalDraftPinPublishPageConfigurationFactory,
  PinDraftResumeListGateway,
  PinPublishPage,
  PinPublishPageConfigurationFactory
} from './PinPublishPage';
import { PinDraftInboxPage } from './PinDraftInboxPage';
import { LoginPage } from './LoginPage';
import { ChannelFeedPage } from './ChannelFeedPage';
import { FollowingFeedPage } from './FollowingFeedPage';
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
import { ProductionImageAttachmentUploaderFactory } from '../platform/SystemImageUploadPlatform';

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
  @State private followingRecommendRepository?: ChannelFeedRepository = undefined;
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
  @State private commentRepository?: CommentRepository = undefined;
  @State private notificationRepository?: NotificationRepository = undefined;
  @State private notificationSettings?: NotificationSettingsGateway = undefined;
  private answerPublishFactory: AnswerPublishPageControllerFactory | undefined = undefined;
  private answerImageUploaderFactory: AnswerPublishImageUploaderFactory | undefined = undefined;
  private pinPublishFactory: PinPublishPageConfigurationFactory | undefined = undefined;
  private pinDraftResumeGateway: PinDraftResumeListGateway | undefined = undefined;

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
    const draftRepository = new DraftRepository(new ContentDraftStore(getAppDatabase(context)),
      new EncryptedDraftBodyStore(context));
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
      this.followingRecommendRepository = new DefaultChannelFeedRepository(new ZhihuHttpClient(session), blockingMatcher);
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
      this.commentRepository = new DefaultCommentRepository(new ZhihuHttpClient(session));
      this.notificationRepository = new DefaultNotificationRepository(new ZhihuHttpClient(session));
      this.notificationSettings = new AppPreferencesStore(context);
      this.answerPublishFactory = new LocalDraftAnswerPublishControllerFactory(session, draftRepository,
        (editSeed: ExistingAnswerForEditing | undefined): AnswerPublishRepository =>
          new SeededAnswerPublishRepository(new DefaultCreationPublishRepository(new ZhihuHttpClient(session)), editSeed));
      const imageUploaders = new ProductionImageAttachmentUploaderFactory(context.cacheDir, session);
      this.answerImageUploaderFactory = () => imageUploaders.create(ImageUploadSource.ANSWER);
      const pinPublishFactory = new LocalDraftPinPublishPageConfigurationFactory(session, draftRepository,
        (): PinPublishRepository => new DefaultPinPublishRepository(new ZhihuHttpClient(session)),
        () => imageUploaders.create(ImageUploadSource.PIN));
      this.pinPublishFactory = pinPublishFactory;
      this.pinDraftResumeGateway = pinPublishFactory;
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
          followingContent: (reloadToken: number, navigate: (destination: P1Destination) => void): void =>
            this.followingContent(reloadToken, navigate),
          hotContent: (reloadToken: number, navigate: (destination: P1Destination) => void): void =>
            this.hotContent(reloadToken, navigate),
          dailyContent: (reloadToken: number, navigate: (destination: P1Destination) => void): void =>
            this.dailyContent(reloadToken, navigate),
          dailyStoryContent: (id: string, navigate: (destination: P1Destination) => void): void =>
            this.dailyStoryContent(id, navigate),
          searchContent: (query: string, navigate: (destination: P1Destination) => void, onBack: () => void): void =>
            this.searchContent(query, navigate, onBack),
          questionContent: (id: string, navigate: (destination: P1Destination) => void, onBack: () => void): void =>
            this.questionContent(id, navigate, onBack),
          answerContent: (id: string, navigate: (destination: P1Destination) => void, onBack: () => void): void =>
            this.answerContent(id, navigate, onBack),
          articleContent: (id: string, navigate: (destination: P1Destination) => void, onBack: () => void): void =>
            this.articleContent(id, navigate, onBack),
          videoContent: (id: string, navigate: (destination: P1Destination) => void, onBack: () => void): void =>
            this.videoContent(id, navigate, onBack),
          writeAnswerContent: (questionId: string, answerId: string | undefined,
            navigate: (destination: P1Destination) => void, onBack: () => void): void =>
            this.writeAnswerContent(questionId, answerId, navigate, onBack),
          writePinContent: (draftId: string, navigate: (destination: P1Destination) => void,
            onBack: () => void): void => this.writePinContent(draftId, navigate, onBack),
          pinDraftInboxContent: (navigate: (destination: P1Destination) => void, onBack: () => void): void =>
            this.pinDraftInboxContent(navigate, onBack),
          peopleContent: (id: string, navigate: (destination: P1Destination) => void,
            onBack: () => void): void => this.peopleContent(id, navigate, onBack),
          pinContent: (id: string, navigate: (destination: P1Destination) => void, onBack: () => void): void =>
            this.pinContent(id, navigate, onBack),
          collectionsContent: (id: string, navigate: (destination: P1Destination) => void,
            onBack: () => void): void => this.collectionsContent(id, navigate, onBack),
          collectionContentContent: (id: string, navigate: (destination: P1Destination) => void,
            onBack: () => void): void => this.collectionContentContent(id, navigate, onBack),
          notificationContent: (navigate: (destination: P1Destination) => void): void =>
            this.notificationContent(navigate),
          notificationSettingsContent: (navigate: (destination: P1Destination) => void): void =>
            this.notificationSettingsContent(navigate),
          blockingRulesContent: (onBack: () => void): void => this.blockingRulesContent(onBack),
          blockedFeedHistoryContent: (onBack: () => void): void => this.blockedFeedHistoryContent(onBack),
          readHistoryContent: (navigate: (destination: P1Destination) => void, onBack: () => void): void =>
            this.readHistoryContent(navigate, onBack),
          loginContent: (onBack: () => void, onAuthenticated: () => void, onScanDesktopLogin: () => void): void =>
            this.loginContent(onBack, onAuthenticated, onScanDesktopLogin),
          technicalLabContent: (navigate: (destination: P1Destination) => void): void =>
            this.technicalLabContent(navigate),
          readerProbeContent: (onBack: () => void): void => this.readerProbeContent(onBack),
          imageProbeContent: (onBack: () => void): void => this.imageProbeContent(onBack),
          databaseProbeContent: (onBack: () => void): void => this.databaseProbeContent(onBack),
          deepLinkProbeContent: (onBack: () => void): void => this.deepLinkProbeContent(onBack),
          qrScanProbeContent: (onBack: () => void): void => this.qrScanProbeContent(onBack),
          qrDesktopLoginScanContent: (onBack: () => void): void => this.qrDesktopLoginScanContent(onBack),
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
  followingContent(reloadToken: number, navigate: (destination: P1Destination) => void) {
    FollowingFeedPage({
      recommendRepository: this.followingRecommendRepository,
      dynamicRepository: this.followingRepository,
      reloadToken: reloadToken,
      navigate: navigate,
      rules: this.blockingRuleStore,
      history: this.blockedFeedHistoryStore
    });
  }

  @Builder
  hotContent(reloadToken: number, navigate: (destination: P1Destination) => void) {
    ChannelFeedPage({
      source: ChannelFeedSource.HOT,
      repository: this.hotRepository,
      reloadToken: reloadToken,
      navigate: navigate,
      rules: this.blockingRuleStore,
      history: this.blockedFeedHistoryStore
    });
  }

  @Builder
  dailyContent(reloadToken: number, navigate: (destination: P1Destination) => void) {
    ChannelFeedPage({
      source: ChannelFeedSource.DAILY,
      repository: this.dailyRepository,
      dailyStoryRepository: this.dailyStoryRepository,
      reloadToken: reloadToken,
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
  searchContent(query: string, navigate: (destination: P1Destination) => void, onBack: () => void) {
    SearchPage({
      initialQuery: query,
      repository: this.searchRepository,
      navigate: navigate,
      onBack: onBack
    });
  }

  @Builder
  questionContent(id: string, navigate: (destination: P1Destination) => void, onBack: () => void) {
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
      session: this.session,
      onBack: onBack
    });
  }

  @Builder
  answerContent(id: string, navigate: (destination: P1Destination) => void, onBack: () => void) {
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
      commentRepository: this.commentRepository,
      session: this.session,
      onBack: onBack
    });
  }

  @Builder
  articleContent(id: string, navigate: (destination: P1Destination) => void, onBack: () => void) {
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
      commentRepository: this.commentRepository,
      session: this.session,
      onBack: onBack
    });
  }

  @Builder
  videoContent(id: string, _navigate: (destination: P1Destination) => void, onBack: () => void) {
    VideoPlaybackPage({ contentId: id, onBack: onBack });
  }

  @Builder
  writeAnswerContent(questionId: string, answerId: string | undefined,
    navigate: (destination: P1Destination) => void, onBack: () => void) {
    AnswerPublishPage({
      questionId: questionId,
      answerId: answerId,
      session: this.session,
      controllerFactory: this.answerPublishFactory,
      imageUploaderFactory: this.answerImageUploaderFactory,
      onGoLogin: (): void => {
        navigate({ name: P1DestinationName.LOGIN });
      },
      onBack: onBack
    });
  }

  @Builder
  writePinContent(draftId: string, navigate: (destination: P1Destination) => void, onBack: () => void) {
    PinPublishPage({
      draftId: draftId,
      configurationFactory: this.pinPublishFactory,
      session: this.session,
      onBack: onBack,
      onLoginRequired: (): void => {
        navigate({ name: P1DestinationName.LOGIN });
      },
      onPublished: (contentId: string): void => {
        navigate({ name: P1DestinationName.PIN, id: contentId });
      }
    });
  }

  @Builder
  pinDraftInboxContent(navigate: (destination: P1Destination) => void, onBack: () => void) {
    PinDraftInboxPage({
      gateway: this.pinDraftResumeGateway,
      session: this.session,
      onBack: onBack,
      onOpen: (draftId: string): void => {
        navigate({ name: P1DestinationName.WRITE_PIN, draftId: draftId });
      },
      onGoLogin: (): void => {
        navigate({ name: P1DestinationName.LOGIN });
      }
    });
  }

  @Builder
  peopleContent(id: string, navigate: (destination: P1Destination) => void, onBack: () => void) {
    PeopleDetailPage({
      identifier: id,
      repository: this.peopleRepository,
      contentRepository: this.peopleContentRepository,
      followRepository: this.followRepository,
      session: this.session,
      navigate: navigate,
      onBack: onBack,
      rules: this.blockingRuleStore,
      history: this.blockedFeedHistoryStore
    });
  }

  @Builder
  pinContent(id: string, navigate: (destination: P1Destination) => void, onBack: () => void) {
    PinDetailPage({
      contentId: id,
      repository: this.pinRepository,
      session: this.session,
      openedContentStore: this.openedContentStore,
      navigate: navigate,
      rules: this.blockingRuleStore,
      history: this.blockedFeedHistoryStore,
      onBack: onBack
    });
  }

  @Builder
  collectionsContent(id: string, navigate: (destination: P1Destination) => void, onBack: () => void) {
    CollectionPage({
      identifier: id,
      repository: this.collectionRepository,
      session: this.session,
      navigate: navigate,
      onBack: onBack
    });
  }

  @Builder
  collectionContentContent(id: string, navigate: (destination: P1Destination) => void, onBack: () => void) {
    CollectionContentPage({
      collectionId: id,
      repository: this.collectionRepository,
      session: this.session,
      navigate: navigate,
      onBack: onBack
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
  blockingRulesContent(onBack: () => void) {
    BlockingRulesPage({ rules: this.blockingRuleStore, preferences: this.preferencesStore, onBack: onBack });
  }

  @Builder
  blockedFeedHistoryContent(onBack: () => void) {
    BlockedFeedHistoryPage({ history: this.blockedFeedHistoryStore, onBack: onBack });
  }

  @Builder
  readHistoryContent(navigate: (destination: P1Destination) => void, onBack: () => void) {
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
      },
      onBack: onBack
    });
  }

  @Builder
  loginContent(onBack: () => void, onAuthenticated: () => void, onScanDesktopLogin: () => void) {
    LoginPage({
      onBack: onBack,
      onAuthenticated: onAuthenticated,
      onScanDesktopLogin: onScanDesktopLogin
    });
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
  qrDesktopLoginScanContent(onBack: () => void) {
    QrDesktopLoginScanPage({ onBack: onBack });
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
