import {
  BlockedKeywordRule,
  BlockedTopicRule,
  BlockedUserRule,
  BlockingPreferencesGateway,
  BlockingRuleGateway,
  BlockingRuleKind,
  defaultBlockingPreferences,
  MAX_BLOCKING_ID_LENGTH,
  MAX_BLOCKING_KEYWORD_LENGTH,
  MAX_BLOCKING_NAME_LENGTH
} from 'data';
import {
  BlockingRulesController,
  BlockingRulesPhase,
  BlockingRulesViewState
} from './BlockingRulesState';

@Component
export struct BlockingRulesPage {
  rules: BlockingRuleGateway | undefined = undefined;
  preferences: BlockingPreferencesGateway | undefined = undefined;
  @State private viewState: BlockingRulesViewState = {
    phase: BlockingRulesPhase.LOADING,
    selectedKind: BlockingRuleKind.KEYWORD,
    keywords: [],
    users: [],
    topics: [],
    preferences: defaultBlockingPreferences(),
    busy: false,
    message: '正在读取屏蔽规则'
  };
  @State private keywordInput: string = '';
  @State private caseSensitive: boolean = false;
  @State private regex: boolean = false;
  @State private identifierInput: string = '';
  @State private nameInput: string = '';
  @State private confirmClear: boolean = false;
  private controller?: BlockingRulesController;

  aboutToAppear(): void {
    const rules = this.rules;
    const preferences = this.preferences;
    if (rules === undefined || preferences === undefined) {
      this.viewState = {
        phase: BlockingRulesPhase.ERROR,
        selectedKind: BlockingRuleKind.KEYWORD,
        keywords: [],
        users: [],
        topics: [],
        preferences: defaultBlockingPreferences(),
        busy: false,
        message: '屏蔽规则数据源未配置'
      };
      return;
    }
    this.controller = new BlockingRulesController(rules, preferences,
      (state: BlockingRulesViewState): void => {
        this.viewState = state;
      });
    this.controller.activate();
  }

  aboutToDisappear(): void {
    this.controller?.deactivate();
    this.controller = undefined;
    this.keywordInput = '';
    this.identifierInput = '';
    this.nameInput = '';
    this.confirmClear = false;
  }

