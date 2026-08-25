import { describe, expect, it } from '@ohos/hypium';
import {
  ContentDraftIdentity,
  ContentDraftKind,
  ContentDraftLoadResult,
  ContentDraftMetadata,
  ContentDraftMetadataStore,
  ContentDraftSaveInput,
  DraftBodyStore,
  DraftRepository,
  HttpFailure,
  HttpFailureKind,
  PinPublishInput,
  PinPublishRepository,
  PinTopicSuggestion
} from 'data';
import {
  PIN_EMPTY_CONTENT_MESSAGE,
  PIN_TOPIC_LOOKUP_FAILED_MESSAGE,
  PinDraftContent,
  PinPublishController,
  PinPublishOperation,
  PinPublishTraceIdFactory,
  PinTopicSearchScheduler
} from '../main/ets/pages/PinPublishState';

const ACCOUNT_KEY: string = 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const DRAFT_ID: string = '01234567-89ab-4cde-8fab-0123456789ab';
const TRACE_ID: string = '1770000000000,01234567-89ab-4cde-8fab-0123456789ab';

class FakeDraftRepository extends DraftRepository {
  readonly saves: Array<ContentDraftSaveInput> = [];
  failNextSave?: Object;

  constructor() {
    super(new NoopMetadataStore(), new NoopBodyStore());
  }

  save(input: ContentDraftSaveInput, _now?: number): Promise<ContentDraftMetadata> {
    this.saves.push(input);
    if (this.failNextSave !== undefined) {
      const failure: Object = this.failNextSave;
      this.failNextSave = undefined;
      return Promise.reject(failure);
    }
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
}

class NoopMetadataStore implements ContentDraftMetadataStore {
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

class NoopBodyStore implements DraftBodyStore {
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

class FakePinPublishRepository implements PinPublishRepository {
  readonly calls: Array<string> = [];
  remoteDraftFailure?: Object;
  publishFailure?: Object;
  publishResult: string = '888';
  private topicResolvers: Array<(value: Array<PinTopicSuggestion>) => void> = [];
  private topicRejectors: Array<(reason: Object) => void> = [];
  cancelCount: number = 0;

  recommendTopics(query: string, _title: string, _contentHtml: string): Promise<Array<PinTopicSuggestion>> {
    this.calls.push(`topics:${query}`);
    return new Promise<Array<PinTopicSuggestion>>((resolve: (value: Array<PinTopicSuggestion>) => void,
      reject: (reason: Object) => void): void => {
      this.topicResolvers.push(resolve);
      this.topicRejectors.push(reject);
    });
  }

  saveRemoteDraft(_input: PinPublishInput): Promise<void> {
    this.calls.push('remote-draft');
    return this.remoteDraftFailure === undefined ? Promise.resolve() : Promise.reject(this.remoteDraftFailure);
  }

  publish(_input: PinPublishInput): Promise<string> {
    this.calls.push('publish');
    return this.publishFailure === undefined ? Promise.resolve(this.publishResult) : Promise.reject(this.publishFailure);
  }

  cancel(): void {
    this.cancelCount += 1;
  }

  resolveTopic(index: number, suggestions: Array<PinTopicSuggestion>): void {
    this.topicResolvers[index](suggestions);
  }

  rejectTopic(index: number): void {
    this.topicRejectors[index](new Error('network details must not escape'));
  }
}

class FakeScheduler implements PinTopicSearchScheduler {
  readonly callbacks: Map<number, () => void> = new Map<number, () => void>();
  private nextHandle: number = 1;

  schedule(_delayMs: number, callback: () => void): number {
    const handle = this.nextHandle;
    this.nextHandle += 1;
    this.callbacks.set(handle, callback);
    return handle;
  }

  cancel(handle: number): void {
    this.callbacks.delete(handle);
  }

