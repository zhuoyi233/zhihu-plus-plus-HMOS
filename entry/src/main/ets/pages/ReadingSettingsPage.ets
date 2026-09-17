import { textToSpeech } from '@kit.CoreSpeechKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  AppPreferencesStore,
  defaultSpeechPreferences,
  normalizeSpeechPreferences,
  SpeechPreferences
} from 'data';
import { getAbilityContext } from '../entryability/AbilityContextHolder';
import { getSpeechPlaybackService, SpeechPlaybackStatus } from '../platform/SpeechPlaybackService';
import { AppNavigationRow, FLOATING_TITLE_BAR_OFFSET } from './AppPageChrome';

interface SpeechVoiceChoice {
  language: string;
  person: number;
  style: string;
  gender: string;
  description: string;
  status: string;
}

@Component
export struct ReadingSettingsPage {
  @State private preferences: SpeechPreferences = defaultSpeechPreferences();
  @State private loaded: boolean = false;
  @State private statusMessage: string = '';
  @State private voicesLoading: boolean = false;
  @State private voiceChoices: Array<SpeechVoiceChoice> = [];
  @StorageProp('speechPlaybackTick') private playbackTick: number = 0;
  private store: AppPreferencesStore | undefined = undefined;
  private voiceRequestSequence: number = 0;

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
            this.sliderSetting('语速', `调整朗读速度（${this.preferences.speed.toFixed(1)}×）`, this.preferences.speed,
              'p5_reading_speed', (value: number): void => {
                this.save({ speed: value, pitch: this.preferences.pitch, person: this.preferences.person,
                  language: this.preferences.language, style: this.preferences.style });
              });
            Divider().color($r('app.color.divider_color'))
            this.sliderSetting('音调', `调整朗读音调（${this.preferences.pitch.toFixed(1)}）`, this.preferences.pitch,
              'p5_reading_pitch', (value: number): void => {
                this.save({ speed: this.preferences.speed, pitch: value, person: this.preferences.person,
                  language: this.preferences.language, style: this.preferences.style });
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
      Text(title)
        .fontSize($r('app.float.p1_body_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Text(description)
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      this.sliderControl(value, testId, onChange)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
  }

  private sliderProgressPercent(value: number): number {
    return Math.min(100, Math.max(0, (value - 0.5) / 1.5 * 100));
  }

  @Builder
  private sliderControl(value: number, testId: string, onChange: (value: number) => void) {
    Stack({ alignContent: Alignment.Center }) {
      Row() {
        Row()
          .width(`${this.sliderProgressPercent(value)}%`)
          .height('100%')
          .backgroundColor($r('app.color.brand_primary'))
        Row()
          .width(`${100 - this.sliderProgressPercent(value)}%`)
          .height('100%')
          .backgroundColor($r('app.color.control_background'))
      }
      .width('calc(100% - 4vp)')
      .height($r('app.float.p3_settings_slider_track_thickness'))
      .borderRadius($r('app.float.p3_settings_slider_track_radius'))
      .clip(true)
      .hitTestBehavior(HitTestMode.None)

      Row() {
        Blank().layoutWeight(Math.max(0, value - 0.5))
        Stack({ alignContent: Alignment.Center }) {
          Row()
            .width('100%')
            .height($r('app.float.p3_settings_slider_track_thickness'))
            .backgroundColor($r('app.color.surface_background'))
          Row()
            .width($r('app.float.p3_settings_slider_thumb_width'))
            .height($r('app.float.p3_settings_slider_thumb_height'))
            .borderRadius($r('app.float.p3_settings_slider_thumb_radius'))
            .backgroundColor($r('app.color.brand_primary'))
        }
        .width($r('app.float.p3_settings_slider_thumb_gap_width'))
        .height($r('app.float.p3_settings_slider_height'))
        Blank().layoutWeight(Math.max(0, 2 - value))
      }
      .width('calc(100% + 12vp)')
      .height($r('app.float.p3_settings_slider_height'))
      .translate({ x: '-6vp' })
      .hitTestBehavior(HitTestMode.None)

      Slider({ value: value, min: 0.5, max: 2, step: 0.1, style: SliderStyle.OutSet })
        .id(testId)
        .width('100%')
        .height($r('app.float.p3_settings_slider_height'))
        .trackColor(Color.Transparent)
        .selectedColor(Color.Transparent)
        .blockColor(Color.Transparent)
        .blockSize({
          width: $r('app.float.p3_settings_slider_thumb_width'),
          height: $r('app.float.p3_settings_slider_thumb_height')
        })
        .blockStyle({
          type: SliderBlockType.SHAPE,
          shape: new Rect({
            width: $r('app.float.p3_settings_slider_thumb_width'),
            height: $r('app.float.p3_settings_slider_thumb_height')
          }).radius($r('app.float.p3_settings_slider_thumb_radius'))
        })
        .showSteps(true)
        .onChange((next: number, _mode: SliderChangeMode): void => onChange(next))
    }
    .width('100%')
    .height($r('app.float.p3_settings_slider_height'))
  }

  @Builder
  private voiceSetting() {
    Row({ space: $r('app.float.p1_spacing_medium') }) {
      Column({ space: $r('app.float.p1_spacing_xsmall') }) {
        Text('音色')
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.primary_text'))
          .width('100%')
        Text(this.voicesLoading ? '正在查询系统可用音色…' : '由 Core Speech Kit 动态提供；未安装音色会在选择后请求下载。')
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Select(this.voiceSelectOptions())
        .id('p5_reading_voice_select')
        .selected(this.selectedVoiceIndex())
        .value(this.selectedVoiceLabel())
        .fontColor($r('app.color.primary_text'))
        .constraintSize({ maxWidth: 160 })
        .enabled(!this.voicesLoading && this.voiceChoices.length > 0)
        .onSelect((index: number): void => this.selectVoice(index))
    }
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
    .alignItems(VerticalAlign.Center)
  }

  private async restore(): Promise<void> {
    try {
      this.preferences = await this.store?.loadSpeechPreferences() ?? defaultSpeechPreferences();
      this.voiceChoices = [this.preferenceVoiceChoice()];
      this.loaded = true;
      void this.loadVoices();
    } catch (_error) {
      this.loaded = true;
      this.statusMessage = '读取朗读设置失败，已使用默认值';
    }
  }

  private preferenceVoiceChoice(): SpeechVoiceChoice {
    return {
      language: this.preferences.language,
      person: this.preferences.person,
      style: this.preferences.style,
      gender: '',
      description: '',
      status: 'INSTALLED'
    } as SpeechVoiceChoice;
  }

  private async loadVoices(): Promise<void> {
    this.voicesLoading = true;
    this.voiceRequestSequence += 1;
    try {
      const voices = await textToSpeech.listVoices({
        requestId: `zhplus-voices-${Date.now()}-${this.voiceRequestSequence}`,
        online: 1
      });
      const choices: Array<SpeechVoiceChoice> = [];
      voices.forEach((voice: textToSpeech.VoiceInfo): void => {
        const choice: SpeechVoiceChoice = {
          language: voice.language,
          person: voice.person === 0 ? 13 : voice.person,
          style: voice.style,
          gender: voice.gender,
          description: voice.description,
          status: voice.status ?? ''
        };
        if (!choices.some((item: SpeechVoiceChoice): boolean => this.sameVoice(item, choice))) {
          choices.push(choice);
        }
      });
      if (choices.length === 0) {
        throw new Error('系统未返回可用音色');
      }
      if (!choices.some((item: SpeechVoiceChoice): boolean => this.isSelectedVoice(item))) {
        choices.unshift(this.preferenceVoiceChoice());
      }
      this.voiceChoices = choices;
      this.statusMessage = '';
    } catch (_error) {
      this.statusMessage = '查询系统音色失败，暂时保留当前音色';
    } finally {
      this.voicesLoading = false;
    }
  }

  private voiceSelectOptions(): SelectOption[] {
    return this.voiceChoices.map((choice: SpeechVoiceChoice): SelectOption => {
      return { value: this.voiceLabel(choice) } as SelectOption;
    });
  }

  private selectedVoiceIndex(): number {
    const index = this.voiceChoices.findIndex((choice: SpeechVoiceChoice): boolean => this.isSelectedVoice(choice));
    return index >= 0 ? index : 0;
  }

  private selectedVoiceLabel(): string {
    const index = this.selectedVoiceIndex();
    return index < this.voiceChoices.length ? this.voiceLabel(this.voiceChoices[index]) : '暂无可用音色';
  }

  private voiceLabel(choice: SpeechVoiceChoice): string {
    let name = choice.description.trim();
    if (choice.person === 13) name = '聆小珊';
    else if (choice.person === 21) name = '凌飞哲';
    else if (choice.person === 8) name = '劳拉';
    else if (name.length === 0) name = `音色 ${choice.person}`;
    const language = choice.language === 'zh-CN' || choice.language === 'zh_CN' ? '中文' :
      (choice.language === 'en-US' || choice.language === 'en_US' ? '英语（美国）' : choice.language);
    if (choice.status === 'GA') return `${name} · ${language}（需下载）`;
    if (choice.status === 'EOM') return `${name} · ${language}（不可用）`;
    return `${name} · ${language}`;
  }

  private sameVoice(left: SpeechVoiceChoice, right: SpeechVoiceChoice): boolean {
    return left.language === right.language && left.person === right.person && left.style === right.style;
  }

  private isSelectedVoice(choice: SpeechVoiceChoice): boolean {
    return choice.language === this.preferences.language && choice.person === this.preferences.person &&
      choice.style === this.preferences.style;
  }

  private selectVoice(index: number): void {
    if (index < 0 || index >= this.voiceChoices.length) {
      return;
    }
    const choice = this.voiceChoices[index];
    if (choice.status === 'EOM') {
      this.statusMessage = '该音色当前不可用';
      return;
    }
    if (choice.status === 'GA') {
      this.downloadVoice(choice);
      return;
    }
    this.saveVoice(choice);
  }

  private downloadVoice(choice: SpeechVoiceChoice): void {
    this.voiceRequestSequence += 1;
    this.statusMessage = `正在请求下载${this.voiceLabel(choice).replace('（需下载）', '')}…`;
    textToSpeech.downloadVoice({
      requestId: `zhplus-download-${Date.now()}-${this.voiceRequestSequence}`,
      language: choice.language,
      person: choice.person,
      style: choice.style
    }, (error: BusinessError, response: textToSpeech.DownloadResponse): void => {
      if (error) {
        this.statusMessage = `音色下载失败（${error.code}）`;
        return;
      }
      response.on('complete', (voice: textToSpeech.VoiceInfo): void => {
        const installed: SpeechVoiceChoice = {
          language: voice.language,
          person: voice.person === 0 ? 13 : voice.person,
          style: voice.style,
          gender: voice.gender,
          description: voice.description,
          status: 'INSTALLED'
        };
        this.saveVoice(installed);
        void this.loadVoices();
      });
      response.on('cancel', (_info: string): void => {
        this.statusMessage = '已取消音色下载';
      });
      response.on('error', (downloadError: BusinessError): void => {
        this.statusMessage = `音色下载失败（${downloadError.code}）`;
      });
    });
  }

  private saveVoice(choice: SpeechVoiceChoice): void {
    this.save({
      speed: this.preferences.speed,
      pitch: this.preferences.pitch,
      person: choice.person,
      language: choice.language,
      style: choice.style
    });
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
