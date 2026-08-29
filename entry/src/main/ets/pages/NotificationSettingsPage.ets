import {
  NotificationKind,
  NotificationPreferences,
  NotificationSettingsGateway,
  NOTIFICATION_KINDS,
  notificationKindInfo
} from 'data';
import { common } from '@kit.AbilityKit';
import notificationManager from '@ohos.notificationManager';

@Component
export struct NotificationSettingsPage {
  settings: NotificationSettingsGateway | undefined = undefined;
  @State private preferences: NotificationPreferences = {
    likeAnswerDisplay: true,
    likeCommentDisplay: true,
    replyCommentDisplay: true,
    inviteAnswerDisplay: false,
    autoMarkAsRead: false,
    unreadBadge: true
  };
  @State private loaded: boolean = false;
  @State private saveStatus: string = '';
  @State private systemNotificationStatus: string = '正在读取系统通知状态…';
  @State private systemNotificationSettingsOpening: boolean = false;

  aboutToAppear(): void {
    this.refreshSystemNotificationStatus();
    const settings = this.settings;
    if (settings === undefined) {
      this.saveStatus = '通知设置数据源未配置';
      return;
    }
    settings.loadNotificationPreferences().then((preferences: NotificationPreferences): void => {
      this.preferences = preferences;
      this.loaded = true;
      this.saveStatus = '';
    }).catch((_error: Error): void => {
      this.loaded = true;
      this.saveStatus = '读取通知设置失败，显示默认值';
    });
  }

