import { CenteredOverlayDialog } from './CenteredOverlayDialog';
import {
  consumeTopBarAction,
  publishTopBarActionState,
  removeTopBarActionState
} from '../common/style/TopBarActionBus';
import { pasteboard, BusinessError } from '@kit.BasicServicesKit';
import {
  BlockedKeywordRule,
  BlockedTopicRule,
  BlockedUserRule,
  BlockingPreferencesGateway,
  BlockingRuleGateway,
  BlockingRuleKind,
  BlocklistBackupImportSummary,
  DEFAULT_THEME_COLOR,
  defaultBlockingPreferences,
  FeedCardStyle,
  MAX_BLOCKING_ID_LENGTH,
  MAX_BLOCKING_KEYWORD_LENGTH,
  MAX_BLOCKING_NAME_LENGTH,
  onThemeColor
} from 'data';
import {
  BlockingRulesController,
  BlockingRulesPhase,
  BlockingRulesViewState
} from './BlockingRulesState';
import { adaptiveOverlayWidth, isWideOverlayContainer, ADAPTIVE_OVERLAY_MENU_WIDTH_VP } from '../common/style/AdaptiveOverlayLayout';
import { settingsGroupBackground, settingsGroupRadius } from './AccountSettingsLayout';
import { SettingsHighlightGroup } from '../components/SettingsSearchHighlight';
import { SettingsSearchLocationRunner } from './SettingsSearchLocationRunner';
import { readLocationRequest, SettingsPaneId, SettingsSearchLocationRequest } from './SettingsSearchTarget';

import { floatingTitleBarOffset } from './AppPageChrome';

/** 本页在顶栏动作通道里的注册 id（独立路由实例）。 */
const BLOCKING_RULES_TOP_BAR_ID: string = 'blocking_rules';

/**
 * 内容屏蔽：开关组、分类、计数与规则行共用一个主滚动，嵌入设置右栏时由宿主画标题。
 *
 * 新增入口从右下角悬浮加号改为计数行的按钮：不再遮挡最后一条规则，也不会在键盘弹出时
 * 盖住表单。弹层在嵌入模式下限定在承载栏内的覆盖容器，避免全屏 sheet 遮住整个设置。
 */
@Component
export struct BlockingRulesPage {
  rules: BlockingRuleGateway | undefined = undefined;
  preferences: BlockingPreferencesGateway | undefined = undefined;
  onBack: () => void = (): void => {};
  /** 嵌入设置容器：不画自带标题、不叠加覆盖式让位，动作交给宿主标题栏。 */
  @Prop embedded: boolean = false;
  onRegisterHeaderActions: (handler: () => void) => void = (_handler: () => void): void => {};
  onReleaseHeaderActions: () => void = (): void => {};
  /** 独立路由（非嵌入）时向宿主 AppShell 注册顶栏“更多”动作；嵌入设置时走宿主注册协议。 */
  @StorageProp('topBarActionTick') @Watch('onTopBarActionTick') private topBarActionTick: number = 0;
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
  @State @Watch('clearDialogChanged') private confirmClear: boolean = false;
  /** 清空确认绑定打开时的分类，后台切换分类不会清错类别。 */
  @State private pendingClearKind: BlockingRuleKind = BlockingRuleKind.KEYWORD;
  @State private pendingClearCount: number = 0;
  @State private actionsSheetShown: boolean = false;
  @State private addRuleSheetShown: boolean = false;
  @State private backupSheetShown: boolean = false;
  @State private exportSheetShown: boolean = false;
  @State private backupInput: string = '';
  @State private exportedText: string = '';
  @State private backupStatus: string = '';
  @State private overlayWidthVp: number = 0;
  @StorageProp('statusBarHeight') private statusBarHeightVp: number = 0;
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @StorageProp('feedCardStyle') private feedCardStyle: string = FeedCardStyle.DIVIDER;
  private controller?: BlockingRulesController;

