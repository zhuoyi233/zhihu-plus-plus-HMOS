import {
  LoginVerificationResult,
  LoginVerificationStatus,
  ZhihuLoginClient,
  ZhihuProfile
} from '../network/ZhihuLoginClient';
import { SessionCookieProvider } from '../network/ZhihuHttpClient';
import { copySessionCookies, parseCookieAssignments, SessionCookie } from './CookieSession';

export interface SessionPersistence {
  save(cookies: Array<SessionCookie>, now?: number): Promise<void>;
  load(now?: number): Promise<Array<SessionCookie>>;
  clear(): Promise<void>;
}

export interface SessionVerifier {
  verify(cookies: Array<SessionCookie>): Promise<LoginVerificationResult>;
  cancel(): void;
}

export enum SessionStatus {
  GUEST = 'guest',
  AUTHENTICATED = 'authenticated',
  EXPIRED = 'expired',
  ERROR = 'error'
}

export interface SessionState {
  status: SessionStatus;
  message: string;
  hasRetainedCredentials: boolean;
  profile?: ZhihuProfile;
}

export interface SessionLoginOperation {
  readonly result: Promise<SessionState>;
  cancel(): void;
}

export interface LoginSessionGateway {
  getState(): SessionState;
  retryRetainedSession(): Promise<SessionState>;
  beginLoginWithCookieHeader(rawCookie: string): SessionLoginOperation;
  beginLoginWithCookies(cookies: Array<SessionCookie>): SessionLoginOperation;
  logout(): Promise<SessionState>;
}

const INITIAL_SESSION_STATE: SessionState = {
  status: SessionStatus.GUEST,
  message: '当前为游客模式',
  hasRetainedCredentials: false
};

class LoginOperationToken {
  cancelled: boolean = false;
  cancellable: boolean = true;
}

class RepositorySessionLoginOperation implements SessionLoginOperation {
  readonly result: Promise<SessionState>;
  private readonly cancelAction: () => void;
  private cancelled: boolean = false;

  constructor(result: Promise<SessionState>, cancelAction: () => void) {
    this.result = result;
    this.cancelAction = cancelAction;
  }

  cancel(): void {
    if (this.cancelled) {
      return;
    }
    this.cancelled = true;
    this.cancelAction();
  }
}

export class SessionRepository implements SessionCookieProvider, LoginSessionGateway {
  private readonly persistence: SessionPersistence;
  private readonly verifier: SessionVerifier;
  private cookies: Array<SessionCookie> = [];
  private state: SessionState = INITIAL_SESSION_STATE;
  private operationQueue: Promise<SessionState> = Promise.resolve(INITIAL_SESSION_STATE);
  private activeLoginToken?: LoginOperationToken;

  constructor(persistence: SessionPersistence, verifier: SessionVerifier = new ZhihuLoginClient()) {
    this.persistence = persistence;
    this.verifier = verifier;
  }

  getCookies(): Array<SessionCookie> {
    return copySessionCookies(this.cookies);
  }

  getState(): SessionState {
    return this.copyState(this.state);
  }

  load(): Promise<SessionState> {
    return this.enqueue(async (): Promise<SessionState> => {
      const previousCookies = copySessionCookies(this.cookies);
      const previousState = this.copyState(this.state);
      const hadAuthenticatedSession = previousState.status === SessionStatus.AUTHENTICATED &&
        previousCookies.length > 0;
      try {
        const storedCookies = await this.persistence.load();
        if (storedCookies.length === 0) {
          this.cookies = [];
          return this.updateState(INITIAL_SESSION_STATE);
        }
        return await this.verifyRestoredSession(copySessionCookies(storedCookies), previousCookies,
          previousState, hadAuthenticatedSession);
      } catch (_error) {
        if (hadAuthenticatedSession) {
          this.cookies = previousCookies;
          return this.updateState(previousState);
        }
        this.cookies = [];
        return this.updateState({
          status: SessionStatus.ERROR,
          message: '登录恢复失败；本地会话未改动',
          hasRetainedCredentials: true
        });
      }
    });
  }

  retryRetainedSession(): Promise<SessionState> {
    if (!this.state.hasRetainedCredentials) {
      return Promise.resolve(this.getState());
    }
    return this.load();
  }

  loginWithCookieHeader(rawCookie: string): Promise<SessionState> {
    return this.beginLoginWithCookieHeader(rawCookie).result;
  }

  loginWithCookies(cookies: Array<SessionCookie>): Promise<SessionState> {
    return this.beginLoginWithCookies(cookies).result;
  }

  beginLoginWithCookieHeader(rawCookie: string): SessionLoginOperation {
    return this.beginLoginWithCookies(parseCookieAssignments(rawCookie));
  }

