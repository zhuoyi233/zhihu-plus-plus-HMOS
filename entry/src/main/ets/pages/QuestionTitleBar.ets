import { Want } from '@kit.AbilityKit';
import { getAbilityContext } from '../entryability/AbilityContextHolder';
import { createSystemShareService } from '../platform/SystemShareService';
import { SharePayloadKind } from '../platform/ShareContracts';

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

@Component
export struct QuestionTitleBar {
  questionId: string = '';
  onBack: () => void = (): void => {};
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
    Row({ space: 8 }) {
      Button({ type: ButtonType.Normal }) {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(20).fontColor([$r('app.color.primary_text')])
      }.width(40).height(40).borderRadius(20).backgroundColor($r('app.color.surface_background'))
        .id('question_back').accessibilityText('返回').onClick((): void => this.onBack())
      Stack({ alignContent: Alignment.Start }) {
        Text('问题').id('question_top_label')
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontColor($r('app.color.primary_text')).fontWeight(FontWeight.Medium)
          .opacity(this.state()?.scrolled ? 0 : 1)
          .translate({ y: this.state()?.scrolled ? -8 : 0 })
        Text(this.state()?.title ?? '')
          .id('question_top_title').fontSize($r('app.float.p1_heading_font_size'))
          .fontColor($r('app.color.primary_text')).fontWeight(FontWeight.Medium)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          .opacity(this.state()?.scrolled ? 1 : 0)
          .translate({ y: this.state()?.scrolled ? 0 : 8 })
      }.layoutWeight(1).height(40).clip(true)
      Button({ type: ButtonType.Normal }) {
        SymbolGlyph($r('sys.symbol.clock')).fontSize(20).fontColor([$r('app.color.primary_text')])
      }.id('question_log').width(40).height(40).backgroundColor(Color.Transparent)
        .accessibilityText('问题日志').onClick((): void => { void this.openLog(); })
      Button({ type: ButtonType.Normal }) {
        SymbolGlyph($r('sys.symbol.share')).fontSize(20).fontColor([$r('app.color.primary_text')])
      }.id('question_share').width(40).height(40).backgroundColor(Color.Transparent)
        .enabled(this.state() !== undefined).accessibilityText('分享问题')
        .onClick((): void => { void this.share(); })
    }.width('100%').padding({ left: $r('app.float.p1_page_padding'), right: $r('app.float.p1_page_padding') })
  }
}
