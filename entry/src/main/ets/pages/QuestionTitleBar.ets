import { Want } from '@kit.AbilityKit';
import { getAbilityContext } from '../entryability/AbilityContextHolder';
import { createSystemShareService } from '../platform/SystemShareService';
import { SharePayloadKind } from '../platform/ShareContracts';
import { TopBarActionButton } from './components/TopBarActionButton';
import { TopBarBackMode, TopBarContent } from './components/TopBarContent';

export interface QuestionTitleState {
  id: string;
  title: string;
  scrolled: boolean;
}

export function publishQuestionTitle(state: QuestionTitleState): void {
  const states = AppStorage.get<QuestionTitleState[]>('questionTitleStates') ?? [];
  const previous = states.find((item: QuestionTitleState): boolean => item.id === state.id);
  if (previous?.title === state.title && previous?.scrolled === state.scrolled) { return; }
  AppStorage.setOrCreate('questionTitleStates',
    states.filter((item: QuestionTitleState): boolean => item.id !== state.id).concat([state]));
}

export function removeQuestionTitle(id: string): void {
  const states = AppStorage.get<QuestionTitleState[]>('questionTitleStates') ?? [];
  AppStorage.setOrCreate('questionTitleStates', states.filter((item: QuestionTitleState): boolean => item.id !== id));
}

/**
 * 问题页顶栏：首屏显示「问题」，正文标题滚出可视区后交叉淡入具体标题，回顶还原。
 * 三个按钮（返回／日志／分享）走共享悬浮圆按钮，标题切换状态仍由正文广播驱动。
 */
@Component
export struct QuestionTitleBar {
  questionId: string = '';
  onBack: () => void = (): void => {
  };
  @StorageProp('questionTitleStates') private states: QuestionTitleState[] = [];

  private state(): QuestionTitleState | undefined {
    return this.states.find((item: QuestionTitleState): boolean => item.id === this.questionId);
  }

  private async openLog(): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined || !/^[1-9][0-9]{0,29}$/.test(this.questionId)) { return; }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: `https://www.zhihu.com/question/${this.questionId}/log`
    };
    try { await context.startAbility(want); } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: '暂时无法打开问题日志' });
    }
  }

  private async share(): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined || this.state() === undefined) { return; }
    try {
      await createSystemShareService(context).share({
        kind: SharePayloadKind.TEXT,
        title: this.state()?.title ?? '问题',
        summary: this.state()?.title ?? '',
        contentUrl: `https://www.zhihu.com/question/${this.questionId}`
      });
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: '暂时无法打开分享面板' });
    }
  }

  build() {
    TopBarContent({
      backMode: TopBarBackMode.CUSTOM,
      backId: 'question_back',
      onBack: (): void => {
        this.onBack();
      },
      hasTitleSlot: true,
      titleSlot: (): void => this.questionTitleSlot(),
      hasTrailingSlot: true,
      trailingSlot: (): void => this.questionActions()
    })
  }

  @Builder
  private questionTitleSlot() {
    Stack({ alignContent: Alignment.Start }) {
      // fontSize() 必须紧跟 Text 构造器，测试 id 放在其后。
      Text('问题')
        .fontSize($r('app.float.heading_font_size'))
        .id('question_top_label')
        .maxFontScale(1.3)
        .fontColor($r('app.color.primary_text'))
        .fontWeight(FontWeight.Medium)
        .opacity(this.state()?.scrolled ? 0 : 1)
        .translate({ y: this.state()?.scrolled ? -8 : 0 })
      Text(this.state()?.title ?? '')
        .fontSize($r('app.float.heading_font_size'))
        .id('question_top_title')
        .maxFontScale(1.3)
        .fontColor($r('app.color.primary_text'))
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .opacity(this.state()?.scrolled ? 1 : 0)
        .translate({ y: this.state()?.scrolled ? 0 : 8 })
    }
    .width('100%')
    .height(40)
    .clip(true)
  }

  @Builder
  private questionActions() {
    TopBarActionButton({
      icon: $r('sys.symbol.clock'),
      elementId: 'question_log',
      label: '问题日志',
      onAction: (): void => {
        void this.openLog();
      }
    })
    TopBarActionButton({
      icon: $r('sys.symbol.share'),
      elementId: 'question_share',
      label: '分享问题',
      disabled: this.state() === undefined,
      onAction: (): void => {
        void this.share();
      }
    })
  }
}
