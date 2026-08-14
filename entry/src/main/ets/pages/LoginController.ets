import {
  LoginSessionGateway,
  QrLoginGateway,
  QrLoginState,
  QrLoginStatus,
  SessionCookie,
  SessionLoginOperation,
  SessionState,
  SessionStatus,
  ZHIHU_QR_POLL_INTERVAL_MS
} from 'data';

export enum LoginPhase {
  GUEST = 'guest',
  AUTHENTICATED = 'authenticated',
  SESSION_EXPIRED = 'session_expired',
  VERIFYING_COOKIE = 'verifying_cookie',
  LOGGING_OUT = 'logging_out',
  QR_STARTING = 'qr_starting',
  QR_READY = 'qr_ready',
  QR_WAITING_CONFIRMATION = 'qr_waiting_confirmation',
  QR_VERIFYING_ACCOUNT = 'qr_verifying_account',
  QR_EXPIRED = 'qr_expired',
  QR_CANCELLED = 'qr_cancelled',
  RISK_CONTROL = 'risk_control',
  PAUSED = 'paused',
  ERROR = 'error'
}

export interface LoginViewState {
  readonly phase: LoginPhase;
  readonly message: string;
  readonly profileName?: string;
  readonly qrLink?: string;
  readonly qrExpiresAt?: number;
  readonly riskControlUrl?: string;
  readonly manualLoginEnabled: boolean;
  readonly qrStartEnabled: boolean;
  readonly qrCancelable: boolean;
  readonly logoutEnabled: boolean;
  readonly retainedSessionRetryEnabled: boolean;
}

export interface LoginPollScheduler {
  schedule(task: () => Promise<void>, delayMs: number): number;
  cancel(taskId: number): void;
}

export type LoginStateObserver = (state: LoginViewState) => void;

export function completesUserAuthentication(previous: LoginPhase, next: LoginPhase): boolean {
  return next === LoginPhase.AUTHENTICATED &&
    (previous === LoginPhase.VERIFYING_COOKIE || previous === LoginPhase.QR_VERIFYING_ACCOUNT);
}

class SystemLoginPollScheduler implements LoginPollScheduler {
  schedule(task: () => Promise<void>, delayMs: number): number {
    return setTimeout((): void => {
      task();
    }, delayMs);
  }

  cancel(taskId: number): void {
    clearTimeout(taskId);
  }
}

export class LoginController {
  private readonly session: LoginSessionGateway;
  private readonly qrClient: QrLoginGateway;
  private readonly scheduler: LoginPollScheduler;
  private readonly observer: LoginStateObserver;
  private active: boolean = false;
  private foreground: boolean = true;
  private generation: number = 0;
  private activeSessionOperation?: SessionLoginOperation;
  private pollTaskId?: number;
  private state: LoginViewState;

  constructor(session: LoginSessionGateway, qrClient: QrLoginGateway,
    observer: LoginStateObserver = (_state: LoginViewState): void => {
    }, scheduler: LoginPollScheduler = new SystemLoginPollScheduler()) {
    this.session = session;
    this.qrClient = qrClient;
    this.scheduler = scheduler;
    this.observer = observer;
    this.state = this.sessionViewState(session.getState());
  }

  activate(): void {
    if (this.active) {
      return;
    }
    this.active = true;
    this.foreground = true;
    this.update(this.sessionViewState(this.session.getState()));
  }

  deactivate(): void {
    if (!this.active) {
      return;
    }
    this.active = false;
    this.invalidateActiveWork();
  }

  setForeground(foreground: boolean): void {
    if (!this.active || foreground === this.foreground) {
      return;
    }
    this.foreground = foreground;
    if (foreground) {
      this.update(this.sessionViewState(this.session.getState()));
      return;
    }
    const interrupted = this.isBusyOrQrPhase(this.state.phase);
    this.invalidateActiveWork();
    const message = interrupted
      ? '登录流程已在后台暂停，请回到前台后重试'
      : '登录功能已暂停，请回到前台后重试';
    this.update(this.viewState(LoginPhase.PAUSED, message));
  }

  snapshot(): LoginViewState {
    return this.copyState(this.state);
  }

  async loginWithCookieHeader(rawCookie: string): Promise<void> {
    if (!this.canStartUserAction()) {
      return;
    }
    const generation = this.beginUserAction();
    this.update(this.viewState(LoginPhase.VERIFYING_COOKIE, '正在验证 Cookie'));
    const operation = this.session.beginLoginWithCookieHeader(rawCookie);
    this.activeSessionOperation = operation;
    try {
      const result = await operation.result;
      if (this.isCurrent(generation)) {
        this.update(this.sessionViewState(result));
      }
    } catch (_error) {
      if (this.isCurrent(generation)) {
        this.update(this.viewState(LoginPhase.ERROR, 'Cookie 验证失败，请稍后重试'));
      }
    } finally {
      this.finishSessionOperation(operation);
    }
  }