  build() {
    Scroll() {
      Column({ space: $r('app.float.p1_spacing_medium') }) {
        if (this.saveStatus.length > 0) {
          Text(this.saveStatus)
            .id('p3_notifications_settings_status')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
        }

        Column({ space: $r('app.float.p1_spacing_small') }) {
          Text('阅读行为')
            .fontSize($r('app.float.p1_heading_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
          this.settingRow(
            '打开通知自动已读',
            '进入通知页后自动把当前批次标记为已读',
            this.preferences.autoMarkAsRead,
            'p3_notifications_settings_auto_read',
            (checked: boolean): void => {
              this.updatePreferences(withAutoMarkAsRead(this.preferences, checked));
            }
          )
          this.settingRow(
            '显示未读红点',
            '在通知分类上显示未读数量',
            this.preferences.unreadBadge,
            'p3_notifications_settings_unread_badge',
            (checked: boolean): void => {
              this.updatePreferences(withUnreadBadge(this.preferences, checked));
            }
          )
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding($r('app.float.p1_card_padding'))
        .borderRadius($r('app.float.p1_card_radius'))
        .backgroundColor($r('app.color.surface_background'))

        Column({ space: $r('app.float.p1_spacing_small') }) {
          Text('系统通知')
            .fontSize($r('app.float.p1_heading_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
          Text('通知授权和提醒方式由 HarmonyOS 在应用级统一管理，不按消息类型复制 Android 通知渠道。')
            .fontSize($r('app.float.p1_caption_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
          Text(this.systemNotificationStatus)
            .id('p3_notifications_settings_system_status')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
          Button(this.systemNotificationSettingsOpening ? '正在打开系统通知设置…' : '管理系统通知')
            .id('p3_notifications_settings_system_open')
            .width('100%')
            .fontSize($r('app.float.p1_body_font_size'))
            .enabled(!this.systemNotificationSettingsOpening)
            .onClick((): void => {
              this.openSystemNotificationSettings();
            })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding($r('app.float.p1_card_padding'))
        .borderRadius($r('app.float.p1_card_radius'))
        .backgroundColor($r('app.color.surface_background'))

        Column({ space: $r('app.float.p1_spacing_small') }) {
          Text('应用内显示')
            .fontSize($r('app.float.p1_heading_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
          Text('选择在通知页面显示哪些通知；默认策略与上游一致（邀请回答默认关闭）')
            .fontSize($r('app.float.p1_caption_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
          ForEach(NOTIFICATION_KINDS, (kind: NotificationKind) => {
            this.settingRow(
              notificationKindInfo(kind).displayName,
              '',
              this.displayEnabled(kind),
              `p3_notifications_settings_display_${kind}`,
              (checked: boolean): void => {
                this.updatePreferences(this.withDisplay(kind, checked));
              }
            )
          }, (kind: NotificationKind): string => kind)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding($r('app.float.p1_card_padding'))
        .borderRadius($r('app.float.p1_card_radius'))
        .backgroundColor($r('app.color.surface_background'))
      }
      .width('100%')
      .padding({ left: $r('app.float.p1_page_padding'), right: $r('app.float.p1_page_padding'),
        top: 94, bottom: $r('app.float.p1_page_padding') })
    }
    .id('p3_notifications_settings_page')
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private settingRow(title: string, description: string, checked: boolean, testId: string,
    onChange: (checked: boolean) => void) {
    Row({ space: $r('app.float.p1_spacing_small') }) {
      Column({ space: 2 }) {
        Text(title)
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.primary_text'))
          .width('100%')
        if (description.length > 0) {
          Text(description)
            .fontSize($r('app.float.p1_caption_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: checked })
        .id(testId)
        .onChange((value: boolean): void => {
          onChange(value);
        })
    }
    .width('100%')
  }

  private updatePreferences(value: NotificationPreferences): void {
    this.preferences = value;
    const settings = this.settings;
    if (settings === undefined) {
      this.saveStatus = '通知设置数据源未配置';
      return;
    }
    settings.saveNotificationPreferences(value).then((): void => {
      this.saveStatus = '';
    }).catch((_error: Error): void => {
      this.saveStatus = '保存通知设置失败';
    });
  }

  private async refreshSystemNotificationStatus(): Promise<void> {
    try {
      const enabled = await notificationManager.isNotificationEnabled();
      this.systemNotificationStatus = enabled ? '系统通知已允许' : '系统通知尚未允许';
    } catch (_error) {
      this.systemNotificationStatus = '暂时无法读取系统通知状态';
    }
  }

  private async openSystemNotificationSettings(): Promise<void> {
    if (this.systemNotificationSettingsOpening) {
      return;
    }
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      this.systemNotificationStatus = '无法打开系统通知设置';
      return;
    }
    this.systemNotificationSettingsOpening = true;
    try {
      await notificationManager.openNotificationSettingsWithResult(hostContext as common.UIAbilityContext);
      await this.refreshSystemNotificationStatus();
    } catch (_error) {
      this.systemNotificationStatus = '无法打开系统通知设置，请稍后重试';
    } finally {
      this.systemNotificationSettingsOpening = false;
    }
  }

  private displayEnabled(kind: NotificationKind): boolean {
    if (kind === NotificationKind.LIKE_COMMENT) {
      return this.preferences.likeCommentDisplay;
    }
    if (kind === NotificationKind.REPLY_COMMENT) {
      return this.preferences.replyCommentDisplay;
    }
    if (kind === NotificationKind.INVITE_ANSWER) {
      return this.preferences.inviteAnswerDisplay;
    }
    return this.preferences.likeAnswerDisplay;
  }

  private withDisplay(kind: NotificationKind, enabled: boolean): NotificationPreferences {
    return {
      likeAnswerDisplay: kind === NotificationKind.LIKE_ANSWER ? enabled : this.preferences.likeAnswerDisplay,
      likeCommentDisplay: kind === NotificationKind.LIKE_COMMENT ? enabled : this.preferences.likeCommentDisplay,
      replyCommentDisplay: kind === NotificationKind.REPLY_COMMENT ? enabled : this.preferences.replyCommentDisplay,
      inviteAnswerDisplay: kind === NotificationKind.INVITE_ANSWER ? enabled : this.preferences.inviteAnswerDisplay,
      autoMarkAsRead: this.preferences.autoMarkAsRead,
      unreadBadge: this.preferences.unreadBadge
    };
  }
}

function withAutoMarkAsRead(preferences: NotificationPreferences, enabled: boolean): NotificationPreferences {
  return {
    likeAnswerDisplay: preferences.likeAnswerDisplay,
    likeCommentDisplay: preferences.likeCommentDisplay,
    replyCommentDisplay: preferences.replyCommentDisplay,
    inviteAnswerDisplay: preferences.inviteAnswerDisplay,
    autoMarkAsRead: enabled,
    unreadBadge: preferences.unreadBadge
  };
}

function withUnreadBadge(preferences: NotificationPreferences, enabled: boolean): NotificationPreferences {
  return {
    likeAnswerDisplay: preferences.likeAnswerDisplay,
    likeCommentDisplay: preferences.likeCommentDisplay,
    replyCommentDisplay: preferences.replyCommentDisplay,
    inviteAnswerDisplay: preferences.inviteAnswerDisplay,
    autoMarkAsRead: preferences.autoMarkAsRead,
    unreadBadge: enabled
  };
}
