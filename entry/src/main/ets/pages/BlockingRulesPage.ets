import { pasteboard, BusinessError } from '@kit.BasicServicesKit';
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
  onBack: () => void = (): void => {};
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
  @State private actionsSheetShown: boolean = false;
  @State private addRuleSheetShown: boolean = false;
  @State private backupSheetShown: boolean = false;
  @State private exportSheetShown: boolean = false;
  @State private backupInput: string = '';
  @State private exportedText: string = '';
  @State private backupStatus: string = '';
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
    this.actionsSheetShown = false;
    this.addRuleSheetShown = false;
    this.backupSheetShown = false;
    this.exportSheetShown = false;
    this.backupInput = '';
    this.exportedText = '';
    this.backupStatus = '';
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column({ space: $r('app.float.p1_spacing_medium') }) {
        this.pageHeader()
        this.preferencesPanel()
        this.tabBar()
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
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .height('100%')
      .padding($r('app.float.p1_page_padding'))
      .backgroundColor($r('app.color.page_background'))

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(24)
          .fontColor([Color.White])
      }
        .id('p3_blocking_add_rule')
        .width(56)
        .height(56)
        .padding(0)
        .borderRadius(28)
        .backgroundColor($r('app.color.brand_primary'))
        .margin({
          right: $r('app.float.p1_page_padding'),
          bottom: $r('app.float.p1_page_padding')
        })
        .accessibilityText('新增屏蔽规则')
        .enabled(!this.viewState.busy)
        .onClick((): void => {
          this.addRuleSheetShown = true;
        })

      Column()
        .bindSheet(this.actionsSheetShown, this.actionsSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false,
          maskColor: '#66000000',
          backgroundColor: $r('app.color.surface_background'),
          onDisappear: (): void => {
            if (this.actionsSheetShown) {
              this.actionsSheetShown = false;
            }
          }
        })
      Column()
        .bindSheet(this.addRuleSheetShown, this.addRuleSheet(), {
          height: SheetSize.LARGE,
          dragBar: true,
          showClose: false,
          maskColor: '#66000000',
          backgroundColor: $r('app.color.surface_background'),
          onDisappear: (): void => {
            if (this.addRuleSheetShown) {
              this.addRuleSheetShown = false;
            }
          }
        })
      Column()
        .bindSheet(this.backupSheetShown, this.backupSheet(), {
          height: SheetSize.LARGE,
          dragBar: true,
          showClose: false,
          maskColor: '#66000000',
          backgroundColor: $r('app.color.surface_background'),
          onDisappear: (): void => {
            if (this.backupSheetShown) {
              this.backupSheetShown = false;
            }
          }
        })
      Column()
        .bindSheet(this.confirmClear, this.clearConfirmation(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false,
          maskColor: '#66000000',
          backgroundColor: $r('app.color.surface_background'),
          onDisappear: (): void => {
            if (this.confirmClear) {
              this.confirmClear = false;
            }
          }
        })
      Column()
        .bindSheet(this.exportSheetShown, this.exportDialog(), {
          height: SheetSize.LARGE,
          dragBar: true,
          showClose: false,
          maskColor: '#66000000',
          backgroundColor: $r('app.color.surface_background'),
          onDisappear: (): void => {
            if (this.exportSheetShown) {
              this.exportSheetShown = false;
            }
          }
        })
    }
    .id('p2_blocking_rules_page')
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private pageHeader() {
    Row({ space: $r('app.float.p1_spacing_small') }) {
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(20)
          .fontColor([$r('app.color.primary_text')])
      }
        .id('p3_blocking_rules_back')
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText('返回')
        .onClick((): void => this.onBack())
      Text('内容屏蔽')
        .fontSize($r('app.float.p1_heading_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .layoutWeight(1)
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.ellipsis_circle'))
          .fontSize(20)
          .fontColor([$r('app.color.primary_text')])
      }
        .id('p3_blocking_rules_actions')
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText('内容屏蔽操作')
        .onClick((): void => {
          this.actionsSheetShown = true;
        })
    }
    .width('100%')
  }

  @Builder
  private actionsSheet() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Text('内容屏蔽操作')
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
          .id('p3_blocking_rules_actions_close')
          .width(40)
          .height(40)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText('关闭内容屏蔽操作')
          .onClick((): void => {
            this.actionsSheetShown = false;
          })
      }
      .width('100%')
      Button('导入或导出屏蔽规则')
        .id('p3_blocking_backup_actions')
        .width('100%')
        .fontSize($r('app.float.p1_body_font_size'))
        .enabled(!this.viewState.busy)
        .onClick((): void => {
          this.actionsSheetShown = false;
          this.backupSheetShown = true;
        })
      Button('清空当前分类')
        .id('p2_blocking_clear')
        .width('100%')
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.error_text'))
        .backgroundColor($r('app.color.control_background'))
        .enabled(!this.viewState.busy && this.currentRuleCount() > 0)
        .onClick((): void => {
          this.actionsSheetShown = false;
          this.confirmClear = true;
        })
    }
    .width('100%')
    .padding($r('app.float.p1_page_padding'))
  }

  @Builder
  private addRuleSheet() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Text(`新增${this.selectedKindLabel()}屏蔽规则`)
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
          .id('p3_blocking_add_rule_close')
          .width(40)
          .height(40)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText('关闭新增屏蔽规则')
          .onClick((): void => {
            this.addRuleSheetShown = false;
          })
      }
      .width('100%')
      this.addPanel()
    }
    .width('100%')
    .padding($r('app.float.p1_page_padding'))
  }

  @Builder
  private backupSheet() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Text('导入或导出屏蔽规则')
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
          .id('p3_blocking_backup_close')
          .width(40)
          .height(40)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText('关闭导入或导出屏蔽规则')
          .onClick((): void => {
            this.backupSheetShown = false;
          })
      }
      .width('100%')
      this.backupPanel()
    }
    .width('100%')
    .padding($r('app.float.p1_page_padding'))
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
      Text(`当前 ${this.currentRuleCount()} 条`)
        .fontSize($r('app.float.p1_caption_font_size'))
        .fontColor($r('app.color.secondary_text'))
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

  @Builder
  private backupPanel() {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      Text('导出为 JSON 文本；导入支持本应用导出的格式，无效条目会被跳过。')
        .fontSize($r('app.float.p1_caption_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      TextArea({ text: this.backupInput, placeholder: '在此粘贴要导入的屏蔽词文本' })
        .id('p3_blocking_backup_input')
        .height(80)
        .maxLength(1048576)
        .onChange((value: string): void => {
          this.backupInput = value;
        })
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Button('导入')
          .id('p3_blocking_import')
          .layoutWeight(1)
          .enabled(!this.viewState.busy && this.backupInput.trim().length > 0)
          .onClick((): void => this.importBackup())
        Button('导出')
          .id('p3_blocking_export')
          .layoutWeight(1)
          .enabled(!this.viewState.busy)
          .onClick((): void => this.exportBackup())
      }
      .width('100%')
      if (this.backupStatus.length > 0) {
        Text(this.backupStatus)
          .id('p3_blocking_backup_status')
          .fontSize($r('app.float.p1_caption_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }
    }
    .width('100%')
    .padding($r('app.float.p1_spacing_medium'))
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.p1_card_radius'))
  }

  @Builder
  private exportDialog() {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      Text('导出的屏蔽词文本')
        .fontSize($r('app.float.p1_body_font_size'))
        .fontWeight(FontWeight.Medium)
        .width('100%')
      TextArea({ text: this.exportedText })
        .id('p3_blocking_export_text')
        .height(160)
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Button('关闭')
          .layoutWeight(1)
          .onClick((): void => {
            this.exportedText = '';
            this.exportSheetShown = false;
          })
        Button('复制到剪贴板')
          .id('p3_blocking_export_copy')
          .layoutWeight(1)
          .onClick((): void => this.copyExportedText())
      }
      .width('100%')
    }
    .width('100%')
    .padding($r('app.float.p1_spacing_medium'))
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.p1_card_radius'))
  }

  private exportBackup(): void {
    this.backupStatus = '';
    this.controller?.exportBackup().then((text: string | undefined): void => {
      if (text !== undefined) {
        this.exportedText = text;
        this.backupSheetShown = false;
        this.exportSheetShown = true;
      }
    });
  }

  private copyExportedText(): void {
    const text = this.exportedText;
    if (text.length === 0) {
      return;
    }
    pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text))
      .then((): void => {
        this.backupStatus = '已复制到剪贴板';
      })
      .catch((_error: BusinessError): void => {
        this.backupStatus = '复制失败，请长按文本手动复制';
      });
  }

  private importBackup(): void {
    const text = this.backupInput;
    this.backupInput = '';
    this.backupStatus = '';
    this.controller?.importBackup(text);
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

  private selectedKindLabel(): string {
    if (this.viewState.selectedKind === BlockingRuleKind.KEYWORD) {
      return '关键词';
    }
    if (this.viewState.selectedKind === BlockingRuleKind.USER) {
      return '用户';
    }
    return '话题';
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
