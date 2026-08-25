import { describe, expect, it } from '@ohos/hypium';
import {
  ContentDraftIdentity,
  ContentDraftKind,
  ContentDraftMetadata,
  ContentDraftMetadataStore,
  ContentDraftSaveInput,
  DraftBodyStore,
  DraftRepository,
  LoginSessionGateway,
  PinPublishInput,
  PinPublishRepository,
  PinTopicSuggestion,
  PublishFailure,
  PublishFailureKind,
  SessionCookie,
  SessionLoginOperation,
  SessionState,
  SessionStatus
} from 'data';
import {
  PIN_PAGE_CANCELLED_MESSAGE,
  PIN_PAGE_LOGIN_REQUIRED_MESSAGE,
  PinPublishPageController,
  PinPublishPagePhase,
  PinPublishPageViewState
} from '../main/ets/pages/PinPublishPageState';
import {
  LocalDraftOnlyPinPublishRepository,
  LocalDraftPinPublishPageConfigurationFactory
} from '../main/ets/pages/PinPublishPage';
import { PinPublishTraceIdFactory, PinTopicSearchScheduler } from '../main/ets/pages/PinPublishState';

const ACCOUNT_KEY: string = 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const DRAFT_ID: string = '01234567-89ab-4cde-8fab-0123456789ab';
const SECOND_DRAFT_ID: string = 'fedcba98-7654-4cde-8fab-0123456789ab';
const SECRET_BODY: string = '不得泄露的正文内容';

class FakeMetadataStore implements ContentDraftMetadataStore {
  find(_identity: ContentDraftIdentity): Promise<ContentDraftMetadata | undefined> {
    return Promise.resolve(undefined);
  }

  listForAccount(_accountKey: string): Promise<Array<ContentDraftMetadata>> {
    return Promise.resolve([]);
  }

  upsert(_metadata: ContentDraftMetadata): Promise<void> {
    return Promise.resolve();
  }

  remove(_identity: ContentDraftIdentity): Promise<void> {
    return Promise.resolve();
  }
}

class FakeBodyStore implements DraftBodyStore {
  save(_draftKey: string, _html: string): Promise<void> {
    return Promise.resolve();
  }

  load(_draftKey: string): Promise<string | undefined> {
    return Promise.resolve(undefined);
  }

  remove(_draftKey: string): Promise<void> {
    return Promise.resolve();
  }
}

class FakeDraftRepository extends DraftRepository {
  readonly saves: Array<ContentDraftSaveInput> = [];
  resumeMetadata: Array<ContentDraftMetadata> = [];

  constructor() {
    super(new FakeMetadataStore(), new FakeBodyStore());
  }

  save(input: ContentDraftSaveInput, _now?: number): Promise<ContentDraftMetadata> {
    this.saves.push(input);
    const metadata: ContentDraftMetadata = {
      draftKey: input.draftKey,
      accountKey: input.accountKey,
      kind: input.kind,
      targetId: input.targetId,
      remoteContentId: input.remoteContentId,
      title: input.title,
      plainTextLength: input.plainTextLength,
      tocEnabled: input.tocEnabled,
      imageRefsJson: input.imageRefsJson,
      topicRefsJson: input.topicRefsJson,
      dirty: input.dirty,
      version: this.saves.length,
      createdAt: 1,
      updatedAt: 1
    };
    return Promise.resolve(metadata);
  }

  listMetadataForAccount(_accountKey: string): Promise<Array<ContentDraftMetadata>> {
    return Promise.resolve(this.resumeMetadata.slice());
  }
}

class FakePinRepository implements PinPublishRepository {
  readonly calls: Array<string> = [];
  cancelCount: number = 0;

  recommendTopics(_query: string, _title: string, _contentHtml: string): Promise<Array<PinTopicSuggestion>> {
    this.calls.push('topics');
    return Promise.resolve([]);
  }

  saveRemoteDraft(_input: PinPublishInput): Promise<void> {
    this.calls.push('remote-draft');
    return Promise.resolve();
  }

  publish(_input: PinPublishInput): Promise<string> {
    this.calls.push('publish');
    return Promise.resolve('701');
  }

  cancel(): void {
    this.cancelCount += 1;
  }
}

class FakeSessionLoginOperation implements SessionLoginOperation {
  readonly result: Promise<SessionState>;