  run(handle: number): void {
    const callback = this.callbacks.get(handle);
    this.callbacks.delete(handle);
    callback?.();
  }
}

class FixedTraceIdFactory implements PinPublishTraceIdFactory {
  createTraceId(): string {
    return TRACE_ID;
  }
}

function pinIdentity(): ContentDraftIdentity {
  return {
    draftKey: `pin:${ACCOUNT_KEY}:${DRAFT_ID}`,
    accountKey: ACCOUNT_KEY,
    kind: ContentDraftKind.PIN,
    targetId: DRAFT_ID
  };
}

function richContent(): PinDraftContent {
  return {
    title: '鸿蒙迁移',
    html: '<p>正文 <strong>文本</strong></p>',
    images: [{
      imageId: '1',
      url: 'https://picx.zhimg.com/v2-image.jpg',
      originalUrl: 'https://picx.zhimg.com/v2-image-original.jpg',
      width: 1080,
      height: 720,
      watermark: 'original'
    }],
    localImageReferences: [],
    topics: [
      { topicId: '2', displayName: 'HarmonyOS' },
      { topicId: '2', displayName: '重复话题' }
    ]
  };
}

function createController(repository: FakePinPublishRepository, drafts: FakeDraftRepository,
  scheduler: FakeScheduler): PinPublishController {
  return new PinPublishController(repository, drafts, pinIdentity(), new FixedTraceIdFactory(), scheduler);
}

export default function pinPublishStateTest(): void {
  describe('pinPublishStateTest', () => {
    it('rejectsEmptyContentWithoutWritingLocalOrRemoteDraft', 0, async () => {
      const repository = new FakePinPublishRepository();
      const drafts = new FakeDraftRepository();
      const controller = createController(repository, drafts, new FakeScheduler());
      controller.activate();

      await controller.publish();

      expect(controller.snapshot().operation).assertEqual(PinPublishOperation.ERROR);
      expect(controller.snapshot().errorMessage).assertEqual(PIN_EMPTY_CONTENT_MESSAGE);
      expect(drafts.saves.length).assertEqual(0);
      expect(repository.calls.length).assertEqual(0);
    });

    it('persistsTitleBodyImagesAndDeduplicatedTopicsBeforeRemoteDraftAndPublish', 0, async () => {
      const repository = new FakePinPublishRepository();
      const drafts = new FakeDraftRepository();
      const controller = createController(repository, drafts, new FakeScheduler());
      controller.activate();
      controller.replaceContent(richContent());

      await controller.publish();

      expect(drafts.saves.length).assertEqual(2);
      expect(drafts.saves[0].title).assertEqual('鸿蒙迁移');
      expect(drafts.saves[0].plainTextLength).assertEqual(5);
      expect(drafts.saves[0].imageRefsJson.includes('v2-image-original.jpg')).assertTrue();
      expect(drafts.saves[0].topicRefsJson).assertEqual('[{"topicId":"2","displayName":"HarmonyOS"}]');
      expect(repository.calls[0]).assertEqual('remote-draft');
      expect(repository.calls[1]).assertEqual('publish');
      expect(drafts.saves[1].remoteContentId).assertEqual('888');
      expect(drafts.saves[1].dirty).assertFalse();
      expect(controller.snapshot().operation).assertEqual(PinPublishOperation.PUBLISHED);
      expect(controller.snapshot().publishedContentId).assertEqual('888');
    });

    it('keepsLocalDraftForAuthenticationForbiddenRateLimitAndOtherPublishFailures', 0, async () => {
      const failures: Array<Object> = [
        new HttpFailure(HttpFailureKind.AUTHENTICATION, 401),
        new HttpFailure(HttpFailureKind.AUTHENTICATION, 403),
        new HttpFailure(HttpFailureKind.RATE_LIMITED, 429),
        new HttpFailure(HttpFailureKind.SERVER, 500)
      ];
      const expected = ['authentication', 'forbidden', 'rate_limited', 'server'];
      for (let index = 0; index < failures.length; index += 1) {
        const repository = new FakePinPublishRepository();
        repository.publishFailure = failures[index];
        const drafts = new FakeDraftRepository();
        const controller = createController(repository, drafts, new FakeScheduler());
        controller.activate();
        controller.replaceContent(richContent());

        await controller.publish();

        expect(drafts.saves.length).assertEqual(1);
        expect(controller.snapshot().failureKind).assertEqual(expected[index]);
        expect(controller.snapshot().localDraftSaved).assertTrue();
      }
    });

    it('doesNotPublishWhenRemoteDraftFailsAndLeavesPersistedContentRecoverable', 0, async () => {
      const repository = new FakePinPublishRepository();
      repository.remoteDraftFailure = new HttpFailure(HttpFailureKind.AUTHENTICATION, 403);
      const drafts = new FakeDraftRepository();
      const controller = createController(repository, drafts, new FakeScheduler());
      controller.activate();
      controller.replaceContent(richContent());

      await controller.publish();

      expect(repository.calls.length).assertEqual(1);
      expect(repository.calls[0]).assertEqual('remote-draft');
      expect(drafts.saves.length).assertEqual(1);
      expect(controller.snapshot().requiresSecurityVerification).assertTrue();
      expect(controller.snapshot().remoteDraftSaved).assertFalse();
    });

    it('debouncesTopicQueriesDropsLateResultsAndBoundsDeduplicatedSuggestions', 0, async () => {
      const repository = new FakePinPublishRepository();
      const scheduler = new FakeScheduler();
      const controller = createController(repository, new FakeDraftRepository(), scheduler);
      controller.activate();
      controller.replaceContent(richContent());
      controller.requestTopicSuggestions('har');
      const firstHandle = 1;
      scheduler.run(firstHandle);
      await Promise.resolve();
      controller.requestTopicSuggestions('harmony');
      const secondHandle = 2;

      scheduler.run(secondHandle);
      await Promise.resolve();
      repository.resolveTopic(0, [{ topicId: '2', displayName: '迟到', discussCount: '1' }]);
      await Promise.resolve();
      repository.resolveTopic(1, [
        { topicId: '3', displayName: 'HarmonyOS', discussCount: '10' },
        { topicId: '3', displayName: '重复', discussCount: '11' },
        { topicId: '4', displayName: 'ArkTS', discussCount: '5' }
      ]);
      await Promise.resolve();

      expect(repository.calls.length).assertEqual(2);
      expect(repository.calls[0]).assertEqual('topics:har');
      expect(repository.calls[1]).assertEqual('topics:harmony');
      expect(controller.snapshot().topicSearch.suggestions.length).assertEqual(2);
      expect(controller.snapshot().topicSearch.suggestions[0].topicId).assertEqual('3');
      expect(controller.snapshot().topicSearch.pending).assertFalse();
    });

    it('cancelsTopicLookupOnLeaveAndUsesFixedFailureFallback', 0, async () => {
      const repository = new FakePinPublishRepository();
      const scheduler = new FakeScheduler();
      const controller = createController(repository, new FakeDraftRepository(), scheduler);
      controller.activate();
      controller.replaceContent(richContent());
      controller.requestTopicSuggestions('harmony');
      scheduler.run(1);
      await Promise.resolve();
      repository.rejectTopic(0);
      await Promise.resolve();

      expect(controller.snapshot().topicSearch.errorMessage).assertEqual(PIN_TOPIC_LOOKUP_FAILED_MESSAGE);
      controller.requestTopicSuggestions('ark');
      controller.deactivate();

      expect(repository.cancelCount).assertEqual(1);
      expect(scheduler.callbacks.size).assertEqual(0);
    });
  });
}
