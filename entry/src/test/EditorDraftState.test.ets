import { describe, expect, it } from '@ohos/hypium';
import {
  ContentDraftIdentity,
  ContentDraftKind,
  ContentDraftMetadata,
  ContentDraftMetadataStore,
  ContentDraftSaveInput,
  DraftBodyStore,
  DraftRepository
} from 'data';
import {
  EDITOR_DRAFT_AUTOSAVE_DELAY_MS,
  EDITOR_DRAFT_LOAD_FAILURE_MESSAGE,
  EditorAutosaveScheduler,
  EditorDraftContent,
  EditorDraftController,
  EditorDraftPhase
} from '../main/ets/pages/EditorDraftState';

const ACCOUNT_KEY: string = 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

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

class DeferredBodyStore implements DraftBodyStore {
  private readonly values: Map<string, string> = new Map<string, string>();
  private readonly saveResolvers: Array<() => void> = [];
  private saveCount: number = 0;
  private resolveFirstSaveStarted?: () => void;
  private resolveSecondSaveStarted?: () => void;
  readonly firstSaveStarted: Promise<void>;
  readonly secondSaveStarted: Promise<void>;

  constructor() {
    this.firstSaveStarted = new Promise<void>((resolve: () => void): void => {
      this.resolveFirstSaveStarted = resolve;
    });
    this.secondSaveStarted = new Promise<void>((resolve: () => void): void => {
      this.resolveSecondSaveStarted = resolve;
    });
  }

  save(draftKey: string, html: string): Promise<void> {
    this.values.set(draftKey, html);
    this.saveCount += 1;
    if (this.saveCount === 1 && this.resolveFirstSaveStarted !== undefined) {
      this.resolveFirstSaveStarted();
      this.resolveFirstSaveStarted = undefined;
    }
    if (this.saveCount === 2 && this.resolveSecondSaveStarted !== undefined) {
      this.resolveSecondSaveStarted();
      this.resolveSecondSaveStarted = undefined;
    }
    return new Promise<void>((resolve: () => void): void => {
      this.saveResolvers.push(resolve);
    });
  }

  load(draftKey: string): Promise<string | undefined> {
    return Promise.resolve(this.values.get(draftKey));
  }

  remove(draftKey: string): Promise<void> {
    this.values.delete(draftKey);
    return Promise.resolve();
  }

  completeNextSave(): void {
    const resolve = this.saveResolvers.shift();
    if (resolve !== undefined) {
      resolve();
    }
  }
}

class ManualScheduler implements EditorAutosaveScheduler {
  private readonly callbacks: Map<number, () => void> = new Map<number, () => void>();
  private nextToken: number = 1;
  lastDelay: number = 0;
  cancelled: Array<number> = [];

  schedule(delayMs: number, callback: () => void): number {
    this.lastDelay = delayMs;
    const token = this.nextToken;
    this.nextToken += 1;
    this.callbacks.set(token, callback);
    return token;
  }

  cancel(token: number): void {
    this.cancelled.push(token);
    this.callbacks.delete(token);
  }

  fireLatest(): void {
    const token = this.nextToken - 1;
    const callback = this.callbacks.get(token);
    if (callback !== undefined) {
      this.callbacks.delete(token);
      callback();
    }
  }

  fireIncludingCancelled(token: number): void {
    const callback = this.callbacks.get(token);
    if (callback !== undefined) {
      callback();
    }
  }
}

