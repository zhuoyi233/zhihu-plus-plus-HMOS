import { describe, expect, it } from '@ohos/hypium';
import {
  AnswerPublishInput,
  AnswerPublishRepository,
  ContentDraftIdentity,
  ContentDraftKind,
  ContentDraftLoadStatus,
  ContentDraftMetadata,
  ContentDraftMetadataStore,
  DraftBodyStore,
  DraftRepository,
  ExistingAnswerForEditing,
  HttpFailure,
  HttpFailureKind,
  LoginSessionGateway,
  SessionCookie,
  SessionLoginOperation,
  SessionState,
  SessionStatus
} from 'data';
import {
  AnswerPublishController,
  AnswerPublishPhase,
  ANSWER_PUBLISH_CONFLICT_MESSAGE,
  ANSWER_PUBLISH_LOGIN_REQUIRED_MESSAGE,
  ANSWER_PUBLISH_RATE_LIMITED_MESSAGE,
  ANSWER_PUBLISH_VERIFICATION_MESSAGE
} from '../main/ets/pages/AnswerPublishState';

const ACCOUNT_KEY: string = 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const TRACE_ID: string = '1770000000000,01234567-89ab-4cde-8fab-0123456789ab';

class FixedSessionOperation implements SessionLoginOperation {
  readonly result: Promise<SessionState>;

  constructor(state: SessionState) {
    this.result = Promise.resolve(state);
  }

  cancel(): void {
  }
}

class FixedSessionGateway implements LoginSessionGateway {
  private readonly state: SessionState;

  constructor(status: SessionStatus) {
    this.state = {
      status: status,
      message: status === SessionStatus.AUTHENTICATED ? '已登录' : '游客模式',
      hasRetainedCredentials: status === SessionStatus.AUTHENTICATED
    };
  }

  getState(): SessionState {
    return this.state;
  }

  retryRetainedSession(): Promise<SessionState> {
    return Promise.resolve(this.state);
  }

  beginLoginWithCookieHeader(_rawCookie: string): SessionLoginOperation {
    return new FixedSessionOperation(this.state);
  }

  beginLoginWithCookies(_cookies: Array<SessionCookie>): SessionLoginOperation {
    return new FixedSessionOperation(this.state);
  }

  logout(): Promise<SessionState> {
    return Promise.resolve(this.state);
  }
}

class MemoryMetadataStore implements ContentDraftMetadataStore {
  private readonly values: Map<string, ContentDraftMetadata> = new Map<string, ContentDraftMetadata>();

  find(identity: ContentDraftIdentity): Promise<ContentDraftMetadata | undefined> {
    return Promise.resolve(this.values.get(identity.draftKey));
  }

  listForAccount(accountKey: string): Promise<Array<ContentDraftMetadata>> {
    const result: Array<ContentDraftMetadata> = [];
    this.values.forEach((value: ContentDraftMetadata): void => {
      if (value.accountKey === accountKey) {
        result.push(value);
      }
    });
    return Promise.resolve(result);
  }

  upsert(metadata: ContentDraftMetadata): Promise<void> {
    this.values.set(metadata.draftKey, metadata);
    return Promise.resolve();
  }

  remove(identity: ContentDraftIdentity): Promise<void> {
    this.values.delete(identity.draftKey);
    return Promise.resolve();
  }
}

class MemoryBodyStore implements DraftBodyStore {
  private readonly values: Map<string, string> = new Map<string, string>();

  save(draftKey: string, html: string): Promise<void> {
    this.values.set(draftKey, html);
    return Promise.resolve();
  }

  load(draftKey: string): Promise<string | undefined> {
    return Promise.resolve(this.values.get(draftKey));
  }

  remove(draftKey: string): Promise<void> {
    this.values.delete(draftKey);
    return Promise.resolve();
  }
}

class DeferredText {
  readonly result: Promise<string>;
  private resolveResult?: (value: string) => void;

  constructor() {
    this.result = new Promise<string>((resolve: (value: string) => void): void => {
      this.resolveResult = resolve;
    });
  }

  resolve(value: string): void {
    if (this.resolveResult !== undefined) {
      this.resolveResult(value);
      this.resolveResult = undefined;
    }
  }
}

class FakeAnswerPublishRepository implements AnswerPublishRepository {
  readonly calls: Array<string> = [];
  readonly remoteDraftInputs: Array<AnswerPublishInput> = [];
  readonly publishInputs: Array<AnswerPublishInput> = [];
  readonly answerIds: Array<string | undefined> = [];
  existing?: ExistingAnswerForEditing;
  remoteDraftFailure?: Object;
  publishFailure?: Object;
  publishResponse: string = '{"data":{"result":"{\\"publish\\":{\\"id\\":\\"789\\"}}"}}';
  publishDeferred?: DeferredText;
  readonly publishStarted: Promise<void>;
  private resolvePublishStarted?: () => void;
  cancelCount: number = 0;

