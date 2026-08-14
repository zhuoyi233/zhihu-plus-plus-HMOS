import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import {
  BlockingPreferences,
  BlockingPreferencesGateway,
  defaultBlockingPreferences,
  normalizeBlockingPreferences
} from '../data/BlockingRuleStore';
import {
  defaultNotificationPreferences,
  NotificationKind,
  NotificationPreferences,
  NotificationSettingsGateway,
  normalizeNotificationPreferences
} from '../domain/NotificationModels';

const PREFERENCES_NAME = 'app_preferences';
const THEME_MODE_KEY = 'theme_mode';
const KEYWORD_BLOCKING_KEY = 'enable_keyword_blocking';
const USER_BLOCKING_KEY = 'enable_user_blocking';
const TOPIC_BLOCKING_KEY = 'enable_topic_blocking';
const TOPIC_BLOCKING_THRESHOLD_KEY = 'topic_blocking_threshold';
const NOTIFICATION_DISPLAY_PREFIX = 'notification_display_in_app_';
const NOTIFICATION_AUTO_MARK_READ_KEY = 'notification_auto_mark_as_read';
const NOTIFICATION_UNREAD_BADGE_KEY = 'notification_unread_badge';

function notificationDisplayKey(kind: NotificationKind): string {
  if (kind === NotificationKind.LIKE_COMMENT) {
    return `${NOTIFICATION_DISPLAY_PREFIX}like_comment`;
  }
  if (kind === NotificationKind.REPLY_COMMENT) {
    return `${NOTIFICATION_DISPLAY_PREFIX}reply_comment`;
  }
  if (kind === NotificationKind.INVITE_ANSWER) {
    return `${NOTIFICATION_DISPLAY_PREFIX}invite_answer`;
  }
  return `${NOTIFICATION_DISPLAY_PREFIX}like_answer`;
}

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

export class AppPreferencesStore implements BlockingPreferencesGateway, NotificationSettingsGateway {
  private readonly context: common.Context;
  private saveQueue: Promise<void> = Promise.resolve();

  constructor(context: common.Context) {
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

  async loadNotificationPreferences(): Promise<NotificationPreferences> {
    await this.saveQueue;
    try {
      const defaults = defaultNotificationPreferences();
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      const readBoolean = async (key: string, fallback: boolean): Promise<boolean> => {
        const value = await store.get(key, fallback);
        return typeof value === 'boolean' ? value : fallback;
      };
      const raw: NotificationPreferences = {
        likeAnswerDisplay: await readBoolean(notificationDisplayKey(NotificationKind.LIKE_ANSWER),
          defaults.likeAnswerDisplay),
        likeCommentDisplay: await readBoolean(notificationDisplayKey(NotificationKind.LIKE_COMMENT),
          defaults.likeCommentDisplay),
        replyCommentDisplay: await readBoolean(notificationDisplayKey(NotificationKind.REPLY_COMMENT),
          defaults.replyCommentDisplay),
        inviteAnswerDisplay: await readBoolean(notificationDisplayKey(NotificationKind.INVITE_ANSWER),
          defaults.inviteAnswerDisplay),
        autoMarkAsRead: await readBoolean(NOTIFICATION_AUTO_MARK_READ_KEY, defaults.autoMarkAsRead),
        unreadBadge: await readBoolean(NOTIFICATION_UNREAD_BADGE_KEY, defaults.unreadBadge)
      };
      return normalizeNotificationPreferences(raw);
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(appPreferencesFailureMessage('Notification preferences load', error));
      }
      throw new Error(appPreferencesFailureMessage('Notification preferences load', undefined));
    }
  }

  saveNotificationPreferences(value: NotificationPreferences): Promise<void> {
    const normalized = normalizeNotificationPreferences(value);
    const operation = this.saveQueue.then(
      (): Promise<void> => this.writeNotificationPreferences(normalized),
      (): Promise<void> => this.writeNotificationPreferences(normalized)
    );
    this.saveQueue = operation.then((): void => {}, (): void => {});
    return operation;
  }

  private async writeNotificationPreferences(value: NotificationPreferences): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.put(notificationDisplayKey(NotificationKind.LIKE_ANSWER), value.likeAnswerDisplay);
      await store.put(notificationDisplayKey(NotificationKind.LIKE_COMMENT), value.likeCommentDisplay);
      await store.put(notificationDisplayKey(NotificationKind.REPLY_COMMENT), value.replyCommentDisplay);
      await store.put(notificationDisplayKey(NotificationKind.INVITE_ANSWER), value.inviteAnswerDisplay);
      await store.put(NOTIFICATION_AUTO_MARK_READ_KEY, value.autoMarkAsRead);
      await store.put(NOTIFICATION_UNREAD_BADGE_KEY, value.unreadBadge);
      await store.flush();
    } catch (error) {
      if (error instanceof Error) {
        throw new Error(appPreferencesFailureMessage('Notification preferences save', error));
      }
      throw new Error(appPreferencesFailureMessage('Notification preferences save', undefined));
    }
  }
}