export default function editorDraftStateTest(): void {
  describe('editorDraftStateTest', () => {
    it('opensNewDraftWithInitialEditorState', 0, async () => {
      const initialContent: EditorDraftContent = {
        html: '<p>新建</p>', title: '标题', tocEnabled: true, imageRefsJson: '[]', topicRefsJson: '[]'
      };
      const controller = createController(createDraftRepository(), new ManualScheduler(), initialContent);

      await controller.open();

      const state = controller.snapshot();
      expect(state.phase).assertEqual(EditorDraftPhase.READY);
      expect(state.loaded).assertTrue();
      expect(state.content.html).assertEqual('<p>新建</p>');
      expect(state.content.title).assertEqual('标题');
      expect(state.content.tocEnabled).assertTrue();
      expect(state.dirty).assertFalse();
    });

    it('restoresStoredTitleBodyTocAndReferencesBeforeInitialContent', 0, async () => {
      const drafts = createDraftRepository();
      await drafts.save(createSaveInput('<p>已存正文</p>', '已存标题', true, '["image"]', '["topic"]'), 10);
      const initialContent: EditorDraftContent = {
        html: '<p>初始正文</p>', title: '初始标题', tocEnabled: false, imageRefsJson: '[]', topicRefsJson: '[]'
      };
      const controller = createController(drafts, new ManualScheduler(), initialContent);

      await controller.open();

      const state = controller.snapshot();
      expect(state.content.html).assertEqual('<p>已存正文</p>');
      expect(state.content.title).assertEqual('已存标题');
      expect(state.content.tocEnabled).assertTrue();
      expect(state.content.imageRefsJson).assertEqual('["image"]');
      expect(state.content.topicRefsJson).assertEqual('["topic"]');
    });

    it('debouncesEditorChangesAndFlushesLatestContent', 0, async () => {
      const drafts = createDraftRepository();
      const scheduler = new ManualScheduler();
      const controller = createController(drafts, scheduler);
      await controller.open();

      controller.updateTitle('第一次');
      controller.updateHtml('<p>第二次正文</p>');
      controller.updateTocEnabled(true);
      controller.updateReferences('["image"]', '["topic"]');
      expect(scheduler.lastDelay).assertEqual(EDITOR_DRAFT_AUTOSAVE_DELAY_MS);
      expect(controller.snapshot().dirty).assertTrue();
      scheduler.fireLatest();
      await nextTick();
      await nextTick();

      const loaded = await drafts.load(identity());
      expect(loaded.draft?.html).assertEqual('<p>第二次正文</p>');
      expect(loaded.draft?.metadata.title).assertEqual('第一次');
      expect(loaded.draft?.metadata.tocEnabled).assertTrue();
      expect(loaded.draft?.metadata.imageRefsJson).assertEqual('["image"]');
      expect(controller.snapshot().dirty).assertFalse();
    });

    it('flushesNewestRevisionAfterAnInFlightSave', 0, async () => {
      const bodyStore = new DeferredBodyStore();
      const drafts = new DraftRepository(new MemoryMetadataStore(), bodyStore);
      const controller = createController(drafts, new ManualScheduler());
      await controller.open();
      controller.updateHtml('<p>第一版</p>');

      const firstFlush = controller.flush(10);
      await bodyStore.firstSaveStarted;
      controller.updateHtml('<p>第二版</p>');
      const secondFlush = controller.flush(20);
      bodyStore.completeNextSave();
      await bodyStore.secondSaveStarted;
      bodyStore.completeNextSave();
      await firstFlush;
      await secondFlush;

      const loaded = await drafts.load(identity());
      expect(loaded.draft?.html).assertEqual('<p>第二版</p>');
      expect(controller.snapshot().dirty).assertFalse();
    });

    it('dropsLateSaveStateAfterDeactivation', 0, async () => {
      const bodyStore = new DeferredBodyStore();
      const controller = createController(new DraftRepository(new MemoryMetadataStore(), bodyStore), new ManualScheduler());
      await controller.open();
      controller.updateHtml('<p>离页正文</p>');

      const saving = controller.flush(10);
      await bodyStore.firstSaveStarted;
      controller.deactivate();
      bodyStore.completeNextSave();
      await saving;

      expect(controller.snapshot().phase).assertEqual(EditorDraftPhase.RELEASED);
      expect(controller.snapshot().saving).assertFalse();
    });

    it('marksCorruptDraftForSafeDiscardWithoutExposingBody', 0, async () => {
      const metadataStore = new MemoryMetadataStore();
      const corruptMetadata: ContentDraftMetadata = {
        draftKey: identity().draftKey,
        accountKey: ACCOUNT_KEY,
        kind: ContentDraftKind.ANSWER,
        targetId: '123',
        title: '元数据',
        plainTextLength: 2,
        tocEnabled: false,
        imageRefsJson: '[]',
        topicRefsJson: '[]',
        dirty: true,
        version: 1,
        createdAt: 1,
        updatedAt: 1
      };
      await metadataStore.upsert(corruptMetadata);
      const controller = createController(new DraftRepository(metadataStore, new MemoryBodyStore()), new ManualScheduler());

      await controller.open();

      expect(controller.snapshot().phase).assertEqual(EditorDraftPhase.FAILED);
      expect(controller.snapshot().errorMessage).assertEqual(EDITOR_DRAFT_LOAD_FAILURE_MESSAGE);
      expect(controller.snapshot().canDiscard).assertTrue();
      await controller.discard();
      expect(controller.snapshot().phase).assertEqual(EditorDraftPhase.READY);
    });
  });
}

function createDraftRepository(): DraftRepository {
  return new DraftRepository(new MemoryMetadataStore(), new MemoryBodyStore());
}

function createController(drafts: DraftRepository, scheduler: EditorAutosaveScheduler,
  initialContent: EditorDraftContent = emptyContent()): EditorDraftController {
  const controller = new EditorDraftController(drafts, identity(), initialContent, scheduler);
  controller.activate();
  return controller;
}

function identity(): ContentDraftIdentity {
  return {
    draftKey: `answer:${ACCOUNT_KEY}:123`,
    accountKey: ACCOUNT_KEY,
    kind: ContentDraftKind.ANSWER,
    targetId: '123'
  };
}

function createSaveInput(html: string, title: string, tocEnabled: boolean,
  imageRefsJson: string, topicRefsJson: string): ContentDraftSaveInput {
  return {
    draftKey: identity().draftKey,
    accountKey: ACCOUNT_KEY,
    kind: ContentDraftKind.ANSWER,
    targetId: '123',
    html: html,
    title: title,
    plainTextLength: html.replace(/<[^>]*>/g, '').length,
    tocEnabled: tocEnabled,
    imageRefsJson: imageRefsJson,
    topicRefsJson: topicRefsJson,
    dirty: true
  };
}

function emptyContent(): EditorDraftContent {
  return { html: '', title: '', tocEnabled: false, imageRefsJson: '[]', topicRefsJson: '[]' };
}

function nextTick(): Promise<void> {
  return Promise.resolve();
}