  build() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      this.preferencesPanel()
      this.tabBar()
      this.addPanel()
      if (this.viewState.phase === BlockingRulesPhase.LOADING && this.currentRuleCount() === 0) {
        LoadingProgress()
          .id('p2_blocking_rules_loading')
          .width(40)
          .height(40)
          .color($r('app.color.brand_primary'))
      } else {
        Text(this.viewState.message)
          .id('p2_blocking_rules_status')
          .fontSize($r('app.float.p1_caption_font_size'))
          .fontColor(this.viewState.phase === BlockingRulesPhase.ERROR ?
            $r('app.color.error_text') : $r('app.color.secondary_text'))
          .width('100%')
        this.ruleList()
      }
      if (this.confirmClear) {
        this.clearConfirmation()
      }
    }
    .id('p2_blocking_rules_page')
    .width('100%')
    .height('100%')
    .padding($r('app.float.p1_page_padding'))
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private preferencesPanel() {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      Text('屏蔽开关')
        .fontSize($r('app.float.p1_body_font_size'))
        .fontWeight(FontWeight.Medium)
        .width('100%')
      this.preferenceSwitch('关键词屏蔽', this.viewState.preferences.keywordBlockingEnabled,
        'p2_blocking_keyword_switch', (enabled: boolean): void => {
          this.controller?.savePreferences({
            keywordBlockingEnabled: enabled,
            userBlockingEnabled: this.viewState.preferences.userBlockingEnabled,
            topicBlockingEnabled: this.viewState.preferences.topicBlockingEnabled,
            topicBlockingThreshold: this.viewState.preferences.topicBlockingThreshold
          });
        })
      this.preferenceSwitch('用户屏蔽', this.viewState.preferences.userBlockingEnabled,
        'p2_blocking_user_switch', (enabled: boolean): void => {
          this.controller?.savePreferences({
            keywordBlockingEnabled: this.viewState.preferences.keywordBlockingEnabled,
            userBlockingEnabled: enabled,
            topicBlockingEnabled: this.viewState.preferences.topicBlockingEnabled,
            topicBlockingThreshold: this.viewState.preferences.topicBlockingThreshold
          });
        })
      this.preferenceSwitch('话题屏蔽', this.viewState.preferences.topicBlockingEnabled,
        'p2_blocking_topic_switch', (enabled: boolean): void => {
          this.controller?.savePreferences({
            keywordBlockingEnabled: this.viewState.preferences.keywordBlockingEnabled,
            userBlockingEnabled: this.viewState.preferences.userBlockingEnabled,
            topicBlockingEnabled: enabled,
            topicBlockingThreshold: this.viewState.preferences.topicBlockingThreshold
          });
        })
      if (this.viewState.preferences.topicBlockingEnabled) {
        Row({ space: $r('app.float.p1_spacing_small') }) {
          Text('命中话题数量达到')
            .fontSize($r('app.float.p1_body_font_size'))
            .layoutWeight(1)
          Button('−')
            .id('p2_blocking_topic_threshold_decrease')
            .enabled(!this.viewState.busy && this.viewState.preferences.topicBlockingThreshold > 1)
            .onClick((): void => this.changeTopicThreshold(-1))
          Text(`${this.viewState.preferences.topicBlockingThreshold}`)
            .fontSize($r('app.float.p1_body_font_size'))
          Button('+')
            .id('p2_blocking_topic_threshold_increase')
            .enabled(!this.viewState.busy && this.viewState.preferences.topicBlockingThreshold < 100)
            .onClick((): void => this.changeTopicThreshold(1))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .padding($r('app.float.p1_spacing_medium'))
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.p1_card_radius'))
  }

  @Builder
  private preferenceSwitch(label: string, enabled: boolean, id: string, onChange: (value: boolean) => void) {
    Row() {
      Text(label)
        .fontSize($r('app.float.p1_body_font_size'))
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: enabled })
        .id(id)
        .enabled(!this.viewState.busy)
        .onChange(onChange)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private tabBar() {
    Row({ space: $r('app.float.p1_spacing_small') }) {
      this.tabButton('关键词', BlockingRuleKind.KEYWORD, 'p2_blocking_tab_keyword')
      this.tabButton('用户', BlockingRuleKind.USER, 'p2_blocking_tab_user')
      this.tabButton('话题', BlockingRuleKind.TOPIC, 'p2_blocking_tab_topic')
    }
    .width('100%')
  }

  @Builder
  private tabButton(label: string, kind: BlockingRuleKind, id: string) {
    Button(label)
      .id(id)
      .layoutWeight(1)
      .enabled(!this.viewState.busy)
      .backgroundColor(this.viewState.selectedKind === kind ?
        $r('app.color.brand_primary') : $r('app.color.card_background'))
      .fontColor(this.viewState.selectedKind === kind ? Color.White : $r('app.color.primary_text'))
      .onClick((): void => {
        this.confirmClear = false;
        this.controller?.selectKind(kind);
      })
  }

  @Builder
  private addPanel() {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      if (this.viewState.selectedKind === BlockingRuleKind.KEYWORD) {
        TextInput({ text: this.keywordInput, placeholder: '输入关键词或安全正则' })
          .id('p2_blocking_keyword_input')
          .maxLength(MAX_BLOCKING_KEYWORD_LENGTH)
          .onChange((value: string): void => {
            this.keywordInput = value;
          })
        Row() {
          Text('区分大小写').layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.caseSensitive })
            .id('p2_blocking_case_sensitive')
            .onChange((value: boolean): void => {
              this.caseSensitive = value;
            })
          Text('正则').margin({ left: $r('app.float.p1_spacing_medium') })
          Toggle({ type: ToggleType.Switch, isOn: this.regex })
            .id('p2_blocking_regex')
            .onChange((value: boolean): void => {
              this.regex = value;
            })
        }
        .width('100%')
        Button('添加关键词规则')
          .id('p2_blocking_add_keyword')
          .enabled(!this.viewState.busy && this.keywordInput.trim().length > 0)
          .width('100%')
          .onClick((): void => {
            const keyword = this.keywordInput;
            this.keywordInput = '';
            this.controller?.addKeyword(keyword, this.caseSensitive, this.regex);
          })
      } else {
        TextInput({ text: this.identifierInput,
          placeholder: this.viewState.selectedKind === BlockingRuleKind.USER ? '用户 ID' : '话题 ID' })
          .id('p2_blocking_identifier_input')
          .maxLength(MAX_BLOCKING_ID_LENGTH)
          .onChange((value: string): void => {
            this.identifierInput = value;
          })
        TextInput({ text: this.nameInput,
          placeholder: this.viewState.selectedKind === BlockingRuleKind.USER ? '用户显示名' : '话题显示名' })
          .id('p2_blocking_name_input')
          .maxLength(MAX_BLOCKING_NAME_LENGTH)
          .onChange((value: string): void => {
            this.nameInput = value;
          })
        Button(this.viewState.selectedKind === BlockingRuleKind.USER ? '添加用户规则' : '添加话题规则')
          .id('p2_blocking_add_named_rule')
          .enabled(!this.viewState.busy && this.identifierInput.trim().length > 0 &&
            this.nameInput.trim().length > 0)
          .width('100%')
          .onClick((): void => this.addNamedRule())
      }
    }
    .width('100%')
    .padding($r('app.float.p1_spacing_medium'))
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.p1_card_radius'))
  }

  @Builder
  private ruleList() {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      Row() {
        Text(`当前 ${this.currentRuleCount()} 条`)
          .fontSize($r('app.float.p1_caption_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .layoutWeight(1)
        Button('清空当前分类')
          .id('p2_blocking_clear')
          .enabled(!this.viewState.busy && this.currentRuleCount() > 0)
          .onClick((): void => {
            this.confirmClear = true;
          })
      }
      .width('100%')
      if (this.currentRuleCount() === 0) {
        Text('当前分类暂无规则')
          .id('p2_blocking_empty')
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding($r('app.float.p1_spacing_large'))
      } else if (this.viewState.selectedKind === BlockingRuleKind.KEYWORD) {
        List({ space: 10 }) {
          ForEach(this.viewState.keywords, (rule: BlockedKeywordRule) => {
            ListItem() {
              this.keywordRow(rule)
            }
          }, (rule: BlockedKeywordRule): string => `${rule.id}`)
        }
        .id('p2_blocking_keyword_list')
        .layoutWeight(1)
      } else if (this.viewState.selectedKind === BlockingRuleKind.USER) {
        List({ space: 10 }) {
          ForEach(this.viewState.users, (rule: BlockedUserRule) => {
            ListItem() {
              this.namedRuleRow(rule.userName, rule.userId, (): void => {
                this.controller?.deleteUser(rule.userId);
              })
            }
          }, (rule: BlockedUserRule): string => rule.userId)
        }
        .id('p2_blocking_user_list')
        .layoutWeight(1)
      } else {
        List({ space: 10 }) {
          ForEach(this.viewState.topics, (rule: BlockedTopicRule) => {
            ListItem() {
              this.namedRuleRow(rule.topicName, rule.topicId, (): void => {
                this.controller?.deleteTopic(rule.topicId);
              })
            }
          }, (rule: BlockedTopicRule): string => rule.topicId)
        }
        .id('p2_blocking_topic_list')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private keywordRow(rule: BlockedKeywordRule) {
    Row({ space: $r('app.float.p1_spacing_small') }) {
      Column({ space: 2 }) {
        Text(rule.keyword)
          .fontSize($r('app.float.p1_body_font_size'))
          .width('100%')
        Text(`${rule.caseSensitive ? '区分大小写' : '忽略大小写'}${rule.isRegex ? ' · 安全正则' : ''}`)
          .fontSize($r('app.float.p1_caption_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }
      .layoutWeight(1)
      Button('删除')
        .enabled(!this.viewState.busy)
        .onClick((): void => {
          this.controller?.deleteKeyword(rule.id);
        })
    }
    .width('100%')
    .padding($r('app.float.p1_spacing_medium'))
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.p1_card_radius'))
  }

  @Builder
  private namedRuleRow(name: string, id: string, onDelete: () => void) {
    Row({ space: $r('app.float.p1_spacing_small') }) {
      Column({ space: 2 }) {
        Text(name).fontSize($r('app.float.p1_body_font_size')).width('100%')
        Text(id)
          .fontSize($r('app.float.p1_caption_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }
      .layoutWeight(1)
      Button('删除')
        .enabled(!this.viewState.busy)
        .onClick(onDelete)
    }
    .width('100%')
    .padding($r('app.float.p1_spacing_medium'))
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.p1_card_radius'))
  }

  @Builder
  private clearConfirmation() {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      Text('确认清空当前分类？此操作无法撤销。')
        .fontSize($r('app.float.p1_body_font_size'))
        .width('100%')
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Button('取消')
          .layoutWeight(1)
          .onClick((): void => {
            this.confirmClear = false;
          })
        Button('确认清空')
          .id('p2_blocking_clear_confirm')
          .layoutWeight(1)
          .enabled(!this.viewState.busy)
          .onClick((): void => {
            this.confirmClear = false;
            this.controller?.clearSelected();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding($r('app.float.p1_spacing_medium'))
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.p1_card_radius'))
  }

  private currentRuleCount(): number {
    if (this.viewState.selectedKind === BlockingRuleKind.KEYWORD) {
      return this.viewState.keywords.length;
    }
    if (this.viewState.selectedKind === BlockingRuleKind.USER) {
      return this.viewState.users.length;
    }
    return this.viewState.topics.length;
  }

  private addNamedRule(): void {
    const identifier = this.identifierInput;
    const name = this.nameInput;
    this.identifierInput = '';
    this.nameInput = '';
    if (this.viewState.selectedKind === BlockingRuleKind.USER) {
      this.controller?.addUser(identifier, name);
    } else {
      this.controller?.addTopic(identifier, name);
    }
  }

  private changeTopicThreshold(delta: number): void {
    this.controller?.savePreferences({
      keywordBlockingEnabled: this.viewState.preferences.keywordBlockingEnabled,
      userBlockingEnabled: this.viewState.preferences.userBlockingEnabled,
      topicBlockingEnabled: this.viewState.preferences.topicBlockingEnabled,
      topicBlockingThreshold: this.viewState.preferences.topicBlockingThreshold + delta
    });
  }
}
