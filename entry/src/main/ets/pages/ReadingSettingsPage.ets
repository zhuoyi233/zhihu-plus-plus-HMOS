import {
  AppPreferencesStore,
  defaultSpeechPreferences,
  normalizeSpeechPreferences,
  SpeechPreferences
} from 'data';
import { getAbilityContext } from '../entryability/AbilityContextHolder';
import { getSpeechPlaybackService, SpeechPlaybackStatus } from '../platform/SpeechPlaybackService';
import { AppNavigationRow, FLOATING_TITLE_BAR_OFFSET } from './AppPageChrome';

@Component
export struct ReadingSettingsPage {
  @State private preferences: SpeechPreferences = defaultSpeechPreferences();
  @State private loaded: boolean = false;
  @State private statusMessage: string = '';
  @StorageProp('speechPlaybackTick') private playbackTick: number = 0;
  private store: AppPreferencesStore | undefined = undefined;

  aboutToAppear(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusMessage = '设置服务暂不可用';
      return;
    }
    this.store = new AppPreferencesStore(context);
    void this.restore();
  }

  build() {
    Scroll() {
      Column({ space: $r('app.float.p1_spacing_large') }) {
        Text('使用 HarmonyOS Core Speech Kit 离线朗读回答和文章。设置会在下次开始朗读时生效。')
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')

        if (this.loaded) {
          this.sectionTitle('语音')
          Column() {
            this.sliderSetting('语速', '0.5×（较慢）到 2.0×（较快）', this.preferences.speed,
              'p5_reading_speed', (value: number): void => {
                this.save({ speed: value, pitch: this.preferences.pitch, person: this.preferences.person });
              });
            Divider().color($r('app.color.divider_color'))
            this.sliderSetting('音调', '0.5（较低）到 2.0（较高）', this.preferences.pitch,
              'p5_reading_pitch', (value: number): void => {
                this.save({ speed: this.preferences.speed, pitch: value, person: this.preferences.person });
              });
            Divider().color($r('app.color.divider_color'))
            this.voiceSetting()
          }
          .width('100%')
          .borderRadius($r('app.float.p1_card_radius'))
          .backgroundColor($r('app.color.surface_background'))

          this.sectionTitle('播放')
          Column() {
            AppNavigationRow({
              title: this.playbackTitle(),
              description: this.playbackDescription(),
              testId: 'p5_reading_stop',
              grouped: true,
              onRowClick: (): void => {
                if (getSpeechPlaybackService().getSnapshot().status !== SpeechPlaybackStatus.IDLE) {
                  getSpeechPlaybackService().stop();
                }
              }
            })
          }
          .width('100%')
          .borderRadius($r('app.float.p1_card_radius'))
          .backgroundColor($r('app.color.surface_background'))
        } else {
          LoadingProgress().width(40).height(40).color($r('app.color.brand_primary'))
        }

        if (this.statusMessage.length > 0) {
          Text(this.statusMessage)
            .id('p5_reading_settings_status')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
        }
      }
      .width('100%')
      .padding({ left: $r('app.float.p1_page_padding'), right: $r('app.float.p1_page_padding'),
        top: FLOATING_TITLE_BAR_OFFSET, bottom: 40 })
    }
    .id('p5_reading_settings_scroll')
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private sectionTitle(title: string) {
    Text(title).fontSize($r('app.float.p1_secondary_font_size'))
      .fontColor($r('app.color.secondary_text')).width('100%')
  }

  @Builder
  private sliderSetting(title: string, description: string, value: number, testId: string,
    onChange: (value: number) => void) {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      Row() {
        Column({ space: 2 }) {
          Text(title).fontSize($r('app.float.p1_body_font_size')).fontColor($r('app.color.primary_text'))
          Text(description).fontSize($r('app.float.p1_secondary_font_size')).fontColor($r('app.color.secondary_text'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Text(value.toFixed(1)).fontSize($r('app.float.p1_body_font_size')).fontColor($r('app.color.brand_primary'))
      }.width('100%')
      Slider({ value: value, min: 0.5, max: 2, step: 0.1, style: SliderStyle.OutSet })
        .id(testId).showSteps(true).onChange((next: number): void => onChange(next))
    }.width('100%').padding($r('app.float.p1_card_padding'))
  }

  @Builder
  private voiceSetting() {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      Text('音色').fontSize($r('app.float.p1_body_font_size')).fontColor($r('app.color.primary_text')).width('100%')
      Text('使用系统内置的聆小珊女声；无需在应用内下载语音模型。')
        .fontSize($r('app.float.p1_secondary_font_size')).fontColor($r('app.color.secondary_text')).width('100%')
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Button('兼容音色').id('p5_reading_voice_0').layoutWeight(1)
          .backgroundColor(this.preferences.person === 0 ? $r('app.color.brand_primary') : $r('app.color.control_background'))
          .onClick((): void => this.save({ speed: this.preferences.speed, pitch: this.preferences.pitch, person: 0 }))
        Button('推荐音色').id('p5_reading_voice_13').layoutWeight(1)
          .backgroundColor(this.preferences.person === 13 ? $r('app.color.brand_primary') : $r('app.color.control_background'))
          .onClick((): void => this.save({ speed: this.preferences.speed, pitch: this.preferences.pitch, person: 13 }))
      }.width('100%')
    }.width('100%').padding($r('app.float.p1_card_padding'))
  }

  private async restore(): Promise<void> {
    try {
      this.preferences = await this.store?.loadSpeechPreferences() ?? defaultSpeechPreferences();
      this.loaded = true;
    } catch (_error) {
      this.loaded = true;
      this.statusMessage = '读取朗读设置失败，已使用默认值';
    }
  }

  private save(value: SpeechPreferences): void {
    const normalized = normalizeSpeechPreferences(value);
    this.preferences = normalized;
    AppStorage.setOrCreate('speechPreferences', normalized);
    this.store?.saveSpeechPreferences(normalized).then((): void => {
      this.statusMessage = '';
    }).catch((): void => {
      this.statusMessage = '保存朗读设置失败，请重试';
    });
  }

  private playbackTitle(): string {
    const snapshot = getSpeechPlaybackService().getSnapshot();
    return snapshot.status === SpeechPlaybackStatus.IDLE ? '当前没有朗读任务' : '停止当前朗读';
  }

  private playbackDescription(): string {
    // 读取 tick，确保 AppStorage 广播变化能触发该计算重新执行。
    const _tick = this.playbackTick;
    const snapshot = getSpeechPlaybackService().getSnapshot();
    return snapshot.status === SpeechPlaybackStatus.IDLE ? '从回答或文章的更多菜单开始朗读' :
      (snapshot.title.length > 0 ? snapshot.title : snapshot.message);
  }
}
