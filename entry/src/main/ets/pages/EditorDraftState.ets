import {
  ContentDraftIdentity,
  ContentDraftLoadStatus,
  ContentDraftSaveInput,
  DraftRepository
} from 'data';

export const EDITOR_DRAFT_AUTOSAVE_DELAY_MS: number = 1500;
export const EDITOR_DRAFT_LOAD_FAILURE_MESSAGE: string = '草稿无法安全恢复，请选择丢弃或重试';
export const EDITOR_DRAFT_SAVE_FAILURE_MESSAGE: string = '草稿保存失败，请重试';

export enum EditorDraftPhase {
  IDLE = 'idle',
  LOADING = 'loading',
  READY = 'ready',
  FAILED = 'failed',
  RELEASED = 'released'
}

export interface EditorDraftContent {
  readonly html: string;
  readonly title: string;
  readonly tocEnabled: boolean;
  readonly imageRefsJson: string;
  readonly topicRefsJson: string;
  readonly remoteContentId?: string;
}

export interface EditorDraftViewState {
  readonly phase: EditorDraftPhase;
  readonly generation: number;
  readonly content: EditorDraftContent;
  readonly loaded: boolean;
  readonly dirty: boolean;
  readonly saving: boolean;
  readonly autosaveScheduled: boolean;
  readonly canLeaveWithoutConfirmation: boolean;
  readonly canDiscard: boolean;
  readonly errorMessage?: string;
}

export type EditorDraftObserver = (state: EditorDraftViewState) => void;

/** 计时器隔离使 autosave 在 Hypium 中不依赖真实时钟。 */
export interface EditorAutosaveScheduler {
  schedule(delayMs: number, callback: () => void): number;
  cancel(token: number): void;
}

export class SystemEditorAutosaveScheduler implements EditorAutosaveScheduler {
  schedule(delayMs: number, callback: () => void): number {
    return setTimeout(callback, delayMs) as number;
  }

  cancel(token: number): void {
    clearTimeout(token);
  }
}

/**
 * 纯状态/编排层：新建时采用初始内容，已存草稿优先恢复；正文只传给加密 DraftRepository，
 * 不在此层记录、打印或发送到网络。页面离开时通过 generation 丢弃迟到结果。
 */
export class EditorDraftController {
  private readonly drafts: DraftRepository;
  private readonly identity: ContentDraftIdentity;
  private readonly initialContent: EditorDraftContent;
  private readonly scheduler: EditorAutosaveScheduler;
  private readonly observer: EditorDraftObserver;
  private active: boolean = false;
  private loaded: boolean = false;
  private generation: number = 0;
  private revision: number = 0;
  private phase: EditorDraftPhase = EditorDraftPhase.IDLE;
  private content: EditorDraftContent;
  private dirty: boolean = false;
  private saving: boolean = false;
  private autosaveToken?: number;
  private savePromise?: Promise<void>;
  private flushAfterSave: boolean = false;
  private canDiscard: boolean = false;
  private errorMessage?: string;

  constructor(drafts: DraftRepository, identity: ContentDraftIdentity,
    initialContent: EditorDraftContent = emptyEditorDraftContent(),
    scheduler: EditorAutosaveScheduler = new SystemEditorAutosaveScheduler(),
    observer: EditorDraftObserver = (_state: EditorDraftViewState): void => {}) {
    this.drafts = drafts;
    this.identity = identity;
    this.initialContent = cloneEditorDraftContent(initialContent);
    this.content = cloneEditorDraftContent(initialContent);
    this.scheduler = scheduler;
    this.observer = observer;
  }

  activate(): void {
    if (this.active || this.phase === EditorDraftPhase.RELEASED) {
      return;
    }
    this.active = true;
    this.emit();
  }