  beginLoginWithCookies(cookies: Array<SessionCookie>): SessionLoginOperation {
    const candidateCookies = copySessionCookies(cookies);
    const token = new LoginOperationToken();
    const operationResult = this.enqueue(async (): Promise<SessionState> => {
      if (token.cancelled) {
        return this.getState();
      }
      this.activeLoginToken = token;
      let verification: LoginVerificationResult;
      try {
        verification = await this.verifier.verify(copySessionCookies(candidateCookies));
      } catch (_error) {
        if (token.cancelled) {
          return this.getState();
        }
        return this.updateState({
          status: SessionStatus.ERROR,
          message: '登录验证失败，请稍后重试',
          hasRetainedCredentials: this.cookies.length > 0,
          profile: this.state.profile
        });
      } finally {
        if (this.activeLoginToken === token) {
          this.activeLoginToken = undefined;
        }
      }
      if (token.cancelled) {
        return this.getState();
      }
      if (verification.status !== LoginVerificationStatus.AUTHENTICATED || verification.profile === undefined) {
        token.cancellable = false;
        return this.updateState({
          status: SessionStatus.ERROR,
          message: verification.message,
          hasRetainedCredentials: this.cookies.length > 0,
          profile: this.state.profile
        });
      }

      token.cancellable = false;
      try {
        await this.persistence.save(copySessionCookies(candidateCookies));
      } catch (_error) {
        return this.updateState({
          status: SessionStatus.ERROR,
          message: 'Cookie 已验证，但加密保存失败',
          hasRetainedCredentials: this.cookies.length > 0,
          profile: this.state.profile
        });
      }
      this.cookies = copySessionCookies(candidateCookies);
      return this.updateState({
        status: SessionStatus.AUTHENTICATED,
        message: `已登录：${verification.profile.name}`,
        hasRetainedCredentials: true,
        profile: verification.profile
      });
    });
    return new RepositorySessionLoginOperation(operationResult, (): void => this.cancelLoginOperation(token));
  }

  logout(): Promise<SessionState> {
    return this.enqueue(async (): Promise<SessionState> => {
      this.cookies = [];
      this.state = INITIAL_SESSION_STATE;
      try {
        await this.persistence.clear();
        return this.updateState({
          status: SessionStatus.GUEST,
          message: '已退出登录并清理本地会话',
          hasRetainedCredentials: false
        });
      } catch (_error) {
        return this.updateState({
          status: SessionStatus.ERROR,
          message: '退出清理失败，请重试',
          hasRetainedCredentials: true
        });
      }
    });
  }

  cancelVerification(): void {
    if (this.activeLoginToken !== undefined) {
      this.activeLoginToken.cancelled = true;
    }
    this.verifier.cancel();
  }

  private cancelLoginOperation(token: LoginOperationToken): void {
    if (!token.cancellable) {
      return;
    }
    token.cancelled = true;
    if (this.activeLoginToken === token) {
      this.verifier.cancel();
    }
  }

  private enqueue(operation: () => Promise<SessionState>): Promise<SessionState> {
    const next = this.operationQueue.then(operation, operation);
    this.operationQueue = next;
    return next;
  }

  private async verifyRestoredSession(cookies: Array<SessionCookie>, previousCookies: Array<SessionCookie>,
    previousState: SessionState, hadAuthenticatedSession: boolean): Promise<SessionState> {
    const result = await this.verifier.verify(cookies);
    if (result.status === LoginVerificationStatus.AUTHENTICATED && result.profile !== undefined) {
      this.cookies = copySessionCookies(cookies);
      return this.updateState({
        status: SessionStatus.AUTHENTICATED,
        message: `已登录：${result.profile.name}`,
        hasRetainedCredentials: true,
        profile: result.profile
      });
    }
    const definitelyExpired = result.status === LoginVerificationStatus.INVALID_INPUT ||
      (result.status === LoginVerificationStatus.REJECTED && result.rejectionStatus === 401);
    if (definitelyExpired) {
      this.cookies = [];
      this.state = INITIAL_SESSION_STATE;
      try {
        await this.persistence.clear();
        return this.updateState({
          status: SessionStatus.EXPIRED,
          message: `${result.message}，已清理本地会话`,
          hasRetainedCredentials: false
        });
      } catch (_error) {
        return this.updateState({
          status: SessionStatus.ERROR,
          message: '登录已失效，但本地会话清理失败',
          hasRetainedCredentials: true
        });
      }
    }
    if (hadAuthenticatedSession) {
      this.cookies = previousCookies;
      return this.updateState(previousState);
    }
    this.cookies = [];
    return this.updateState({
      status: SessionStatus.ERROR,
      message: `${result.message}；本地会话已保留`,
      hasRetainedCredentials: true
    });
  }

  private updateState(state: SessionState): SessionState {
    this.state = this.copyState(state);
    return this.copyState(this.state);
  }

  private copyState(state: SessionState): SessionState {
    const profile = state.profile;
    return {
      status: state.status,
      message: state.message,
      hasRetainedCredentials: state.hasRetainedCredentials,
      profile: profile === undefined ? undefined : {
        id: profile.id,
        name: profile.name,
        urlToken: profile.urlToken,
        userType: profile.userType,
        avatarUrl: profile.avatarUrl
      }
    };
  }
}