  async retryRetainedSession(): Promise<void> {
    if (!this.canStartUserAction() || !this.state.retainedSessionRetryEnabled) {
      return;
    }
    const generation = this.beginUserAction();
    this.update(this.viewState(LoginPhase.VERIFYING_COOKIE, '正在验证已保留会话'));
    try {
      const result = await this.session.retryRetainedSession();
      if (this.isCurrent(generation)) {
        this.update(this.sessionViewState(result));
      }
    } catch (_error) {
      if (this.isCurrent(generation)) {
        this.update(this.viewState(LoginPhase.ERROR, '已保留会话验证失败，请稍后重试', undefined,
          undefined, undefined, undefined, true));
      }
    }
  }

  async startQrLogin(): Promise<void> {
    if (!this.canStartUserAction()) {
      return;
    }
    const sessionState = this.session.getState();
    if (sessionState.status === SessionStatus.AUTHENTICATED) {
      this.update(this.sessionViewState(sessionState));
      return;
    }
    const generation = this.beginUserAction();
    this.update(this.viewState(LoginPhase.QR_STARTING, '正在获取登录二维码'));
    try {
      const qrState = await this.qrClient.start([]);
      if (this.isCurrent(generation)) {
        await this.applyQrState(qrState, generation);
      }
    } catch (_error) {
      if (this.isCurrent(generation)) {
        this.update(this.viewState(LoginPhase.ERROR, '二维码获取失败，请重试'));
      }
    }
  }

  cancelQrLogin(): void {
    if (!this.active) {
      return;
    }
    this.generation += 1;
    this.cancelScheduledPoll();
    this.qrClient.cancel();
    this.cancelOwnedSessionVerification();
    this.update(this.viewState(LoginPhase.QR_CANCELLED, '二维码登录已取消'));
  }

  async logout(): Promise<void> {
    if (!this.active || !this.state.logoutEnabled || this.isBusyPhase(this.state.phase)) {
      return;
    }
    const generation = this.beginUserAction();
    this.update(this.viewState(LoginPhase.LOGGING_OUT, '正在退出登录'));
    try {
      const result = await this.session.logout();
      if (this.isCurrent(generation)) {
        this.update(this.sessionViewState(result));
      }
    } catch (_error) {
      if (this.isCurrent(generation)) {
        this.update(this.viewState(LoginPhase.ERROR, '退出登录失败，请重试'));
      }
    }
  }

  private async applyQrState(qrState: QrLoginState, generation: number): Promise<void> {
    if (qrState.status === QrLoginStatus.CREDENTIAL_READY) {
      await this.verifyQrCredentials(generation);
      return;
    }
    let phase = LoginPhase.ERROR;
    if (qrState.status === QrLoginStatus.READY) {
      phase = LoginPhase.QR_READY;
    } else if (qrState.status === QrLoginStatus.WAITING_CONFIRMATION) {
      phase = LoginPhase.QR_WAITING_CONFIRMATION;
    } else if (qrState.status === QrLoginStatus.EXPIRED) {
      phase = LoginPhase.QR_EXPIRED;
    } else if (qrState.status === QrLoginStatus.CANCELLED) {
      phase = LoginPhase.QR_CANCELLED;
    } else if (qrState.status === QrLoginStatus.RISK_CONTROL) {
      phase = LoginPhase.RISK_CONTROL;
    } else if (qrState.status === QrLoginStatus.BUSY) {
      phase = LoginPhase.QR_STARTING;
    }
    const keepQrLink = phase === LoginPhase.QR_READY || phase === LoginPhase.QR_WAITING_CONFIRMATION;
    this.update(this.viewState(phase, qrState.message,
      keepQrLink ? qrState.qrLink ?? this.state.qrLink : undefined,
      keepQrLink ? qrState.expiresAt ?? this.state.qrExpiresAt : undefined,
      phase === LoginPhase.RISK_CONTROL ? qrState.riskControlUrl : undefined));
    if (keepQrLink) {
      this.scheduleNextPoll(generation);
    }
  }

  private async pollQr(generation: number): Promise<void> {
    if (!this.isCurrent(generation)) {
      return;
    }
    try {
      const qrState = await this.qrClient.pollOnce();
      if (this.isCurrent(generation)) {
        await this.applyQrState(qrState, generation);
      }
    } catch (_error) {
      if (this.isCurrent(generation)) {
        this.update(this.viewState(LoginPhase.ERROR, '二维码状态查询失败，请重试'));
      }
    }
  }

  private async verifyQrCredentials(generation: number): Promise<void> {
    const cookies = this.qrClient.getCandidateCookies();
    if (cookies.length === 0) {
      this.update(this.viewState(LoginPhase.ERROR, '扫码凭据不完整，请重新获取二维码'));
      return;
    }
    this.cancelScheduledPoll();
    this.update(this.viewState(LoginPhase.QR_VERIFYING_ACCOUNT, '扫码完成，正在验证账号'));
    const operation = this.session.beginLoginWithCookies(cookies);
    this.activeSessionOperation = operation;
    try {
      const result = await operation.result;
      if (!this.isCurrent(generation)) {
        return;
      }
      this.qrClient.cancel();
      if (result.status === SessionStatus.AUTHENTICATED) {
        this.update(this.sessionViewState(result));
      } else {
        this.update(this.viewState(LoginPhase.ERROR, result.message));
      }
    } catch (_error) {
      if (this.isCurrent(generation)) {
        this.qrClient.cancel();
        this.update(this.viewState(LoginPhase.ERROR, '扫码凭据验证失败，请重新获取二维码'));
      }
    } finally {
      this.finishSessionOperation(operation);
    }
  }

