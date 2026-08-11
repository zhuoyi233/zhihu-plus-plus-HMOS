import { common } from '@kit.AbilityKit';
import { P1Destination } from 'core';
import {
  DefaultContentRepository,
  DefaultSearchRepository,
  getAppDatabase,
  getAppSessionOwner,
  OpenedContentStore,
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

@Entry
@Component
struct Index {
  build() {
    Stack() {
      P1Shell({
        homeContent: this.homeContent,
        searchContent: this.searchContent,
        questionContent: this.questionContent,
        answerContent: this.answerContent,
        articleContent: this.articleContent,
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
    HomeFeedPage({ navigate: navigate });
  }

  @Builder
  searchContent(query: string, navigate: (destination: P1Destination) => void) {
    SearchPage({
      initialQuery: query,
      repository: new DefaultSearchRepository(new ZhihuHttpClient(
        getAppSessionOwner(this.getUIContext().getHostContext() as common.UIAbilityContext).getRepository()
      )),
      navigate: navigate
    });
  }

  @Builder
  questionContent(id: string, navigate: (destination: P1Destination) => void) {
    QuestionDetailPage({
      contentId: id,
      repository: new DefaultContentRepository(new ZhihuHttpClient(
        getAppSessionOwner(this.getUIContext().getHostContext() as common.UIAbilityContext).getRepository()
      )),
      openedContentStore: new OpenedContentStore(
        getAppDatabase(this.getUIContext().getHostContext() as common.UIAbilityContext)
      ),
      navigate: navigate
    });
  }

  @Builder
  answerContent(id: string, navigate: (destination: P1Destination) => void) {
    AnswerDetailPage({
      contentId: id,
      repository: new DefaultContentRepository(new ZhihuHttpClient(
        getAppSessionOwner(this.getUIContext().getHostContext() as common.UIAbilityContext).getRepository()
      )),
      openedContentStore: new OpenedContentStore(
        getAppDatabase(this.getUIContext().getHostContext() as common.UIAbilityContext)
      ),
      navigate: navigate
    });
  }

  @Builder
  articleContent(id: string, navigate: (destination: P1Destination) => void) {
    ArticleDetailPage({
      contentId: id,
      repository: new DefaultContentRepository(new ZhihuHttpClient(
        getAppSessionOwner(this.getUIContext().getHostContext() as common.UIAbilityContext).getRepository()
      )),
      openedContentStore: new OpenedContentStore(
        getAppDatabase(this.getUIContext().getHostContext() as common.UIAbilityContext)
      ),
      navigate: navigate
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