  async open(): Promise<void> {
    if (!this.active || this.saving || this.phase === EditorDraftPhase.LOADING) {
      return;
    }
    const operation = this.beginLoad();
    try {
      const result = await this.drafts.load(this.identity);
      if (!this.isCurrent(operation)) {
        return;
      }
      if (result.status === ContentDraftLoadStatus.FOUND && result.draft !== undefined) {
        this.content = {
          html: result.draft.html,
          title: result.draft.metadata.title,
          tocEnabled: result.draft.metadata.tocEnabled,
          imageRefsJson: result.draft.metadata.imageRefsJson,
          topicRefsJson: result.draft.metadata.topicRefsJson,
          remoteContentId: result.draft.metadata.remoteContentId
        };
        this.dirty = result.draft.metadata.dirty;
      } else if (result.status === ContentDraftLoadStatus.NOT_FOUND) {
        this.content = cloneEditorDraftContent(this.initialContent);
        this.dirty = false;
      } else {
        this.phase = EditorDraftPhase.FAILED;
        this.errorMessage = EDITOR_DRAFT_LOAD_FAILURE_MESSAGE;
        this.canDiscard = true;
        this.emit();
        return;
      }
      this.loaded = true;
      this.phase = EditorDraftPhase.READY;
      this.canDiscard = false;
      this.errorMessage = undefined;
      this.emit();
      if (this.dirty) {
        this.scheduleAutosave();
      }
    } catch (_error) {
      if (this.isCurrent(operation)) {
        this.phase = EditorDraftPhase.FAILED;
        this.errorMessage = EDITOR_DRAFT_LOAD_FAILURE_MESSAGE;
        this.canDiscard = false;
        this.emit();
      }
    }
  }

  replaceContent(content: EditorDraftContent): void {
    if (!this.canEdit()) {
      return;
    }
    this.content = cloneEditorDraftContent(content);
    this.markDirty();
  }

  updateHtml(html: string): void {
    if (!this.canEdit()) {
      return;
    }
    this.content = {
      html: html,
      title: this.content.title,
      tocEnabled: this.content.tocEnabled,
      imageRefsJson: this.content.imageRefsJson,
      topicRefsJson: this.content.topicRefsJson,
      remoteContentId: this.content.remoteContentId
    };
    this.markDirty();
  }

  updateTitle(title: string): void {
    if (!this.canEdit()) {
      return;
    }
    this.content = {
      html: this.content.html,
      title: title,
      tocEnabled: this.content.tocEnabled,
      imageRefsJson: this.content.imageRefsJson,
      topicRefsJson: this.content.topicRefsJson,
      remoteContentId: this.content.remoteContentId
    };
    this.markDirty();
  }

  updateTocEnabled(tocEnabled: boolean): void {
    if (!this.canEdit()) {
      return;
    }
    this.content = {
      html: this.content.html,
      title: this.content.title,
      tocEnabled: tocEnabled,
      imageRefsJson: this.content.imageRefsJson,
      topicRefsJson: this.content.topicRefsJson,
      remoteContentId: this.content.remoteContentId
    };
    this.markDirty();
  }

  updateReferences(imageRefsJson: string, topicRefsJson: string): void {
    if (!this.canEdit()) {
      return;
    }
    this.content = {
      html: this.content.html,
      title: this.content.title,
      tocEnabled: this.content.tocEnabled,
      imageRefsJson: imageRefsJson,
      topicRefsJson: topicRefsJson,
      remoteContentId: this.content.remoteContentId
    };
    this.markDirty();
  }

  async flush(now: number = Date.now()): Promise<void> {
    if (!this.active || !this.loaded || this.phase === EditorDraftPhase.RELEASED || !this.dirty) {
      return;
    }
    this.cancelAutosave();
    if (this.savePromise !== undefined) {
      this.flushAfterSave = true;
      return this.savePromise;
    }
    const running = this.saveUntilSettled(this.generation, now);
    this.savePromise = running;
    try {
      await running;
    } finally {
      if (this.savePromise === running) {
        this.savePromise = undefined;
      }
    }
  }

  async discard(): Promise<void> {
    if (!this.active || this.phase === EditorDraftPhase.RELEASED || this.saving) {
      return;
    }
    this.cancelAutosave();
    const operation = this.generation;
    try {
      await this.drafts.discard(this.identity);
      if (!this.isCurrent(operation)) {
        return;
      }
      this.content = cloneEditorDraftContent(this.initialContent);
      this.dirty = false;
      this.canDiscard = false;
      this.errorMessage = undefined;
      this.loaded = true;
      this.phase = EditorDraftPhase.READY;
      this.emit();
    } catch (_error) {
      if (this.isCurrent(operation)) {
        this.phase = EditorDraftPhase.FAILED;
        this.errorMessage = EDITOR_DRAFT_SAVE_FAILURE_MESSAGE;
        this.emit();
      }
    }
  }