  private scheduleNextPoll(generation: number): void {
    this.cancelScheduledPoll();
    if (!this.isCurrent(generation)) {
      return;
    }
    this.pollTaskId = this.scheduler.schedule(async (): Promise<void> => {
      this.pollTaskId = undefined;
      await this.pollQr(generation);
    }, ZHIHU_QR_POLL_INTERVAL_MS);
  }

  private beginUserAction(): number {
    this.generation += 1;
    this.cancelScheduledPoll();
    this.qrClient.cancel();
    this.cancelOwnedSessionVerification();
    return this.generation;
  }

  private invalidateActiveWork(): void {
    this.generation += 1;
    this.cancelScheduledPoll();
    this.qrClient.cancel();
    this.cancelOwnedSessionVerification();
  }

  private cancelOwnedSessionVerification(): void {
    const operation = this.activeSessionOperation;
    if (operation === undefined) {
      return;
    }
    this.activeSessionOperation = undefined;
    operation.cancel();
  }

  private finishSessionOperation(operation: SessionLoginOperation): void {
    if (this.activeSessionOperation === operation) {
      this.activeSessionOperation = undefined;
    }
  }

  private cancelScheduledPoll(): void {
    const taskId = this.pollTaskId;
    this.pollTaskId = undefined;
    if (taskId !== undefined) {
      this.scheduler.cancel(taskId);
    }
  }

  private canStartUserAction(): boolean {
    return this.active && this.foreground && !this.isBusyPhase(this.state.phase);
  }

  private isCurrent(generation: number): boolean {
    return this.active && this.foreground && generation === this.generation;
  }

  private isBusyPhase(phase: LoginPhase): boolean {
    return phase === LoginPhase.VERIFYING_COOKIE || phase === LoginPhase.LOGGING_OUT ||
      phase === LoginPhase.QR_STARTING || phase === LoginPhase.QR_VERIFYING_ACCOUNT;
  }

  private isBusyOrQrPhase(phase: LoginPhase): boolean {
    return this.isBusyPhase(phase) || phase === LoginPhase.QR_READY ||
      phase === LoginPhase.QR_WAITING_CONFIRMATION;
  }

  private sessionViewState(session: SessionState): LoginViewState {
    if (session.status === SessionStatus.AUTHENTICATED && session.profile !== undefined) {
      return this.viewState(LoginPhase.AUTHENTICATED, session.message, undefined, undefined, undefined,
        session.profile.name);
    }
    if (session.status === SessionStatus.EXPIRED) {
      return this.viewState(LoginPhase.SESSION_EXPIRED, session.message);
    }
    if (session.status === SessionStatus.ERROR) {
      return this.viewState(LoginPhase.ERROR, session.message, undefined, undefined, undefined,
        session.profile?.name, session.hasRetainedCredentials);
    }
    return this.viewState(LoginPhase.GUEST, session.message);
  }

  private viewState(phase: LoginPhase, message: string, qrLink?: string, qrExpiresAt?: number,
    riskControlUrl?: string, profileName?: string, retainedSessionRetryEnabled: boolean = false): LoginViewState {
    const busy = this.isBusyPhase(phase);
    const interactive = this.active && this.foreground;
    const authenticated = this.session.getState().status === SessionStatus.AUTHENTICATED;
    const qrCancelable = phase === LoginPhase.QR_READY || phase === LoginPhase.QR_WAITING_CONFIRMATION ||
      phase === LoginPhase.QR_STARTING;
    return {
      phase: phase,
      message: message,
      profileName: profileName,
      qrLink: qrLink,
      qrExpiresAt: qrExpiresAt,
      riskControlUrl: riskControlUrl,
      manualLoginEnabled: interactive && !busy,
      qrStartEnabled: interactive && !busy && !qrCancelable && !authenticated,
      qrCancelable: interactive && qrCancelable,
      logoutEnabled: interactive && !busy && this.session.getState().hasRetainedCredentials,
      retainedSessionRetryEnabled: interactive && !busy && retainedSessionRetryEnabled
    };
  }

  private update(state: LoginViewState): void {
    this.state = this.copyState(state);
    if (this.active) {
      this.observer(this.copyState(this.state));
    }
  }

  private copyState(state: LoginViewState): LoginViewState {
    return {
      phase: state.phase,
      message: state.message,
      profileName: state.profileName,
      qrLink: state.qrLink,
      qrExpiresAt: state.qrExpiresAt,
      riskControlUrl: state.riskControlUrl,
      manualLoginEnabled: state.manualLoginEnabled,
      qrStartEnabled: state.qrStartEnabled,
      qrCancelable: state.qrCancelable,
      logoutEnabled: state.logoutEnabled,
      retainedSessionRetryEnabled: state.retainedSessionRetryEnabled
    };
  }
}
