import {
  HttpFailure,
  HttpFailureKind,
  LoginSessionGateway,
  MobileNotificationAuthor,
  MobileNotificationRepository,
  SessionStatus,
  ZhihuPrivateMessage,
  ZhihuPrivateMessagePage,
  privateMessageStableId
} from 'data';

export enum PrivateMessagePhase {
  IDLE = 'idle',
  LOADING = 'loading',
  READY = 'ready',
  EMPTY = 'empty',
  ERROR = 'error'
}

export interface PrivateMessageViewState {
  readonly phase: PrivateMessagePhase;
  /** 按时间正序排列（旧→新），列表底部为最新一条。 */
  readonly items: Array<ZhihuPrivateMessage>;
  readonly peer?: MobileNotificationAuthor;
  readonly sending: boolean;
  readonly loadingMore: boolean;
  readonly canLoadMore: boolean;
  readonly requiresLogin: boolean;
  readonly errorMessage?: string;
  readonly sendError?: string;
}

export type PrivateMessageStateObserver = (state: PrivateMessageViewState) => void;

/**
 * 私信会话控制器（对齐上游 `PrivateMessageViewModel`）：GET /messages 按
 * sender_id 拉取会话；发送走加密表单 POST /messages，成功把回执插入尾部。
 */
export class PrivateMessageController {
  private readonly repository: MobileNotificationRepository;
  private readonly session: LoginSessionGateway;
  private readonly observer: PrivateMessageStateObserver;
  private readonly peerId: string;
  private active: boolean = false;
  private generation: number = 0;
  private phase: PrivateMessagePhase = PrivateMessagePhase.IDLE;
  private messages: Array<ZhihuPrivateMessage> = [];
  private peer?: MobileNotificationAuthor;
  private nextCursor?: string;
  private reachedEnd: boolean = true;
  private sending: boolean = false;
  private loadingMore: boolean = false;
  private paginationBlocked: boolean = false;
  private requiresLogin: boolean = false;
  private errorMessage?: string;
  private sendError?: string;

  constructor(peerId: string, repository: MobileNotificationRepository,
    session: LoginSessionGateway, observer: PrivateMessageStateObserver = (_state:
      PrivateMessageViewState): void => {
    }) {
    this.peerId = peerId;
    this.repository = repository;
    this.session = session;
    this.observer = observer;
  }

  activate(): void {
    if (this.active) {
      return;
    }
    this.active = true;
    this.emit();
  }

  deactivate(): void {
    if (!this.active) {
      return;
    }
    this.active = false;
    this.generation += 1;
    this.loadingMore = false;
    this.repository.cancel();
  }

  snapshot(): PrivateMessageViewState {
    return {
      phase: this.phase,
      items: this.chronological(),
      peer: this.peer,
      sending: this.sending,
      loadingMore: this.loadingMore,
      canLoadMore: !this.paginationBlocked && !this.reachedEnd && this.nextCursor !== undefined,
      requiresLogin: this.requiresLogin,
      errorMessage: this.errorMessage,
      sendError: this.sendError
    };
  }

  loadInitial(): Promise<void> {
    if (!this.active) {
      return Promise.resolve();
    }
    this.repository.cancel();
    const generation = ++this.generation;
    this.phase = PrivateMessagePhase.LOADING;
    this.loadingMore = false;
    this.paginationBlocked = false;
    this.requiresLogin = false;
    this.errorMessage = undefined;
    this.sendError = undefined;
    this.emit();
    if (this.session.getState().status !== SessionStatus.AUTHENTICATED) {
      this.phase = PrivateMessagePhase.ERROR;
      this.errorMessage = '私信需要登录，请登录后重试';
      this.requiresLogin = true;
      this.emit();
      return Promise.resolve();
    }
    return this.fetchPage(generation, undefined);
  }

  retry(): Promise<void> {
    return this.loadInitial();
  }

  async loadMore(): Promise<void> {
    if (!this.active || this.phase === PrivateMessagePhase.LOADING || this.loadingMore ||
      this.paginationBlocked || this.reachedEnd || this.nextCursor === undefined) {
      return;
    }
    const generation = this.generation;
    const cursor = this.nextCursor;
    this.loadingMore = true;
    this.emit();
    try {
      await this.fetchPage(generation, cursor);
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      if (this.messages.length === 0) {
        this.phase = PrivateMessagePhase.ERROR;
      }
      this.setFailure(error, true);
    } finally {
      if (this.isCurrent(generation)) {
        this.loadingMore = false;
        this.emit();
      }
    }
  }

