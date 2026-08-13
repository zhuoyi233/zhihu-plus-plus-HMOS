import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import {
  decodeCookieSession,
  encodeCookieSession,
  removeExpiredCookies,
  SessionCookie
} from './CookieSession';
import { decryptSession, encryptSession } from './SessionCipher';
import { SessionKeyStore } from './SessionKeyStore';
import { SessionPersistence } from './SessionRepository';

const PREFERENCES_NAME = 'secure_session';
const ENCRYPTED_SESSION_KEY = 'cookie_session_v1';

export class CookieSessionStore implements SessionPersistence {
  private readonly context: common.Context;
  private readonly keyStore: SessionKeyStore;

  constructor(context: common.Context, keyStore: SessionKeyStore = new SessionKeyStore()) {
    this.context = context;
    this.keyStore = keyStore;
  }

  async save(cookies: Array<SessionCookie>, now: number = Date.now()): Promise<void> {
    const activeCookies = removeExpiredCookies(cookies, now);
    const keyData = await this.keyStore.getOrCreate();
    try {
      const encrypted = await encryptSession(encodeCookieSession(activeCookies, now), keyData);
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.put(ENCRYPTED_SESSION_KEY, encrypted);
      await store.flush();
    } catch (_error) {
      throw this.storeError('Session save');
    } finally {
      keyData.fill(0);
    }
  }

  async load(now: number = Date.now()): Promise<Array<SessionCookie>> {
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      const encryptedValue = await store.get(ENCRYPTED_SESSION_KEY, '');
      if (typeof encryptedValue !== 'string' || encryptedValue.length === 0) {
        return [];
      }

      const keyData = await this.keyStore.load();
      if (keyData === undefined) {
        await this.removeEncryptedSession(store);
        return [];
      }

      let cookies: Array<SessionCookie>;
      try {
        cookies = decodeCookieSession(await decryptSession(encryptedValue, keyData)).cookies;
      } catch (_error) {
        await this.removeEncryptedSession(store);
        return [];
      } finally {
        keyData.fill(0);
      }

      const activeCookies = removeExpiredCookies(cookies, now);
      if (activeCookies.length !== cookies.length) {
        await this.save(activeCookies, now);
      }
      return activeCookies;
    } catch (_error) {
      throw this.storeError('Session load');
    }
  }

  async clear(): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await this.removeEncryptedSession(store);
      await this.keyStore.clear();
    } catch (_error) {
      throw this.storeError('Session clear');
    }
  }

  private async removeEncryptedSession(store: preferences.Preferences): Promise<void> {
    try {
      await store.delete(ENCRYPTED_SESSION_KEY);
      await store.flush();
    } catch (_error) {
      throw this.storeError('Encrypted session removal');
    }
  }

  private storeError(operation: string): Error {
    return new Error(`${operation} failed`);
  }
}
