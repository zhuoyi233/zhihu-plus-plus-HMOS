import {
  AppPreferencesStore,
  BlockingPreferences,
  ContentFilterRuntimeGateway,
  ContentFilterStats,
  defaultBlockingPreferences,
  defaultRecommendationFilterPreferences,
  normalizeRecommendationFilterPreferences,
  QualityFilterMode,
  qualityFilterModeLabel,
  RecommendationFilterPreferences,
  RecommendationMode,
  recommendationModeLabel
} from 'data';

type FilterBooleanKey = 'loginForRecommendation' | 'autoRefreshHomeOnStartup' | 'enableContentFilter' |
  'filterFollowedUserContent' | 'blockZhihuAdPlatform' | 'blockZhihuSchool' |
  'blockWeChatOfficialAccount' | 'blockPaidContent' | 'reverseBlock';

type RuleBooleanKey = 'keywordBlockingEnabled' | 'userBlockingEnabled' | 'topicBlockingEnabled';

type ThresholdKey = 'answerVoteupThreshold' | 'articleVoteupThreshold' | 'articleFollowersThreshold' |
  'videoVoteThreshold' | 'videoFollowersThreshold' | 'questionAnswerThreshold' | 'questionFollowersThreshold' |
  'topicBlockingThreshold';
type SettingsSheetKind = 'threshold' | 'stats';

function copyFilter(value: RecommendationFilterPreferences): RecommendationFilterPreferences {
  return {
    recommendationMode: value.recommendationMode,
    loginForRecommendation: value.loginForRecommendation,
    autoRefreshHomeOnStartup: value.autoRefreshHomeOnStartup,
    qualityFilterMode: value.qualityFilterMode,
    answerVoteupThreshold: value.answerVoteupThreshold,
    articleVoteupThreshold: value.articleVoteupThreshold,
    articleFollowersThreshold: value.articleFollowersThreshold,
    videoVoteThreshold: value.videoVoteThreshold,
    videoFollowersThreshold: value.videoFollowersThreshold,
    questionAnswerThreshold: value.questionAnswerThreshold,
    questionFollowersThreshold: value.questionFollowersThreshold,
    enableContentFilter: value.enableContentFilter,
    filterFollowedUserContent: value.filterFollowedUserContent,
    blockZhihuAdPlatform: value.blockZhihuAdPlatform,
    blockZhihuSchool: value.blockZhihuSchool,
    blockWeChatOfficialAccount: value.blockWeChatOfficialAccount,
    blockPaidContent: value.blockPaidContent,
    reverseBlock: value.reverseBlock
  };
}

@Component
export struct ContentFilterSettingsPage {
  preferences: AppPreferencesStore | undefined = undefined;
  runtime: ContentFilterRuntimeGateway | undefined = undefined;
  onOpenBlocklist: () => void = (): void => {};
  onOpenBlockedHistory: () => void = (): void => {};
  @State private filter: RecommendationFilterPreferences = defaultRecommendationFilterPreferences();
  @State private rules: BlockingPreferences = defaultBlockingPreferences();
  @State private statusMessage: string = '';
  @State private settingsSheetShown: boolean = false;
  @State private settingsSheetKind: SettingsSheetKind = 'threshold';
  @State private thresholdKey: ThresholdKey = 'answerVoteupThreshold';
  @State private thresholdInput: string = '';
  @State private resetConfirmation: boolean = false;
  @State private stats: ContentFilterStats = { totalSeen: 0, totalFiltered: 0, filterRate: 0, lastFilteredAt: 0 };

  aboutToAppear(): void {
    void this.restore();
  }