  constructor() {
    this.publishStarted = new Promise<void>((resolve: () => void): void => {
      this.resolvePublishStarted = resolve;
    });
  }

  findMyAnswerId(_questionId: string): Promise<string | undefined> {
    this.calls.push('relationship');
    return Promise.resolve(this.answerIds.length > 0 ? this.answerIds.shift() : undefined);
  }

  fetchAnswerForEditing(answerId: string): Promise<ExistingAnswerForEditing | undefined> {
    this.calls.push(`fetch:${answerId}`);
    return Promise.resolve(this.existing);
  }

  saveRemoteDraft(input: AnswerPublishInput): Promise<void> {
    this.calls.push('remoteDraft');
    this.remoteDraftInputs.push(input);
    if (this.remoteDraftFailure !== undefined) {
      return Promise.reject(this.remoteDraftFailure);
    }
    return Promise.resolve();
  }

  publish(input: AnswerPublishInput): Promise<string> {
    this.calls.push('publish');
    this.publishInputs.push(input);
    if (this.resolvePublishStarted !== undefined) {
      this.resolvePublishStarted();
      this.resolvePublishStarted = undefined;
    }
    if (this.publishFailure !== undefined) {
      return Promise.reject(this.publishFailure);
    }
    return this.publishDeferred === undefined ? Promise.resolve(this.publishResponse) : this.publishDeferred.result;
  }

  cancel(): void {
    this.cancelCount += 1;
  }
}

function createDraftRepository(): DraftRepository {
  return new DraftRepository(new MemoryMetadataStore(), new MemoryBodyStore());
}

function createController(repository: FakeAnswerPublishRepository, drafts: DraftRepository,
  status: SessionStatus = SessionStatus.AUTHENTICATED): AnswerPublishController {
  const controller = new AnswerPublishController(
    repository, drafts, new FixedSessionGateway(status), ACCOUNT_KEY, '123'
  );
  controller.activate();
  return controller;
}