  deactivate(): void {
    if (!this.active) {
      return;
    }
    this.cancelAutosave();
    this.active = false;
    this.generation += 1;
    this.phase = EditorDraftPhase.RELEASED;
    this.saving = false;
    this.emit();
  }

  snapshot(): EditorDraftViewState {
    return {
      phase: this.phase,
      generation: this.generation,
      content: cloneEditorDraftContent(this.content),
      loaded: this.loaded,
      dirty: this.dirty,
      saving: this.saving,
      autosaveScheduled: this.autosaveToken !== undefined,
      canLeaveWithoutConfirmation: !this.dirty && !this.saving,
      canDiscard: this.canDiscard,
      errorMessage: this.errorMessage
    };
  }

  private beginLoad(): number {
    this.cancelAutosave();
    this.generation += 1;
    this.phase = EditorDraftPhase.LOADING;
    this.errorMessage = undefined;
    this.canDiscard = false;
    this.emit();
    return this.generation;
  }

  private markDirty(): void {
    this.revision += 1;
    this.dirty = true;
    this.phase = EditorDraftPhase.READY;
    this.errorMessage = undefined;
    this.canDiscard = false;
    this.scheduleAutosave();
    this.emit();
  }

  private scheduleAutosave(): void {
    this.cancelAutosave();
    const operation = this.generation;
    this.autosaveToken = this.scheduler.schedule(EDITOR_DRAFT_AUTOSAVE_DELAY_MS, (): void => {
      if (!this.isCurrent(operation)) {
        return;
      }
      this.autosaveToken = undefined;
      this.flush().then((): void => {}, (): void => {});
    });
  }

  private cancelAutosave(): void {
    if (this.autosaveToken === undefined) {
      return;
    }
    this.scheduler.cancel(this.autosaveToken);
    this.autosaveToken = undefined;
  }

  private async saveUntilSettled(operation: number, now: number): Promise<void> {
    do {
      this.flushAfterSave = false;
      const savedRevision = this.revision;
      const input = this.createSaveInput();
      this.saving = true;
      this.phase = EditorDraftPhase.READY;
      this.emit();
      try {
        await this.drafts.save(input, now);
      } catch (_error) {
        if (this.isCurrent(operation)) {
          this.saving = false;
          this.phase = EditorDraftPhase.FAILED;
          this.errorMessage = EDITOR_DRAFT_SAVE_FAILURE_MESSAGE;
          this.emit();
        }
        return;
      }
      if (!this.isCurrent(operation)) {
        return;
      }
      this.dirty = savedRevision !== this.revision;
      this.saving = false;
    } while (this.isCurrent(operation) && this.dirty && this.flushAfterSave);

    if (!this.isCurrent(operation)) {
      return;
    }
    this.phase = EditorDraftPhase.READY;
    this.errorMessage = undefined;
    this.emit();
    if (this.dirty) {
      this.scheduleAutosave();
    }
  }

  private createSaveInput(): ContentDraftSaveInput {
    return {
      draftKey: this.identity.draftKey,
      accountKey: this.identity.accountKey,
      kind: this.identity.kind,
      targetId: this.identity.targetId,
      html: this.content.html,
      remoteContentId: this.content.remoteContentId,
      title: this.content.title,
      plainTextLength: countPlainText(this.content.html),
      tocEnabled: this.content.tocEnabled,
      imageRefsJson: this.content.imageRefsJson,
      topicRefsJson: this.content.topicRefsJson,
      dirty: true
    };
  }

  private canEdit(): boolean {
    return this.active && this.loaded && this.phase !== EditorDraftPhase.RELEASED;
  }

  private isCurrent(operation: number): boolean {
    return this.active && operation === this.generation;
  }

  private emit(): void {
    this.observer(this.snapshot());
  }
}

function emptyEditorDraftContent(): EditorDraftContent {
  return {
    html: '',
    title: '',
    tocEnabled: false,
    imageRefsJson: '[]',
    topicRefsJson: '[]'
  };
}

function cloneEditorDraftContent(content: EditorDraftContent): EditorDraftContent {
  return {
    html: content.html,
    title: content.title,
    tocEnabled: content.tocEnabled,
    imageRefsJson: content.imageRefsJson,
    topicRefsJson: content.topicRefsJson,
    remoteContentId: content.remoteContentId
  };
}

function countPlainText(html: string): number {
  return html.replace(/<[^>]*>/g, '').length;
}
