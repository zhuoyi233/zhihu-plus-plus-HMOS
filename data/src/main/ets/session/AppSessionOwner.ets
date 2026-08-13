import { common } from '@kit.AbilityKit';
import { CookieSessionStore } from './CookieSessionStore';
import { SessionRepository, SessionState } from './SessionRepository';

export type SessionRepositoryFactory = () => SessionRepository;

export class AppSessionOwner {
  private readonly factory: SessionRepositoryFactory;
  private repository?: SessionRepository;
  private restoreRun?: Promise<SessionState>;

  constructor(factory: SessionRepositoryFactory) {
    this.factory = factory;
  }

  getRepository(): SessionRepository {
    if (this.repository === undefined) {
      this.repository = this.factory();
    }
    return this.repository;
  }

  restoreDeferred(): Promise<SessionState> {
    if (this.restoreRun === undefined) {
      this.restoreRun = this.getRepository().load();
    }
    return this.restoreRun;
  }

  cancelInFlightVerification(): void {
    this.repository?.cancelVerification();
    this.restoreRun = undefined;
  }
}

let appSessionOwner: AppSessionOwner | undefined = undefined;

export function getAppSessionOwner(context: common.Context): AppSessionOwner {
  if (appSessionOwner === undefined) {
    const applicationContext = context.getApplicationContext();
    appSessionOwner = new AppSessionOwner((): SessionRepository =>
      new SessionRepository(new CookieSessionStore(applicationContext)));
  }
  return appSessionOwner;
}