export default function answerPublishStateTest(): void {
  describe('answerPublishStateTest', () => {
    it('opensNewAnswerWithoutFetchingExistingContent', 0, async () => {
      const repository = new FakeAnswerPublishRepository();
      const controller = createController(repository, createDraftRepository());

      await controller.open();

      const state = controller.snapshot();
      expect(state.phase).assertEqual(AnswerPublishPhase.READY);
      expect(state.answerId).assertUndefined();
      expect(state.html).assertEqual('');
      expect(repository.calls.length).assertEqual(1);
      expect(repository.calls[0]).assertEqual('relationship');
    });

    it('loadsExistingAnswerEditableContentAndToc', 0, async () => {
      const repository = new FakeAnswerPublishRepository();
      repository.answerIds.push('456');
      repository.existing = { answerId: '456', html: '<p>已有内容</p>', tocEnabled: true };
      const controller = createController(repository, createDraftRepository());

      await controller.open();

      const state = controller.snapshot();
      expect(state.phase).assertEqual(AnswerPublishPhase.READY);
      expect(state.answerId).assertEqual('456');
      expect(state.html).assertEqual('<p>已有内容</p>');
      expect(state.tocEnabled).assertTrue();
      expect(repository.calls[1]).assertEqual('fetch:456');
    });

    it('flushesLocalThenRemoteDraftThenPublishesAndClearsOnlyOnNestedSuccess', 0, async () => {
      const repository = new FakeAnswerPublishRepository();
      const drafts = createDraftRepository();
      const controller = createController(repository, drafts);
      await controller.open();
      controller.updateContent('<p>新的回答</p>', true);

      await controller.publish(TRACE_ID, 100);

      const state = controller.snapshot();
      expect(state.phase).assertEqual(AnswerPublishPhase.PUBLISHED);
      expect(state.publishedAnswerId).assertEqual('789');
      expect(repository.calls[1]).assertEqual('remoteDraft');
      expect(repository.calls[2]).assertEqual('publish');
      expect(repository.remoteDraftInputs[0].html).assertEqual('<p>新的回答</p>');
      expect(repository.publishInputs[0].tocEnabled).assertTrue();
      expect((await drafts.load(createAnswerIdentity())).status).assertEqual(ContentDraftLoadStatus.NOT_FOUND);
    });

    it('publishesExistingAnswerAsEditWithoutDroppingAnswerIdOrToc', 0, async () => {
      const repository = new FakeAnswerPublishRepository();
      repository.answerIds.push('456');
      repository.existing = { answerId: '456', html: '<p>旧内容</p>', tocEnabled: false };
      const controller = createController(repository, createDraftRepository());
      await controller.open();
      controller.updateContent('<p>更新内容</p>', true);

      await controller.publish(TRACE_ID, 100);

      expect(repository.remoteDraftInputs[0].answerId).assertEqual('456');
      expect(repository.publishInputs[0].answerId).assertEqual('456');
      expect(repository.publishInputs[0].tocEnabled).assertTrue();
      expect(controller.snapshot().publishedAnswerId).assertEqual('789');
    });

    it('requeriesExistingAnswerAfter103003AndAllowsConflictEdit', 0, async () => {
      const repository = new FakeAnswerPublishRepository();
      repository.answerIds.push(undefined);
      repository.answerIds.push('456');
      repository.publishResponse = '{"code":103003}';
      const controller = createController(repository, createDraftRepository());
      await controller.open();
      controller.updateContent('<p>保留的新内容</p>', false);

      await controller.publish(TRACE_ID, 100);

      const conflicted = controller.snapshot();
      expect(conflicted.phase).assertEqual(AnswerPublishPhase.CONFLICT);
      expect(conflicted.conflictAnswerId).assertEqual('456');
      expect(conflicted.errorMessage).assertEqual(ANSWER_PUBLISH_CONFLICT_MESSAGE);
      controller.continueEditingExistingAnswer();
      expect(controller.snapshot().phase).assertEqual(AnswerPublishPhase.READY);
      expect(controller.snapshot().answerId).assertEqual('456');
      expect(controller.snapshot().html).assertEqual('<p>保留的新内容</p>');
    });

    it('preservesLocalDraftFor401403429AndGenericFailures', 0, async () => {
      const failures: Array<Object> = [
        new HttpFailure(HttpFailureKind.AUTHENTICATION, 401),
        new HttpFailure(HttpFailureKind.AUTHENTICATION, 403),
        new HttpFailure(HttpFailureKind.RATE_LIMITED, 429),
        new HttpFailure(HttpFailureKind.SERVER, 500)
      ];
      const expectedMessages: Array<string> = [
        ANSWER_PUBLISH_LOGIN_REQUIRED_MESSAGE,
        ANSWER_PUBLISH_VERIFICATION_MESSAGE,
        ANSWER_PUBLISH_RATE_LIMITED_MESSAGE,
        '回答发布失败，草稿已保留'
      ];
      for (let index = 0; index < failures.length; index += 1) {
        const repository = new FakeAnswerPublishRepository();
        repository.publishFailure = failures[index];
        const drafts = createDraftRepository();
        const controller = createController(repository, drafts);
        await controller.open();
        controller.updateContent(`<p>失败草稿${index}</p>`, false);

        await controller.publish(TRACE_ID, 100 + index);

        const state = controller.snapshot();
        const loaded = await drafts.load(createAnswerIdentity());
        expect(state.phase).assertEqual(AnswerPublishPhase.FAILED);
        expect(state.errorMessage).assertEqual(expectedMessages[index]);
        expect(loaded.status).assertEqual(ContentDraftLoadStatus.FOUND);
        expect(loaded.draft?.html).assertEqual(`<p>失败草稿${index}</p>`);
      }
    });

    it('gatesGuestBeforeCreatingDraftOrCallingRepository', 0, async () => {
      const repository = new FakeAnswerPublishRepository();
      const controller = createController(repository, createDraftRepository(), SessionStatus.GUEST);

      await controller.open();
      await controller.publish(TRACE_ID, 100);

      expect(controller.snapshot().requiresLogin).assertTrue();
      expect(controller.snapshot().errorMessage).assertEqual(ANSWER_PUBLISH_LOGIN_REQUIRED_MESSAGE);
      expect(repository.calls.length).assertEqual(0);
    });

    it('dropsLatePublishResponseAfterCancellationAndKeepsDraft', 0, async () => {
      const repository = new FakeAnswerPublishRepository();
      repository.publishDeferred = new DeferredText();
      const drafts = createDraftRepository();
      const controller = createController(repository, drafts);
      await controller.open();
      controller.updateContent('<p>离页草稿</p>', false);

      const pending = controller.publish(TRACE_ID, 100);
      await repository.publishStarted;
      expect(repository.calls[2]).assertEqual('publish');
      controller.deactivate();
      repository.publishDeferred.resolve('{"data":{"result":"{\\"publish\\":{\\"id\\":\\"789\\"}}"}}');
      await pending;

      expect(repository.cancelCount).assertEqual(1);
      expect(controller.snapshot().phase).assertEqual(AnswerPublishPhase.RELEASED);
      expect((await drafts.load(createAnswerIdentity())).status).assertEqual(ContentDraftLoadStatus.FOUND);
    });
  });
}

function createAnswerIdentity(): ContentDraftIdentity {
  return {
    accountKey: ACCOUNT_KEY,
    kind: ContentDraftKind.ANSWER,
    targetId: '123',
    draftKey: `answer:${ACCOUNT_KEY}:123`
  };
}