  private clearDialog: CustomDialogController = new CustomDialogController({
    builder: CenteredOverlayDialog({ content: (): void => { this.clearConfirmation(); } }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    maskColor: '#99000000',
    backgroundColor: $r('app.color.surface_background'),
    cancel: (): void => { this.confirmClear = false; }
  });

  private clearDialogChanged(): void {
    if (this.confirmClear) {
      this.clearDialog.open();
    } else {
      this.clearDialog.close();
    }
  }

  /** 搜索定位：本页滚动容器执行器与请求 tick 监听。 */
  private scroller: Scroller = new Scroller();
  private locator: SettingsSearchLocationRunner | undefined = undefined;
  @StorageProp('settingsSearchLocationTick') @Watch('onSearchLocationRequest')
  private searchLocationTick: number = 0;

  private onSearchLocationRequest(): void {
    this.consumeSearchLocation();
  }


  /** 消费定位请求：仅嵌入设置实例且目标为本页时执行滚动与提醒。 */
  private consumeSearchLocation(): void {
    const request = readLocationRequest();
    if (request === undefined || request.paneId !== SettingsPaneId.BLOCKING_RULES || !this.embedded) {
      return;
    }
    this.locator?.cancel(false);
    this.locator = new SettingsSearchLocationRunner({
      getUIContext: (): UIContext => this.getUIContext(),
      isEmbedded: (): boolean => this.embedded,
      isReady: (): boolean => true,
      getScroller: (): Scroller => this.scroller,
      scrollId: 'blocking_rules_scroll',
      contentId: 'blocking_rules_content',
      desiredTop: (): number => floatingTitleBarOffset() + 12,
      onFailed: (): void => this.getUIContext().getPromptAction().showToast({
        message: '暂时无法定位，请稍后重试', duration: 2000
      }),
      onFallback: (): void => this.getUIContext().getPromptAction().showToast({
        message: '该项当前被隐藏，已定位到前置开关', duration: 2000
      })
    });
    this.locator.consume(request);
  }
  aboutToAppear(): void {
    if (this.embedded) {
      this.onRegisterHeaderActions((): void => {
        this.actionsSheetShown = true;
      });
    } else {
      // 独立路由：标题与返回由宿主 HDS 标题栏承载，本页只注册“更多”动作。
      publishTopBarActionState({ id: BLOCKING_RULES_TOP_BAR_ID, available: true, title: '', text: '', enabled: true });
    }
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
    if (this.controller !== undefined) {
      this.controller.activate();
      return;
    }
    this.controller = new BlockingRulesController(rules, preferences,
      (state: BlockingRulesViewState): void => {
        this.viewState = state;
      });
    this.controller.activate();
  }

  aboutToDisappear(): void {
    if (this.embedded) {
      this.onReleaseHeaderActions();
      this.locator?.cancel(false);
      this.locator = undefined;
    } else {
      removeTopBarActionState(BLOCKING_RULES_TOP_BAR_ID);
    }
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

  private isCardStyle(): boolean {
    return this.feedCardStyle === FeedCardStyle.CARD;
  }

  private anyOverlayShown(): boolean {
    return this.actionsSheetShown || this.addRuleSheetShown || this.backupSheetShown || this.exportSheetShown;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll(this.scroller) {
        Column({ space: $r('app.float.spacing_medium') }) {
          this.preferencesPanel()
          this.tabBar()
          this.countRow()
          this.statusRow()
          this.ruleRows()
        }
        .id('blocking_rules_content')
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({
          left: $r('app.float.page_padding'),
          right: $r('app.float.page_padding'),
          top: this.embedded ? 4 : 94,
          bottom: $r('app.float.page_padding')
        })
      }
      .id('blocking_rules_scroll')
      .onScrollStart((): void => {
        this.locator?.onScrollStarted();
      })
      .onScrollStop((): void => {
        this.locator?.onScrollStopped();
      })
      .width('100%')
      .height('100%')
      // 内容不足一屏时 Scroll 默认居中，会让标题下出现大段空白；固定从顶部开始排。
      .align(Alignment.TopStart)
      // 顶栏覆盖式呈现：内容从栏下沿开始，滚动时穿过顶栏。
      .contentStartOffset(this.embedded ? floatingTitleBarOffset() : 0)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .backgroundColor($r('app.color.page_background'))

      if (!this.embedded) {
        // 独立入口：标题、返回与“更多”全部由宿主 HDS 标题栏承载，页面不再自绘顶栏。
        // 独立路由沿用系统 sheet；嵌入模式改在右栏内做覆盖容器（见下）。
        Column()
          .bindSheet(this.addRuleSheetShown, this.addRuleSheet(), {
            preferType: SheetType.CENTER,
            height: SheetSize.LARGE,
            dragBar: false,
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
            preferType: SheetType.CENTER,
            height: SheetSize.LARGE,
            dragBar: false,
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
          .bindSheet(this.exportSheetShown, this.exportDialog(), {
            preferType: SheetType.CENTER,
            height: SheetSize.LARGE,
            dragBar: false,
            showClose: false,
            maskColor: '#66000000',
            backgroundColor: $r('app.color.surface_background'),
            onDisappear: (): void => {
              if (this.exportSheetShown) {
                this.exportSheetShown = false;
              }
            }
          })
      } else if (this.anyOverlayShown()) {
        this.embeddedOverlay()
      }
    }
    .id('blocking_rules_page')
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      const width = Number(newArea.width);
      if (width > 0) {
        this.overlayWidthVp = width;
      }
    })
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private embeddedOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick((): void => {
          this.closeAllOverlays();
        })
      Column() {
        Scroll() {
          Column() {
            this.modalBody()
          }
          .width('100%')
        }
        .scrollBar(BarState.Off)
        .constraintSize({ maxHeight: '85%' })
      }
      .width('92%')
      .constraintSize({ maxWidth: 560 })
      .backgroundColor(settingsGroupBackground(FeedCardStyle.CARD))
      .borderRadius(settingsGroupRadius(FeedCardStyle.CARD))
      .clip(true)
      .shadow({ radius: 24, color: '#33000000', offsetY: 8 })
    }
    .id('blocking_rules_overlay')
    .width('100%')
    .height('100%')
    .zIndex(3)
  }

