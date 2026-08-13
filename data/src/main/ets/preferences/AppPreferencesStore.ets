import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import {
  BlockingPreferences,
  defaultBlockingPreferences,
  normalizeBlockingPreferences
} from '../data/BlockingRuleStore';

const PREFERENCES_NAME = 'app_preferences';
const THEME_MODE_KEY = 'theme_mode';
const KEYWORD_BLOCKING_KEY = 'enable_keyword_blocking';
const USER_BLOCKING_KEY = 'enable_user_blocking';
const TOPIC_BLOCKING_KEY = 'enable_topic_blocking';
const TOPIC_BLOCKING_THRESHOLD_KEY = 'topic_blocking_threshold';

export enum AppThemeMode {
  SYSTEM = 0,
  LIGHT = 1,
  DARK = 2
}

export function decodeAppThemeMode(value: preferences.ValueType): AppThemeMode {
  if (value === AppThemeMode.LIGHT) {
    return AppThemeMode.LIGHT;
  }
  if (value === AppThemeMode.DARK) {
    return AppThemeMode.DARK;
  }
  return AppThemeMode.SYSTEM;
}

export function appPreferencesFailureMessage(operation: string, error: Object | null | undefined): string {
  if (error instanceof Error) {
    if (error.message.trim().length > 0) {
      return `${operation} failed: ${error.message}`;
    }
  }
  return `${operation} failed`;
}

export class AppPreferencesStore {
  private readonly context: common.UIAbilityContext;
  private saveQueue: Promise<void> = Promise.resolve();

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async loadThemeMode(): Promise<AppThemeMode> {
    await this.saveQueue;
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      return decodeAppThemeMode(await store.get(THEME_MODE_KEY, AppThemeMode.SYSTEM));
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(appPreferencesFailureMessage('Theme mode load', error));
      }
      throw new Error(appPreferencesFailureMessage('Theme mode load', undefined));
    }
  }

  saveThemeMode(mode: AppThemeMode): Promise<void> {
    const normalizedMode = decodeAppThemeMode(mode);
    const operation = this.saveQueue.then(
      (): Promise<void> => this.writeThemeMode(normalizedMode),
      (): Promise<void> => this.writeThemeMode(normalizedMode)
    );
    this.saveQueue = operation.then(
      (): void => {},
      (): void => {}
    );
    return operation;
  }

  async loadBlockingPreferences(): Promise<BlockingPreferences> {
    await this.saveQueue;
    try {
      const defaults = defaultBlockingPreferences();
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      const keywordEnabled = await store.get(KEYWORD_BLOCKING_KEY, defaults.keywordBlockingEnabled);
      const userEnabled = await store.get(USER_BLOCKING_KEY, defaults.userBlockingEnabled);
      const topicEnabled = await store.get(TOPIC_BLOCKING_KEY, defaults.topicBlockingEnabled);
      const threshold = await store.get(TOPIC_BLOCKING_THRESHOLD_KEY, defaults.topicBlockingThreshold);
      return normalizeBlockingPreferences({
        keywordBlockingEnabled: typeof keywordEnabled === 'boolean' ? keywordEnabled : true,
        userBlockingEnabled: typeof userEnabled === 'boolean' ? userEnabled : true,
        topicBlockingEnabled: typeof topicEnabled === 'boolean' ? topicEnabled : true,
        topicBlockingThreshold: typeof threshold === 'number' ? threshold : 1
      });
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(appPreferencesFailureMessage('Blocking preferences load', error));
      }
      throw new Error(appPreferencesFailureMessage('Blocking preferences load', undefined));
    }
  }

  saveBlockingPreferences(value: BlockingPreferences): Promise<void> {
    const normalized = normalizeBlockingPreferences(value);
    const operation = this.saveQueue.then(
      (): Promise<void> => this.writeBlockingPreferences(normalized),
      (): Promise<void> => this.writeBlockingPreferences(normalized)
    );
    this.saveQueue = operation.then((): void => {}, (): void => {});
    return operation;
  }

  private async writeThemeMode(mode: AppThemeMode): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.put(THEME_MODE_KEY, mode);
      await store.flush();
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(appPreferencesFailureMessage('Theme mode save', error));
      }
      throw new Error(appPreferencesFailureMessage('Theme mode save', undefined));
    }
  }

  private async writeBlockingPreferences(value: BlockingPreferences): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.put(KEYWORD_BLOCKING_KEY, value.keywordBlockingEnabled);
      await store.put(USER_BLOCKING_KEY, value.userBlockingEnabled);
      await store.put(TOPIC_BLOCKING_KEY, value.topicBlockingEnabled);
      await store.put(TOPIC_BLOCKING_THRESHOLD_KEY, value.topicBlockingThreshold);
      await store.flush();
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(appPreferencesFailureMessage('Blocking preferences save', error));
      }
      throw new Error(appPreferencesFailureMessage('Blocking preferences save', undefined));
    }
  }
}