  async send(content: string): Promise<boolean> {
    if (!this.active || this.sending || content.trim().length === 0) {
      return false;
    }
    if (this.session.getState().status !== SessionStatus.AUTHENTICATED) {
      this.requiresLogin = true;
      this.sendError = '发送私信需要登录，请登录后重试';
      this.emit();
      return false;
    }
    const generation = this.generation;
    this.sending = true;
    this.sendError = undefined;
    this.emit();
    try {
      const receipt = await this.repository.sendPrivateMessage(this.peerId, content);
      if (!this.isCurrent(generation)) {
        return false;
      }
      const exists = this.messages.some((message: ZhihuPrivateMessage): boolean =>
        privateMessageStableId(message) === privateMessageStableId(receipt));
      if (!exists) {
        this.messages.push(receipt);
      }
      if (this.phase !== PrivateMessagePhase.LOADING) {
        this.phase = PrivateMessagePhase.READY;
      }
      return true;
    } catch (error) {
      if (this.isCurrent(generation)) {
        this.sendError = sendFailureMessage(error);
      }
      return false;
    } finally {
      if (this.isCurrent(generation)) {
        this.sending = false;
        this.emit();
      }
    }
  }

  private async fetchPage(generation: number, cursor?: string): Promise<void> {
    try {
      const pageRequest: Promise<ZhihuPrivateMessagePage> =
        this.repository.getPrivateMessagePage(this.peerId, cursor);
      let peerRequest: Promise<MobileNotificationAuthor> | undefined = undefined;
      if (this.peer === undefined && cursor === undefined) {
        peerRequest = this.repository.getPrivateMessagePeer(this.peerId).catch((_error: Error):
          MobileNotificationAuthor => {
          // 对齐上游：peer 信息失败不阻断会话列表
          return { id: '', name: '', urlToken: '', headline: '', avatarUrl: '' };
        });
      }
      const page = await pageRequest;
      if (!this.isCurrent(generation)) {
        return;
      }
      // /messages 返回新→旧，控制器内按旧→新存放（尾部为最新）。
      // 翻页游标（after_id）取的是更旧一批，必须前插到顶部，否则旧消息会
      // 被拼到最新消息之后，发出的消息就夹在了旧消息中间。
      const existing: Set<string> = new Set<string>();
      this.messages.forEach((message: ZhihuPrivateMessage): void => {
        existing.add(privateMessageStableId(message));
      });
      const block: Array<ZhihuPrivateMessage> = [];
      for (let index = page.items.length - 1; index >= 0; index -= 1) {
        const message = page.items[index];
        const id = privateMessageStableId(message);
        if (!existing.has(id)) {
          existing.add(id);
          block.push(message);
        }
      }
      if (cursor === undefined) {
        this.messages = block;
      } else {
        this.messages = block.concat(this.messages);
      }
      this.nextCursor = page.cursor.next;
      this.reachedEnd = page.cursor.isEnd || page.cursor.next === undefined;
      this.paginationBlocked = false;
      this.phase = this.messages.length === 0 ? PrivateMessagePhase.EMPTY : PrivateMessagePhase.READY;
      if (peerRequest !== undefined) {
        const peer = await peerRequest;
        if (this.isCurrent(generation) && peer.id.length > 0) {
          this.peer = peer;
        }
      }
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.phase = PrivateMessagePhase.ERROR;
      this.setFailure(error, false);
    } finally {
      if (this.isCurrent(generation)) {
        this.emit();
      }
    }
  }

  private chronological(): Array<ZhihuPrivateMessage> {
    return this.messages.slice();
  }

  private setFailure(error: Object, more: boolean): void {
    const authentication = error instanceof HttpFailure && error.kind === HttpFailureKind.AUTHENTICATION;
    this.requiresLogin = authentication && (error.status === undefined || error.status === 401);
    this.errorMessage = authentication && error.status === 403
      ? '请求被拒绝，可能需要完成知乎风控验证'
      : this.requiresLogin
        ? '私信需要登录，请登录后重试'
        : more ? '加载更多失败，请重试' : '私信加载失败，请检查网络后重试';
    this.paginationBlocked = more;
  }

  private isCurrent(generation: number): boolean {
    return this.active && generation === this.generation;
  }

  private emit(): void {
    if (this.active) {
      this.observer(this.snapshot());
    }
  }
}

function sendFailureMessage(error: Object): string {
  if (error instanceof HttpFailure) {
    if (error.kind === HttpFailureKind.AUTHENTICATION) {
      return error.status === 403 ? '发送被拒绝，可能需要完成知乎风控验证' : '登录状态不可用，请登录后重试';
    }
    if (error.kind === HttpFailureKind.RATE_LIMITED) {
      return '发送过于频繁，请稍后重试';
    }
    if (error.kind === HttpFailureKind.TIMEOUT) {
      return '发送超时，请重试';
    }
  }
  return '发送失败，请重试';
}