  @Builder
  private modalBody() {
    if (this.addRuleSheetShown) {
      this.addRuleSheet()
    } else if (this.backupSheetShown) {
      this.backupSheet()
    } else if (this.exportSheetShown) {
      this.exportDialog()
    } else {
      this.actionsSheet()
    }
  }

  private closeAllOverlays(): void {
    this.actionsSheetShown = false;
    this.addRuleSheetShown = false;
    this.backupSheetShown = false;
    this.exportSheetShown = false;
  }

  /** 顶栏“更多”被宿主点击：转调本页操作弹层（嵌入/独立两种入口同一实现）。 */
  private onTopBarActionTick(): void {
    if (consumeTopBarAction(BLOCKING_RULES_TOP_BAR_ID)) {
      this.actionsSheetShown = true;
    }
  }

  @Builder
  private actionsSheet() {
    Column({ space: $r('app.float.spacing_medium') }) {
      Row({ space: $r('app.float.spacing_small') }) {
        Text('内容屏蔽操作')
          .fontSize($r('app.float.heading_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
          .id('blocking_rules_actions_close')
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
        .backgroundColor($r('app.color.control_background'))
        .fontColor($r('app.color.primary_text'))
        .id('blocking_backup_actions')
        .width('100%')
        .fontSize($r('app.float.body_font_size'))
        .enabled(!this.viewState.busy)
        .onClick((): void => {
          this.actionsSheetShown = false;
          this.backupSheetShown = true;
        })
      Button('清空当前分类')
        .id('blocking_clear')
        .width('100%')
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.error_text'))
        .backgroundColor($r('app.color.control_background'))
        .enabled(!this.viewState.busy && this.currentRuleCount() > 0)
        .onClick((): void => {
          this.actionsSheetShown = false;
          this.openClearConfirmation();
        })
    }
    .width('100%')
    .padding($r('app.float.page_padding'))
  }

  @Builder
  private addRuleSheet() {
    Column({ space: $r('app.float.spacing_medium') }) {
      Row({ space: $r('app.float.spacing_small') }) {
        Text(`新增${this.selectedKindLabel()}屏蔽规则`)
          .fontSize($r('app.float.heading_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
          .id('blocking_add_rule_close')
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
    .padding($r('app.float.page_padding'))
  }

  @Builder
  private backupSheet() {
    Column({ space: $r('app.float.spacing_medium') }) {
      Row({ space: $r('app.float.spacing_small') }) {
        Text('导入或导出屏蔽规则')
          .fontSize($r('app.float.heading_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
          .id('blocking_backup_close')
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
    .padding($r('app.float.page_padding'))
  }

  @Builder
  private preferencesPanel() {
    Column({ space: $r('app.float.spacing_small') }) {
      Text('屏蔽开关')
        .fontSize($r('app.float.caption_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      this.preferenceSwitch('关键词屏蔽', this.viewState.preferences.keywordBlockingEnabled,
        'blocking_keyword_switch', (enabled: boolean): void => {
          this.controller?.savePreferences({
            keywordBlockingEnabled: enabled,
            userBlockingEnabled: this.viewState.preferences.userBlockingEnabled,
            topicBlockingEnabled: this.viewState.preferences.topicBlockingEnabled,
            topicBlockingThreshold: this.viewState.preferences.topicBlockingThreshold
          });
        })
      Divider().color($r('app.color.divider_color'))
      this.preferenceSwitch('用户屏蔽', this.viewState.preferences.userBlockingEnabled,
        'blocking_user_switch', (enabled: boolean): void => {
          this.controller?.savePreferences({
            keywordBlockingEnabled: this.viewState.preferences.keywordBlockingEnabled,
            userBlockingEnabled: enabled,
            topicBlockingEnabled: this.viewState.preferences.topicBlockingEnabled,
            topicBlockingThreshold: this.viewState.preferences.topicBlockingThreshold
          });
        })
      Divider().color($r('app.color.divider_color'))
      this.preferenceSwitch('话题屏蔽', this.viewState.preferences.topicBlockingEnabled,
        'blocking_topic_switch', (enabled: boolean): void => {
          this.controller?.savePreferences({
            keywordBlockingEnabled: this.viewState.preferences.keywordBlockingEnabled,
            userBlockingEnabled: this.viewState.preferences.userBlockingEnabled,
            topicBlockingEnabled: enabled,
            topicBlockingThreshold: this.viewState.preferences.topicBlockingThreshold
          });
        })
      if (this.viewState.preferences.topicBlockingEnabled) {
        Divider().color($r('app.color.divider_color'))
        Row({ space: $r('app.float.spacing_small') }) {
          Text('命中话题数量达到')
            .fontSize($r('app.float.body_font_size'))
            .fontColor($r('app.color.primary_text'))
            .layoutWeight(1)
          Button('−')
            .backgroundColor($r('app.color.control_background'))
            .fontColor($r('app.color.primary_text'))
            .id('blocking_topic_threshold_decrease')
            .enabled(!this.viewState.busy && this.viewState.preferences.topicBlockingThreshold > 1)
            .onClick((): void => this.changeTopicThreshold(-1))
          Text(`${this.viewState.preferences.topicBlockingThreshold}`)
            .fontSize($r('app.float.body_font_size'))
          Button('+')
            .backgroundColor($r('app.color.control_background'))
            .fontColor($r('app.color.primary_text'))
            .id('blocking_topic_threshold_increase')
            .enabled(!this.viewState.busy && this.viewState.preferences.topicBlockingThreshold < 100)
            .onClick((): void => this.changeTopicThreshold(1))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .padding($r('app.float.spacing_medium'))
    .backgroundColor(settingsGroupBackground(this.feedCardStyle))
    .borderRadius(settingsGroupRadius(this.feedCardStyle))
  }

  @Builder
  private preferenceSwitch(label: string, enabled: boolean, id: string, onChange: (value: boolean) => void) {
    Row() {
      Text(label)
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: enabled })
        .id(id)
        .selectedColor(this.resolvedThemeColor)
        .enabled(!this.viewState.busy)
        .onChange(onChange)
    }
    .width('100%')
    .height(44)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private tabBar() {
    Row({ space: $r('app.float.spacing_small') }) {
      this.tabButton('关键词', BlockingRuleKind.KEYWORD, 'blocking_tab_keyword')
      this.tabButton('用户', BlockingRuleKind.USER, 'blocking_tab_user')
      this.tabButton('话题', BlockingRuleKind.TOPIC, 'blocking_tab_topic')
    }
    .width('100%')
  }

  @Builder
  private tabButton(label: string, kind: BlockingRuleKind, id: string) {
    Button(label)
      .id(id)
      .layoutWeight(1)
      .height(40)
      .fontSize($r('app.float.body_font_size'))
      .enabled(!this.viewState.busy)
      .backgroundColor(this.viewState.selectedKind === kind ?
        this.resolvedThemeColor : $r('app.color.control_background'))
      .fontColor(this.viewState.selectedKind === kind ?
        onThemeColor(this.resolvedThemeColor) : $r('app.color.primary_text'))
      .onClick((): void => {
        this.confirmClear = false;
        this.controller?.selectKind(kind);
      })
  }

  @Builder
  private countRow() {
    Row({ space: $r('app.float.spacing_small') }) {
      Text(`当前 ${this.currentRuleCount()} 条`)
        .fontSize($r('app.float.caption_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .layoutWeight(1)
      Button('新增规则')
        .id('blocking_add_rule')
        .height(36)
        .fontSize($r('app.float.secondary_font_size'))
        .fontColor(onThemeColor(this.resolvedThemeColor))
        .backgroundColor(this.resolvedThemeColor)
        .enabled(!this.viewState.busy)
        .accessibilityText(`新增${this.selectedKindLabel()}屏蔽规则`)
        .onClick((): void => {
          this.addRuleSheetShown = true;
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private statusRow() {
    if (this.viewState.message.length > 0) {
      Text(this.viewState.message)
        .id('blocking_rules_status')
        .fontSize($r('app.float.caption_font_size'))
        .fontColor(this.viewState.phase === BlockingRulesPhase.ERROR ?
          $r('app.color.error_text') : $r('app.color.secondary_text'))
        .width('100%')
    }
  }

  @Builder
  private ruleRows() {
    if (this.viewState.phase === BlockingRulesPhase.LOADING && this.currentRuleCount() === 0) {
      Row() {
        LoadingProgress()
          .id('blocking_rules_loading')
          .width(40)
          .height(40)
          .color(this.resolvedThemeColor)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 32, bottom: 32 })
    } else if (this.currentRuleCount() === 0) {
      Text('当前分类暂无规则')
        .id('blocking_empty')
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding($r('app.float.spacing_large'))
    } else if (this.viewState.selectedKind === BlockingRuleKind.KEYWORD) {
      Column({ space: this.isCardStyle() ? 10 : 0 }) {
        ForEach(this.viewState.keywords, (rule: BlockedKeywordRule) => {
          this.keywordRow(rule)
        }, (rule: BlockedKeywordRule): string => `${rule.id}`)
      }
      .id('blocking_keyword_list')
      .width('100%')
    } else if (this.viewState.selectedKind === BlockingRuleKind.USER) {
      Column({ space: this.isCardStyle() ? 10 : 0 }) {
        ForEach(this.viewState.users, (rule: BlockedUserRule) => {
          this.namedRuleRow(rule.questionAuthorOnly === true ? `提问者：${rule.userName}` : rule.userName, rule.userId,
            (): void => {
              this.controller?.deleteUser(rule.userId);
            })
        }, (rule: BlockedUserRule): string => rule.userId)
      }
      .id('blocking_user_list')
      .width('100%')
    } else {
      Column({ space: this.isCardStyle() ? 10 : 0 }) {
        ForEach(this.viewState.topics, (rule: BlockedTopicRule) => {
          this.namedRuleRow(rule.topicName, rule.topicId, (): void => {
            this.controller?.deleteTopic(rule.topicId);
          })
        }, (rule: BlockedTopicRule): string => rule.topicId)
      }
      .id('blocking_topic_list')
      .width('100%')
    }
  }

  @Builder
  private addPanel() {
    Column({ space: $r('app.float.spacing_small') }) {
      if (this.viewState.selectedKind === BlockingRuleKind.KEYWORD) {
        TextInput({ text: this.keywordInput, placeholder: '输入关键词或安全正则' })
          .id('blocking_keyword_input')
          .maxLength(MAX_BLOCKING_KEYWORD_LENGTH)
          .onChange((value: string): void => {
            this.keywordInput = value;
          })
        Row() {
          Text('区分大小写')
            .fontSize($r('app.float.body_font_size'))
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.caseSensitive })
            .id('blocking_case_sensitive')
            .selectedColor(this.resolvedThemeColor)
            .onChange((value: boolean): void => {
              this.caseSensitive = value;
            })
          Text('正则')
            .fontSize($r('app.float.body_font_size'))
            .margin({ left: $r('app.float.spacing_medium') })
          Toggle({ type: ToggleType.Switch, isOn: this.regex })
            .id('blocking_regex')
            .selectedColor(this.resolvedThemeColor)
            .onChange((value: boolean): void => {
              this.regex = value;
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        Button('添加关键词规则')
          .id('blocking_add_keyword')
          .enabled(!this.viewState.busy && this.keywordInput.trim().length > 0)
          .width('100%')
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .backgroundColor(this.resolvedThemeColor)
          .onClick((): void => {
            void this.submitKeyword();
          })
      } else {
        TextInput({ text: this.identifierInput,
          placeholder: this.viewState.selectedKind === BlockingRuleKind.USER ? '用户 ID' : '话题 ID' })
          .id('blocking_identifier_input')
          .maxLength(MAX_BLOCKING_ID_LENGTH)
          .onChange((value: string): void => {
            this.identifierInput = value;
          })
        TextInput({ text: this.nameInput,
          placeholder: this.viewState.selectedKind === BlockingRuleKind.USER ? '用户显示名' : '话题显示名' })
          .id('blocking_name_input')
          .maxLength(MAX_BLOCKING_NAME_LENGTH)
          .onChange((value: string): void => {
            this.nameInput = value;
          })
        Button(this.viewState.selectedKind === BlockingRuleKind.USER ? '添加用户规则' : '添加话题规则')
          .id('blocking_add_named_rule')
          .enabled(!this.viewState.busy && this.identifierInput.trim().length > 0 &&
            this.nameInput.trim().length > 0)
          .width('100%')
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .backgroundColor(this.resolvedThemeColor)
          .onClick((): void => {
            void this.submitNamedRule();
          })
      }
    }
    .width('100%')
    .padding($r('app.float.spacing_medium'))
    .backgroundColor(settingsGroupBackground(this.feedCardStyle))
    .borderRadius(settingsGroupRadius(this.feedCardStyle))
  }

  @Builder
  private keywordRow(rule: BlockedKeywordRule) {
    Row({ space: $r('app.float.spacing_small') }) {
      Column({ space: 2 }) {
        Text(rule.keyword)
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.primary_text'))
          .width('100%')
        Text(`${rule.caseSensitive ? '区分大小写' : '忽略大小写'}${rule.isRegex ? ' · 安全正则' : ''}`)
          .fontSize($r('app.float.caption_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }
      .layoutWeight(1)
      Button('删除')
        .backgroundColor($r('app.color.control_background'))
        .fontColor($r('app.color.primary_text'))
        .fontSize($r('app.float.secondary_font_size'))
        .enabled(!this.viewState.busy)
        .accessibilityText(`删除关键词规则 ${rule.keyword}`)
        .onClick((): void => {
          this.controller?.deleteKeyword(rule.id);
        })
    }
    .width('100%')
    .padding(this.isCardStyle() ? 14 : 12)
    .backgroundColor(this.isCardStyle() ? $r('app.color.card_background') : Color.Transparent)
    .borderRadius(this.isCardStyle() ? $r('app.float.card_radius') : 0)
  }

  @Builder
  private namedRuleRow(name: string, id: string, onDelete: () => void) {
    Row({ space: $r('app.float.spacing_small') }) {
      Column({ space: 2 }) {
        Text(name)
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.primary_text'))
          .width('100%')
        Text(id)
          .fontSize($r('app.float.caption_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }
      .layoutWeight(1)
      Button('删除')
        .backgroundColor($r('app.color.control_background'))
        .fontColor($r('app.color.primary_text'))
        .fontSize($r('app.float.secondary_font_size'))
        .enabled(!this.viewState.busy)
        .accessibilityText(`删除${this.selectedKindLabel()}规则 ${name}`)
        .onClick(onDelete)
    }
    .width('100%')
    .padding(this.isCardStyle() ? 14 : 12)
    .backgroundColor(this.isCardStyle() ? $r('app.color.card_background') : Color.Transparent)
    .borderRadius(this.isCardStyle() ? $r('app.float.card_radius') : 0)
  }

  @Builder
  private clearConfirmation() {
    Column({ space: $r('app.float.spacing_small') }) {
      Text(`确认清空${this.kindLabel(this.pendingClearKind)}屏蔽规则？`)
        .fontSize($r('app.float.body_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Text(`打开确认时该分类有 ${this.pendingClearCount} 条规则；只清空这一分类，其他分类与屏蔽记录不受影响。此操作无法撤销。`)
        .fontSize($r('app.float.caption_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      Row({ space: $r('app.float.spacing_small') }) {
        Button('取消')
          .backgroundColor($r('app.color.control_background'))
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
          .onClick((): void => {
            this.confirmClear = false;
          })
        Button('确认清空')
          .backgroundColor(this.resolvedThemeColor)
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .id('blocking_clear_confirm')
          .layoutWeight(1)
          .enabled(!this.viewState.busy)
          .onClick((): void => {
            this.confirmClear = false;
            if (this.pendingClearKind !== this.viewState.selectedKind) {
              this.controller?.selectKind(this.pendingClearKind);
            }
            this.controller?.clearKind(this.pendingClearKind);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding($r('app.float.spacing_medium'))
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.card_radius'))
  }

  @Builder
  private backupPanel() {
    Column({ space: $r('app.float.spacing_small') }) {
      Text('导出为 JSON 文本；导入支持本应用导出的格式，无效条目会被跳过。')
        .fontSize($r('app.float.caption_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      TextArea({ text: this.backupInput, placeholder: '在此粘贴要导入的屏蔽词文本' })
        .id('blocking_backup_input')
        .height(80)
        .maxLength(1048576)
        .onChange((value: string): void => {
          this.backupInput = value;
        })
      Row({ space: $r('app.float.spacing_small') }) {
        Button('导入')
          .backgroundColor(this.resolvedThemeColor)
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .id('blocking_import')
          .layoutWeight(1)
          .enabled(!this.viewState.busy && this.backupInput.trim().length > 0)
          .onClick((): void => this.importBackup())
        Button('导出')
          .backgroundColor(this.resolvedThemeColor)
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .id('blocking_export')
          .layoutWeight(1)
          .enabled(!this.viewState.busy)
          .onClick((): void => this.exportBackup())
      }
      .width('100%')
      if (this.backupStatus.length > 0) {
        Text(this.backupStatus)
          .id('blocking_backup_status')
          .fontSize($r('app.float.caption_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }
    }
    .width('100%')
    .padding($r('app.float.spacing_medium'))
    .backgroundColor(settingsGroupBackground(this.feedCardStyle))
    .borderRadius(settingsGroupRadius(this.feedCardStyle))
  }

  @Builder
  private exportDialog() {
    Column({ space: $r('app.float.spacing_small') }) {
      Text('导出的屏蔽词文本')
        .fontSize($r('app.float.body_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      TextArea({ text: this.exportedText })
        .id('blocking_export_text')
        .height(160)
      if (this.backupStatus.length > 0) {
        Text(this.backupStatus)
          .id('blocking_export_status')
          .fontSize($r('app.float.caption_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }
      Row({ space: $r('app.float.spacing_small') }) {
        Button('关闭')
          .backgroundColor($r('app.color.control_background'))
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
          .onClick((): void => {
            this.exportedText = '';
            this.backupStatus = '';
            this.exportSheetShown = false;
          })
        Button('复制到剪贴板')
          .backgroundColor(this.resolvedThemeColor)
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .id('blocking_export_copy')
          .layoutWeight(1)
          .onClick((): void => this.copyExportedText())
      }
      .width('100%')
    }
    .width('100%')
    .padding($r('app.float.spacing_medium'))
    .backgroundColor(settingsGroupBackground(this.feedCardStyle))
    .borderRadius(settingsGroupRadius(this.feedCardStyle))
  }

  private openClearConfirmation(): void {
    this.pendingClearKind = this.viewState.selectedKind;
    this.pendingClearCount = this.currentRuleCount();
    this.confirmClear = true;
  }

  private async submitKeyword(): Promise<void> {
    const keyword = this.keywordInput;
    if (keyword.trim().length === 0 || this.viewState.busy) {
      return;
    }
    await this.controller?.addKeyword(keyword, this.caseSensitive, this.regex);
    // 只有真正保存成功（phase 回到 READY）才清空并关闭表单，失败保留输入供重试。
    if (this.viewState.phase === BlockingRulesPhase.READY) {
      this.keywordInput = '';
      this.addRuleSheetShown = false;
    }
  }

  private async submitNamedRule(): Promise<void> {
    const identifier = this.identifierInput;
    const name = this.nameInput;
    if (identifier.trim().length === 0 || name.trim().length === 0 || this.viewState.busy) {
      return;
    }
    if (this.viewState.selectedKind === BlockingRuleKind.USER) {
      await this.controller?.addUser(identifier, name);
    } else {
      await this.controller?.addTopic(identifier, name);
    }
    if (this.viewState.phase === BlockingRulesPhase.READY) {
      this.identifierInput = '';
      this.nameInput = '';
      this.addRuleSheetShown = false;
    }
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
    if (text.trim().length === 0) {
      return;
    }
    this.backupStatus = '';
    this.controller?.importBackup(text).then((summary: BlocklistBackupImportSummary | undefined): void => {
      if (summary !== undefined && this.viewState.phase === BlockingRulesPhase.READY) {
        // 导入成功才清空输入；失败保留文本，允许直接重试。
        this.backupInput = '';
      }
    });
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
    return this.kindLabel(this.viewState.selectedKind);
  }

  private kindLabel(kind: BlockingRuleKind): string {
    if (kind === BlockingRuleKind.KEYWORD) {
      return '关键词';
    }
    if (kind === BlockingRuleKind.USER) {
      return '用户';
    }
    return '话题';
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