  build() {
    Scroll() {
      Column({ space: $r('app.float.p1_spacing_large') }) {
        if (this.statusMessage.length > 0) {
          Text(this.statusMessage)
            .id('p3_content_filter_status')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
        }
        this.sectionTitle('推荐来源')
        Column() {
          this.recommendationModeSetting()
          Divider().color($r('app.color.divider_color'))
          this.switchSetting('推荐内容时登录', '获取推荐内容时携带登录凭证', this.filter.loginForRecommendation,
            true, 'p3_filter_login_recommendation', (value: boolean): void =>
              this.updateFilterBoolean('loginForRecommendation', value))
          Divider().color($r('app.color.divider_color'))
          this.switchSetting('启动时自动刷新首页', '关闭后优先显示上次获取的一批首页推荐；没有缓存时仍会加载新推荐',
            this.filter.autoRefreshHomeOnStartup, true, 'p3_filter_auto_refresh_startup', (value: boolean): void =>
              this.updateFilterBoolean('autoRefreshHomeOnStartup', value))
        }
        .width('100%')
        .borderRadius($r('app.float.p1_card_radius'))
        .backgroundColor($r('app.color.surface_background'))

        this.sectionTitle('内容质量')
        Column() {
          this.qualityModeSetting()
          Divider().color($r('app.color.divider_color'))
          this.thresholdSetting('回答最低赞数', '低于此赞同数的未关注作者回答会被过滤',
            'answerVoteupThreshold', this.filter.answerVoteupThreshold, true, 'p3_filter_answer_vote_threshold')
          Divider().color($r('app.color.divider_color'))
          this.thresholdSetting('文章最低赞数', '低于此赞数或作者粉丝低于对应阈值的文章会被过滤',
            'articleVoteupThreshold', this.filter.articleVoteupThreshold, true, 'p3_filter_article_vote_threshold')
          Divider().color($r('app.color.divider_color'))
          this.thresholdSetting('文章最低粉丝数', '文章作者粉丝数低于此值时应用质量过滤',
            'articleFollowersThreshold', this.filter.articleFollowersThreshold, true, 'p3_filter_article_follower_threshold')
          Divider().color($r('app.color.divider_color'))
          this.thresholdSetting('视频最低赞数', '视频赞同数低于此值时应用质量过滤',
            'videoVoteThreshold', this.filter.videoVoteThreshold, true, 'p3_filter_video_vote_threshold')
          Divider().color($r('app.color.divider_color'))
          this.thresholdSetting('视频最低粉丝数', '视频作者粉丝数低于此值时应用质量过滤',
            'videoFollowersThreshold', this.filter.videoFollowersThreshold, true, 'p3_filter_video_follower_threshold')
          Divider().color($r('app.color.divider_color'))
          this.thresholdSetting('问题最低回答数', '问题回答数低于此值时应用质量过滤',
            'questionAnswerThreshold', this.filter.questionAnswerThreshold, true, 'p3_filter_question_answer_threshold')
          Divider().color($r('app.color.divider_color'))
          this.thresholdSetting('问题最低关注数', '问题关注数低于此值时应用质量过滤',
            'questionFollowersThreshold', this.filter.questionFollowersThreshold, true, 'p3_filter_question_follower_threshold')
        }
        .width('100%')
        .borderRadius($r('app.float.p1_card_radius'))
        .backgroundColor($r('app.color.surface_background'))

        this.sectionTitle('智能与规则过滤')
        Column() {
          this.switchSetting('启用智能内容过滤', '自动过滤首页展示超过2次但用户未点击的内容，减少重复推荐',
            this.filter.enableContentFilter, true, 'p3_filter_smart_enabled', (value: boolean): void =>
              this.updateFilterBoolean('enableContentFilter', value))
          Divider().color($r('app.color.divider_color'))
          this.switchSetting('过滤已关注用户内容', '关闭后，已关注作者的内容始终显示',
            this.filter.filterFollowedUserContent, this.filter.enableContentFilter,
            'p3_filter_followed_user', (value: boolean): void =>
              this.updateFilterBoolean('filterFollowedUserContent', value))
          Divider().color($r('app.color.divider_color'))
          this.ruleSwitchSetting('启用关键词屏蔽', '屏蔽包含特定关键词的内容',
            this.rules.keywordBlockingEnabled, 'keywordBlockingEnabled', 'p3_filter_keyword_enabled')
          Divider().color($r('app.color.divider_color'))
          this.ruleSwitchSetting('启用用户屏蔽', '屏蔽特定用户发布的内容',
            this.rules.userBlockingEnabled, 'userBlockingEnabled', 'p3_filter_user_enabled')
          Divider().color($r('app.color.divider_color'))
          this.ruleSwitchSetting('启用主题屏蔽', '屏蔽包含特定主题的内容',
            this.rules.topicBlockingEnabled, 'topicBlockingEnabled', 'p3_filter_topic_enabled')
          Divider().color($r('app.color.divider_color'))
          this.thresholdSetting('主题屏蔽阈值', '命中的已屏蔽主题数量达到此值时过滤内容',
            'topicBlockingThreshold', this.rules.topicBlockingThreshold, this.rules.topicBlockingEnabled,
            'p3_filter_topic_threshold')
        }
        .width('100%')
        .borderRadius($r('app.float.p1_card_radius'))
        .backgroundColor($r('app.color.surface_background'))

        this.sectionTitle('推广与付费内容')
        Column() {
          this.switchSetting('屏蔽知乎广告平台内容', '匹配并屏蔽包含 xg.zhihu.com 的推广内容',
            this.filter.blockZhihuAdPlatform, true, 'p3_filter_zhihu_ad', (value: boolean): void =>
              this.updateFilterBoolean('blockZhihuAdPlatform', value))
          Divider().color($r('app.color.divider_color'))
          this.switchSetting('屏蔽知乎学堂内容', '匹配并屏蔽包含 d.zhihu.com 或 data-edu-card-id 的内容',
            this.filter.blockZhihuSchool, true, 'p3_filter_zhihu_school', (value: boolean): void =>
              this.updateFilterBoolean('blockZhihuSchool', value))
          Divider().color($r('app.color.divider_color'))
          this.switchSetting('屏蔽微信公众号文章', '匹配并屏蔽包含 mp.weixin.qq.com 的外链文章',
            this.filter.blockWeChatOfficialAccount, true, 'p3_filter_wechat', (value: boolean): void =>
              this.updateFilterBoolean('blockWeChatOfficialAccount', value))
          Divider().color($r('app.color.divider_color'))
          this.switchSetting('屏蔽知乎盐选付费内容', '屏蔽知乎盐选会员专享的付费回答和文章',
            this.filter.blockPaidContent, true, 'p3_filter_paid', (value: boolean): void =>
              this.updateFilterBoolean('blockPaidContent', value))
          Divider().color($r('app.color.divider_color'))
          this.switchSetting('反向屏蔽（吃💩模式）', '开启后首页只保留广告和付费内容，屏蔽其余内容',
            this.filter.reverseBlock, true, 'p3_filter_reverse', (value: boolean): void =>
              this.updateFilterBoolean('reverseBlock', value))
        }
        .width('100%')
        .borderRadius($r('app.float.p1_card_radius'))
        .backgroundColor($r('app.color.surface_background'))

        this.sectionTitle('管理与统计')
        Column() {
          this.navigationSetting('内容屏蔽', '关键词、用户和主题精确规则', 'p3_filter_open_blocklist',
            this.onOpenBlocklist)
          Divider().color($r('app.color.divider_color'))
          this.navigationSetting('屏蔽记录', '查看最近被过滤或手动隐藏的内容', 'p3_filter_open_history',
            this.onOpenBlockedHistory)
          Divider().color($r('app.color.divider_color'))
          this.navigationSetting('过滤统计', '查看过滤率，并清理过期数据或重置统计', 'p3_filter_statistics', (): void => {
            void this.openStats();
          })
        }
        .width('100%')
        .borderRadius($r('app.float.p1_card_radius'))
        .backgroundColor($r('app.color.surface_background'))
      }
      .width('100%')
      .padding({ left: $r('app.float.p1_page_padding'), right: $r('app.float.p1_page_padding'), top: 94,
        bottom: $r('app.float.p1_page_padding') })
    }
    .id('p3_content_filter_settings_page')
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .backgroundColor($r('app.color.page_background'))
    .bindSheet($$this.settingsSheetShown, this.settingsSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      backgroundColor: $r('app.color.card_background')
    })
  }

  @Builder
  private settingsSheet() {
    if (this.settingsSheetKind === 'threshold') {
      this.thresholdSheet()
    } else {
      this.statsSheet()
    }
  }

  @Builder
  private sectionTitle(title: string) {
    Text(title).fontSize($r('app.float.p1_secondary_font_size')).fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.secondary_text')).width('100%').padding({ left: $r('app.float.p1_spacing_xsmall') })
  }

  @Builder
  private recommendationModeSetting() {
    this.selectSetting('推荐算法', '选择首页推荐内容来源', recommendationModeLabel(this.filter.recommendationMode),
      [{ value: 'Web 端推荐' }, { value: '安卓端推荐' }, { value: '本地推荐' }, { value: '混合推荐' }],
      this.recommendationModeIndex(), 'p3_filter_recommendation_mode', (index: number): void => {
        const values: RecommendationMode[] = [RecommendationMode.WEB, RecommendationMode.ANDROID,
          RecommendationMode.LOCAL, RecommendationMode.MIXED];
        if (index >= 0 && index < values.length) {
          const next = copyFilter(this.filter);
          next.recommendationMode = values[index];
          this.filter = normalizeRecommendationFilterPreferences(next);
          this.persistFilter();
        }
      })
  }

  @Builder
  private qualityModeSetting() {
    this.selectSetting('质量屏蔽', '根据赞同数、关注数等指标处理低质量内容',
      qualityFilterModeLabel(this.filter.qualityFilterMode),
      [{ value: '不屏蔽' }, { value: '屏蔽规则' }, { value: '隐藏' }], this.qualityModeIndex(),
      'p3_filter_quality_mode', (index: number): void => {
        const values: QualityFilterMode[] = [QualityFilterMode.OFF, QualityFilterMode.RULES, QualityFilterMode.HIDE];
        if (index >= 0 && index < values.length) {
          const next = copyFilter(this.filter);
          next.qualityFilterMode = values[index];
          this.filter = normalizeRecommendationFilterPreferences(next);
          this.persistFilter();
        }
      })
  }

  @Builder
  private switchSetting(title: string, description: string, checked: boolean, enabled: boolean, testId: string,
    onChange: (value: boolean) => void) {
    Row({ space: $r('app.float.p1_spacing_medium') }) {
      Column({ space: $r('app.float.p1_spacing_xsmall') }) {
        Text(title).fontSize($r('app.float.p1_body_font_size')).fontColor($r('app.color.primary_text')).width('100%')
        Text(description).fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text')).width('100%')
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: checked }).id(testId).enabled(enabled)
        .onChange((value: boolean): void => onChange(value))
    }.width('100%').padding($r('app.float.p1_card_padding')).alignItems(VerticalAlign.Center)
      .opacity(enabled ? 1 : 0.45)
  }

  @Builder
  private ruleSwitchSetting(title: string, description: string, checked: boolean, key: RuleBooleanKey, testId: string) {
    this.switchSetting(title, description, checked, true, testId,
      (value: boolean): void => this.updateRuleBoolean(key, value))
  }

  @Builder
  private selectSetting(title: string, description: string, value: string, options: SelectOption[], selected: number,
    testId: string, onSelect: (index: number) => void) {
    Row({ space: $r('app.float.p1_spacing_medium') }) {
      Column({ space: $r('app.float.p1_spacing_xsmall') }) {
        Text(title).fontSize($r('app.float.p1_body_font_size')).fontColor($r('app.color.primary_text')).width('100%')
        Text(description).fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text')).width('100%')
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Select(options).id(testId).selected(selected).value(value).fontColor($r('app.color.primary_text'))
        .constraintSize({ maxWidth: 160 }).onSelect((index: number): void => onSelect(index))
    }.width('100%').padding($r('app.float.p1_card_padding')).alignItems(VerticalAlign.Center)
  }

  @Builder
  private thresholdSetting(title: string, description: string, key: ThresholdKey, value: number,
    enabled: boolean, testId: string) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: $r('app.float.p1_spacing_medium') }) {
        Column({ space: $r('app.float.p1_spacing_xsmall') }) {
          Text(title).fontSize($r('app.float.p1_body_font_size')).fontColor($r('app.color.primary_text')).width('100%')
          Text(description).fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text')).width('100%')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Text(`${value}`).fontSize($r('app.float.p1_body_font_size')).fontColor($r('app.color.secondary_text'))
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([$r('app.color.secondary_text')])
      }.width('100%').alignItems(VerticalAlign.Center)
    }.id(testId).width('100%').padding($r('app.float.p1_card_padding')).backgroundColor(Color.Transparent)
      .enabled(enabled).opacity(enabled ? 1 : 0.45).onClick((): void => this.openThreshold(key, value))
  }

  @Builder
  private navigationSetting(title: string, description: string, testId: string, action: () => void) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: $r('app.float.p1_spacing_medium') }) {
        Column({ space: $r('app.float.p1_spacing_xsmall') }) {
          Text(title).fontSize($r('app.float.p1_body_font_size')).fontColor($r('app.color.primary_text')).width('100%')
          Text(description).fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text')).width('100%')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([$r('app.color.secondary_text')])
      }.width('100%').alignItems(VerticalAlign.Center)
    }.id(testId).width('100%').padding($r('app.float.p1_card_padding')).backgroundColor(Color.Transparent)
      .onClick((): void => action())
  }

  @Builder
  private thresholdSheet() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Text(`设置${this.thresholdTitle()}`).fontSize($r('app.float.p1_heading_font_size'))
        .fontWeight(FontWeight.Medium).fontColor($r('app.color.primary_text')).width('100%')
      if (this.thresholdKey === 'topicBlockingThreshold') {
        Text('当内容包含的被屏蔽主题数量达到或超过此阈值时，该内容将被屏蔽。')
          .fontSize($r('app.float.p1_secondary_font_size')).fontColor($r('app.color.secondary_text')).width('100%')
      }
      TextInput({ text: this.thresholdInput, placeholder: '输入非负整数' }).id('p3_filter_threshold_input')
        .type(InputType.Number).maxLength(9).onChange((value: string): void => { this.thresholdInput = value; })
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Button('取消').layoutWeight(1).onClick((): void => { this.settingsSheetShown = false; })
        Button('确定').id('p3_filter_threshold_confirm').layoutWeight(1)
          .enabled(this.validThresholdInput()).onClick((): void => this.confirmThreshold())
      }.width('100%')
    }.width('100%').padding($r('app.float.p1_spacing_large'))
  }

  @Builder
  private statsSheet() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Text('过滤统计详情').fontSize($r('app.float.p1_heading_font_size')).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text')).width('100%')
      Text(`总记录数：${this.stats.totalSeen}`).fontSize($r('app.float.p1_body_font_size')).width('100%')
      Text(`已过滤：${this.stats.totalFiltered}`).fontSize($r('app.float.p1_body_font_size')).width('100%')
      Text(`过滤率：${(this.stats.filterRate * 100).toFixed(1)}%`)
        .fontSize($r('app.float.p1_body_font_size')).width('100%')
      Button('清理 7 天前数据').id('p3_filter_cleanup_old').width('100%')
        .onClick((): void => this.cleanupOldData())
      if (this.resetConfirmation) {
        Text('再次点击将重置所有曝光统计和屏蔽记录，此操作不可撤销。')
          .fontSize($r('app.float.p1_secondary_font_size')).fontColor($r('app.color.error_text')).width('100%')
        Button('确认重置所有数据').id('p3_filter_reset_confirm').width('100%')
          .fontColor($r('app.color.error_text')).onClick((): void => this.clearAllData())
      } else {
        Button('重置所有数据').id('p3_filter_reset_all').width('100%')
          .fontColor($r('app.color.error_text')).onClick((): void => { this.resetConfirmation = true; })
      }
      Button('关闭').id('p3_filter_stats_close').width('100%').onClick((): void => {
        this.settingsSheetShown = false;
        this.resetConfirmation = false;
      })
    }.width('100%').padding($r('app.float.p1_spacing_large'))
  }

  private async restore(): Promise<void> {
    const store = this.preferences;
    if (store === undefined) {
      this.statusMessage = '设置服务暂不可用';
      return;
    }
    try {
      this.filter = await store.loadRecommendationFilterPreferences();
      this.rules = await store.loadBlockingPreferences();
    } catch (_error) {
      this.statusMessage = '设置读取失败，已使用默认值';
    }
  }

  private updateFilterBoolean(key: FilterBooleanKey, value: boolean): void {
    const next = copyFilter(this.filter);
    if (key === 'loginForRecommendation') next.loginForRecommendation = value;
    else if (key === 'autoRefreshHomeOnStartup') next.autoRefreshHomeOnStartup = value;
    else if (key === 'enableContentFilter') next.enableContentFilter = value;
    else if (key === 'filterFollowedUserContent') next.filterFollowedUserContent = value;
    else if (key === 'blockZhihuAdPlatform') next.blockZhihuAdPlatform = value;
    else if (key === 'blockZhihuSchool') next.blockZhihuSchool = value;
    else if (key === 'blockWeChatOfficialAccount') next.blockWeChatOfficialAccount = value;
    else if (key === 'blockPaidContent') next.blockPaidContent = value;
    else next.reverseBlock = value;
    this.filter = normalizeRecommendationFilterPreferences(next);
    this.persistFilter();
  }

  private updateRuleBoolean(key: RuleBooleanKey, value: boolean): void {
    const next: BlockingPreferences = {
      keywordBlockingEnabled: key === 'keywordBlockingEnabled' ? value : this.rules.keywordBlockingEnabled,
      userBlockingEnabled: key === 'userBlockingEnabled' ? value : this.rules.userBlockingEnabled,
      topicBlockingEnabled: key === 'topicBlockingEnabled' ? value : this.rules.topicBlockingEnabled,
      topicBlockingThreshold: this.rules.topicBlockingThreshold
    };
    this.rules = next;
    this.persistRules();
  }

  private persistFilter(): void {
    this.preferences?.saveRecommendationFilterPreferences(this.filter).then((): void => {
      AppStorage.setOrCreate('contentFilterSettingsTick', (AppStorage.get<number>('contentFilterSettingsTick') ?? 0) + 1);
      this.statusMessage = '';
    }).catch((_error: Error): void => { this.statusMessage = '设置保存失败，请重试'; });
  }

  private persistRules(): void {
    this.preferences?.saveBlockingPreferences(this.rules).then((): void => {
      AppStorage.setOrCreate('contentFilterSettingsTick', (AppStorage.get<number>('contentFilterSettingsTick') ?? 0) + 1);
      this.statusMessage = '';
    }).catch((_error: Error): void => { this.statusMessage = '设置保存失败，请重试'; });
  }

  private openThreshold(key: ThresholdKey, value: number): void {
    this.thresholdKey = key;
    this.thresholdInput = `${value}`;
    this.settingsSheetKind = 'threshold';
    this.settingsSheetShown = true;
  }

  private validThresholdInput(): boolean {
    if (!/^\d{1,9}$/.test(this.thresholdInput)) return false;
    const value = Number(this.thresholdInput);
    return Number.isSafeInteger(value) && value >= (this.thresholdKey === 'topicBlockingThreshold' ? 1 : 0) &&
      value <= 100000000;
  }

  private confirmThreshold(): void {
    if (!this.validThresholdInput()) return;
    const value = Number(this.thresholdInput);
    this.settingsSheetShown = false;
    if (this.thresholdKey === 'topicBlockingThreshold') {
      this.rules = {
        keywordBlockingEnabled: this.rules.keywordBlockingEnabled,
        userBlockingEnabled: this.rules.userBlockingEnabled,
        topicBlockingEnabled: this.rules.topicBlockingEnabled,
        topicBlockingThreshold: value
      };
      this.persistRules();
      return;
    }
    const next = copyFilter(this.filter);
    if (this.thresholdKey === 'answerVoteupThreshold') next.answerVoteupThreshold = value;
    else if (this.thresholdKey === 'articleVoteupThreshold') next.articleVoteupThreshold = value;
    else if (this.thresholdKey === 'articleFollowersThreshold') next.articleFollowersThreshold = value;
    else if (this.thresholdKey === 'videoVoteThreshold') next.videoVoteThreshold = value;
    else if (this.thresholdKey === 'videoFollowersThreshold') next.videoFollowersThreshold = value;
    else if (this.thresholdKey === 'questionAnswerThreshold') next.questionAnswerThreshold = value;
    else next.questionFollowersThreshold = value;
    this.filter = normalizeRecommendationFilterPreferences(next);
    this.persistFilter();
  }

  private thresholdTitle(): string {
    if (this.thresholdKey === 'answerVoteupThreshold') return '回答最低赞数';
    if (this.thresholdKey === 'articleVoteupThreshold') return '文章最低赞数';
    if (this.thresholdKey === 'articleFollowersThreshold') return '文章最低粉丝数';
    if (this.thresholdKey === 'videoVoteThreshold') return '视频最低赞数';
    if (this.thresholdKey === 'videoFollowersThreshold') return '视频最低粉丝数';
    if (this.thresholdKey === 'questionAnswerThreshold') return '问题最低回答数';
    if (this.thresholdKey === 'questionFollowersThreshold') return '问题最低关注数';
    return '主题屏蔽阈值';
  }

  private recommendationModeIndex(): number {
    if (this.filter.recommendationMode === RecommendationMode.WEB) return 0;
    if (this.filter.recommendationMode === RecommendationMode.ANDROID) return 1;
    if (this.filter.recommendationMode === RecommendationMode.LOCAL) return 2;
    return 3;
  }

  private async openStats(): Promise<void> {
    const runtime = this.runtime;
    if (runtime === undefined) {
      this.statusMessage = '过滤统计服务暂不可用';
      return;
    }
    try {
      this.stats = await runtime.loadStats();
      this.resetConfirmation = false;
      this.settingsSheetKind = 'stats';
      this.settingsSheetShown = true;
    } catch (_error) {
      this.statusMessage = '过滤统计读取失败';
    }
  }

  private cleanupOldData(): void {
    const cutoff = Date.now() - 7 * 24 * 60 * 60 * 1000;
    this.runtime?.cleanupOldData(cutoff).then((): void => {
      this.statusMessage = '已清理 7 天前的过滤数据';
      void this.openStats();
    }).catch((_error: Error): void => { this.statusMessage = '清理失败，请重试'; });
  }

  private clearAllData(): void {
    this.runtime?.clearAllData().then((): void => {
      this.stats = { totalSeen: 0, totalFiltered: 0, filterRate: 0, lastFilteredAt: 0 };
      this.resetConfirmation = false;
      this.statusMessage = '过滤数据已重置';
    }).catch((_error: Error): void => { this.statusMessage = '重置失败，请重试'; });
  }

  private qualityModeIndex(): number {
    if (this.filter.qualityFilterMode === QualityFilterMode.OFF) return 0;
    if (this.filter.qualityFilterMode === QualityFilterMode.HIDE) return 2;
    return 1;
  }
}