  constructor(state: SessionState) {
    this.result = Promise.resolve(state);
  }

  cancel(): void {
  }
}

class FakeSession implements LoginSessionGateway {
  private readonly state: SessionState;

  constructor(status: SessionStatus) {
    this.state = {
      status: status,
      message: 'fixed session state',
      hasRetainedCredentials: status === SessionStatus.AUTHENTICATED,
      profile: status === SessionStatus.AUTHENTICATED
        ? { id: 'member-1', name: '测试用户', userType: 'people', avatarUrl: '' }
        : undefined
    };
  }

  getState(): SessionState {
    return this.state;
  }

  retryRetainedSession(): Promise<SessionState> {
    return Promise.resolve(this.state);
  }

  beginLoginWithCookieHeader(_rawCookie: string): SessionLoginOperation {
    return this.operation();
  }

  beginLoginWithCookies(_cookies: Array<SessionCookie>): SessionLoginOperation {
    return this.operation();
  }

  logout(): Promise<SessionState> {
    return Promise.resolve(this.state);
  }

  private operation(): SessionLoginOperation {
    return new FakeSessionLoginOperation(this.state);
  }
}

class FixedTraceIds implements PinPublishTraceIdFactory {
  createTraceId(): string {
    return '1770000000000,01234567-89ab-4cde-8fab-0123456789ab';
  }
}

class FakeTopicScheduler implements PinTopicSearchScheduler {
  schedule(_delayMs: number, _callback: () => void): number {
    return 1;
  }

  cancel(_handle: number): void {
  }
}

function identity(): ContentDraftIdentity {
  return {
    draftKey: `pin:${ACCOUNT_KEY}:${DRAFT_ID}`,
    accountKey: ACCOUNT_KEY,
    kind: ContentDraftKind.PIN,
    targetId: DRAFT_ID
  };
}

function resumeMetadata(draftId: string, title: string, updatedAt: number, dirty: boolean,
  kind: ContentDraftKind = ContentDraftKind.PIN): ContentDraftMetadata {
  return {
    draftKey: `${kind}:${ACCOUNT_KEY}:${draftId}`,
    accountKey: ACCOUNT_KEY,
    kind: kind,
    targetId: draftId,
    title: title,
    plainTextLength: 1,
    tocEnabled: false,
    imageRefsJson: '[]',
    topicRefsJson: '[]',
    dirty: dirty,
    version: 1,
    createdAt: 1,
    updatedAt: updatedAt
  };
}

function controller(session: SessionStatus, repository: FakePinRepository, drafts: FakeDraftRepository,
  observer: (state: PinPublishPageViewState) => void = (_state: PinPublishPageViewState): void => {},
  onPublished: (contentId: string) => void = (_contentId: string): void => {}): PinPublishPageController {
  return new PinPublishPageController(repository, drafts, new FakeSession(session), identity(), new FixedTraceIds(),
    new FakeTopicScheduler(), observer, onPublished);
}

