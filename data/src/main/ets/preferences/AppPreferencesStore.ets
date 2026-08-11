import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';

const PREFERENCES_NAME = 'app_preferences';
const THEME_MODE_KEY = 'theme_mode';

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
    const businessError = error as BusinessError;
    if (typeof businessError.code === 'number') {
      return `${operation} failed (${businessError.code})`;
    }
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
      throw new Error(appPreferencesFailureMessage('Theme mode load', error as Object | null | undefined));
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

  private async writeThemeMode(mode: AppThemeMode): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.put(THEME_MODE_KEY, mode);
      await store.flush();
    } catch (error) {
      throw new Error(appPreferencesFailureMessage('Theme mode save', error as Object | null | undefined));
    }
  }
}