export default function pinPublishPageStateTest(): void {
  describe('pinPublishPageStateTest', () => {
    it('doesNotAllowGuestEditsSavesOrPublishesAndUsesFixedLoginMessage', 0, async () => {
      const repository = new FakePinRepository();
      const drafts = new FakeDraftRepository();
      const messages: Array<string> = [];
      const page = controller(SessionStatus.GUEST, repository, drafts, (state: PinPublishPageViewState): void => {
        messages.push(state.message);
      });
      page.activate();
      page.updateHtml(SECRET_BODY);
      await page.saveLocalDraft();
      await page.publishPin();

      expect(page.snapshot().phase).assertEqual(PinPublishPagePhase.LOGIN_REQUIRED);
      expect(page.snapshot().message).assertEqual(PIN_PAGE_LOGIN_REQUIRED_MESSAGE);
      expect(drafts.saves.length).assertEqual(0);
      expect(repository.calls.length).assertEqual(0);
      expect(messages[messages.length - 1].includes(SECRET_BODY)).assertFalse();
    });

    it('doesNotWriteForEmptyAuthenticatedContent', 0, async () => {
      const repository = new FakePinRepository();
      const drafts = new FakeDraftRepository();
      const page = controller(SessionStatus.AUTHENTICATED, repository, drafts);
      page.activate();

      await page.publishPin();

      expect(page.snapshot().canPublish).assertFalse();
      expect(drafts.saves.length).assertEqual(0);
      expect(repository.calls.length).assertEqual(0);
    });

    it('cancelsWithoutWritingAndRemovesContentFromReleasedObservableState', 0, async () => {
      const repository = new FakePinRepository();
      const drafts = new FakeDraftRepository();
      const page = controller(SessionStatus.AUTHENTICATED, repository, drafts);
      page.activate();
      page.updateHtml(SECRET_BODY);

      page.cancel();
      await page.publishPin();

      expect(page.snapshot().phase).assertEqual(PinPublishPagePhase.RELEASED);
      expect(page.snapshot().message).assertEqual(PIN_PAGE_CANCELLED_MESSAGE);
      expect(page.snapshot().content.html).assertEqual('');
      expect(drafts.saves.length).assertEqual(0);
      expect(repository.calls.length).assertEqual(0);
      expect(repository.cancelCount).assertEqual(1);
    });

    it('publishesThroughThePinStateMachineAndExposesOnlyTypedContentIdCallback', 0, async () => {
      const repository = new FakePinRepository();
      const drafts = new FakeDraftRepository();
      let publishedId: string = '';
      const page = controller(SessionStatus.AUTHENTICATED, repository, drafts,
        (_state: PinPublishPageViewState): void => {}, (contentId: string): void => {
          publishedId = contentId;
        });
      page.activate();
      page.updateTitle('P4 想法');

      await page.publishPin();

      expect(repository.calls[0]).assertEqual('remote-draft');
      expect(repository.calls[1]).assertEqual('publish');
      expect(drafts.saves.length).assertEqual(2);
      expect(publishedId).assertEqual('701');
      expect(page.snapshot().phase).assertEqual(PinPublishPagePhase.PUBLISHED);
    });

    it('buildsAuthenticatedPinCompositionWithAccountIsolatedIdentity', 0, async () => {
      const drafts = new FakeDraftRepository();
      const factory = new LocalDraftPinPublishPageConfigurationFactory(
        new FakeSession(SessionStatus.AUTHENTICATED), drafts);

      const configuration = await factory.create(DRAFT_ID);

      expect(configuration === undefined).assertFalse();
      if (configuration !== undefined) {
        expect(configuration.identity.kind).assertEqual(ContentDraftKind.PIN);
        expect(configuration.identity.targetId).assertEqual(DRAFT_ID);
        expect(configuration.identity.accountKey.startsWith('sha256:')).assertTrue();
        expect(configuration.drafts === drafts).assertTrue();
      }
    });

    it('keepsGuestAndDefaultRemotePinOperationsOutsideNetworkBoundary', 0, async () => {
      const drafts = new FakeDraftRepository();
      const guestFactory = new LocalDraftPinPublishPageConfigurationFactory(new FakeSession(SessionStatus.GUEST), drafts);
      const guestConfiguration = await guestFactory.create(DRAFT_ID);
      const repository = new LocalDraftOnlyPinPublishRepository();
      const result: Object = await repository.saveRemoteDraft({
        title: '',
        html: '仅用于验证安全默认实现',
        textLength: 10,
        images: [],
        topics: [],
        traceId: '1770000000000,01234567-89ab-4cde-8fab-0123456789ab'
      }).then((): Object => new Error('默认远端草稿实现不应成功'), (error: Error): Object => error);

      expect(guestConfiguration).assertUndefined();
      expect(result instanceof PublishFailure).assertTrue();
      if (result instanceof PublishFailure) {
        expect(result.kind).assertEqual(PublishFailureKind.SERVER);
      }
    });

    it('listsOnlyDirtyPinMetadataForDraftResume', 0, async () => {
      const drafts = new FakeDraftRepository();
      drafts.resumeMetadata = [
        resumeMetadata(DRAFT_ID, '较早想法', 100, true),
        resumeMetadata(SECOND_DRAFT_ID, '已发布草稿', 200, false),
        resumeMetadata('123', '回答不应出现', 300, true, ContentDraftKind.ANSWER)
      ];
      const factory = new LocalDraftPinPublishPageConfigurationFactory(
        new FakeSession(SessionStatus.AUTHENTICATED), drafts);

      const items = await factory.listResumeItems();

      expect(items.length).assertEqual(1);
      expect(items[0].draftId).assertEqual(DRAFT_ID);
      expect(items[0].title).assertEqual('较早想法');
    });
  });
}
