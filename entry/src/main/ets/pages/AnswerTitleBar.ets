import { hdsMaterial } from '@kit.UIDesignKit';
import { materialCanvas } from './components/MaterialCanvas';

/** 回答页顶栏状态：问题标题 + 答主摘要 + 滚动折叠信号。
 * 跨页面经 AppStorage 广播（同 QuestionTitleBar 模式，HDS 标题栏 stackBuilder 树下
 * 常规传值不更新，必须走存储通道）。 */
export interface AnswerTitleState {
  id: string;
  activeAnswerId: string;
  documentKey: string;
  /** 回答所属问题 id：折叠态顶栏标题可点击进入该问题查看全部回答。 */
  questionId: string;
  questionTitle: string;
  authorName: string;
  authorAvatarUrl: string;
  /** 答主认证徽章图标 URL；未认证为空串。 */
  authorBadgeIconUrl: string;
  scrolled: boolean;
  authorVisible: boolean;
  materialVisible: boolean;
}

export function publishAnswerTitle(state: AnswerTitleState): void {
  const states = AppStorage.get<AnswerTitleState[]>('answerTitleStates') ?? [];
  const previous = states.find((item: AnswerTitleState): boolean => item.id === state.id);
  if (previous?.activeAnswerId === state.activeAnswerId && previous.documentKey === state.documentKey &&
    previous.questionId === state.questionId && previous?.questionTitle === state.questionTitle &&
    previous.authorName === state.authorName &&
    previous.authorAvatarUrl === state.authorAvatarUrl &&
    previous.authorBadgeIconUrl === state.authorBadgeIconUrl && previous.scrolled === state.scrolled &&
    previous.authorVisible === state.authorVisible && previous.materialVisible === state.materialVisible) {
    return;
  }
  AppStorage.setOrCreate('answerTitleStates',
    states.filter((item: AnswerTitleState): boolean => item.id !== state.id).concat([state]));
}

export function removeAnswerTitle(id: string): void {
  const states = AppStorage.get<AnswerTitleState[]>('answerTitleStates') ?? [];
  AppStorage.setOrCreate('answerTitleStates',
    states.filter((item: AnswerTitleState): boolean => item.id !== id));
}

/**
 * 回答页 HDS 标题栏（固定 48vp，HDS 自身高度 56vp 不可增高）：
 * - 未滚动：显示“回答”占位，完整问题标题由正文信息头随正文一起滚动展示；
 * - 滚动后（问题标题滚出可视区）：返回键 + 问题单行（溢出省略）+ 下方答主头像/名称。
 *
 * 「问题标题集成到顶栏」（设置项）开启后，未滚动时返回键旁也常驻问题标题（最多两行，
 * 超出省略），正文信息头不再重复展示；两种状态下的标题都可点击进入问题页。
 */
@Component
export struct AnswerTitleBar {
  answerId: string = '';
  onBack: () => void = (): void => {
  };
  /** 点击折叠态标题：进入该问题查看全部回答。 */
  onOpenQuestion: (questionId: string) => void = (_questionId: string): void => {
  };
  @StorageProp('answerTitleStates') @Watch('onStatesChanged') private states: AnswerTitleState[] = [];
  /** 问题标题是否常驻顶栏（外观设置；默认关闭，保持"滚动后才折叠进顶栏"）。 */
  @StorageProp('questionInTitleBar') private questionInTitleBar: boolean = false;
  /** 回答页过滑切换进行中：关闭整栏命中，避免移动中的返回键仍可点。 */
  @StorageProp('answerOverscrollActive') private overscrollActive: boolean = false;
  /**
   * 折叠态本地副本：广播状态变化本身不在本组件的动画作用域内，
   * 直接读 scrolled() 会让"两行标题"硬切成"单行 + 答主"。
   * 这里经 @Watch 转成本地状态并在本组件内 animateTo，切换才有过渡。
   */
  @State private folded: boolean = false;
  @State private authorVisible: boolean = false;
  private documentKey: string = '';

  aboutToAppear(): void {
    this.onStatesChanged();
  }

  private onStatesChanged(): void {
    const state = this.state();
    const next = state?.scrolled ?? false;
    const author = state?.authorVisible ?? false;
    // 回答身份立即交接；只对同一正文内的形态变化做本地动画。
    if (this.documentKey !== (state?.documentKey ?? '')) {
      this.documentKey = state?.documentKey ?? '';
      this.folded = next;
      this.authorVisible = author;
      return;
    }
    if (next === this.folded && author === this.authorVisible) { return; }
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseInOut }, (): void => {
      this.folded = next;
      this.authorVisible = author;
    });
  }

  private state(): AnswerTitleState | undefined {
    return this.states.find((item: AnswerTitleState): boolean => item.id === this.answerId);
  }

  private supportsImmersiveMaterial(): boolean {
    try {
      return hdsMaterial.getSystemMaterialTypes().includes(hdsMaterial.MaterialType.IMMERSIVE);
    } catch (_error) {
      return false;
    }
  }

  /** 顶栏是否展示问题标题：滚动折叠后始终展示；设置开启时常驻（未滚动最多两行）。 */
  private showsTitle(): boolean {
    return this.folded || this.questionInTitleBar;
  }

  /** 点击标题进入所属问题；问题 id 尚未广播（加载中）时不响应。 */
  private openQuestion(): void {
    const questionId = this.state()?.questionId ?? '';
    if (questionId.length === 0) {
      return;
    }
    this.onOpenQuestion(questionId);
  }

  build() {
    Row({ space: $r('app.float.spacing_small') }) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.supportsImmersiveMaterial()) {
          materialCanvas(52, 52)
        }
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
          .width(40)
          .height(40)
          .padding(0)
          .borderRadius(20)
          .backgroundColor(this.supportsImmersiveMaterial()
            ? Color.Transparent
            : $r('app.color.surface_background'))
          .accessibilityText('返回')
          .onClick((): void => {
            this.onBack();
          })
      }
        .width(44)
        .height(44)
        .borderRadius(22)
        .clip(true)

      // 标题压缩与作者摘要分别受几何状态控制。
      // 设置开启后未滚动也渲染：问题两行（过长省略），答主摘要仍只在折叠态出现。
      if (this.showsTitle()) {
        Column({ space: 2 }) {
          Text(this.state()?.questionTitle || '回答')
            .id('answer_top_question')
            // 16fp、22vp 行高在固定栏高内容纳两行，允许系统字号放大至 1.3 倍。
            .fontSize(16)
            .lineHeight(22)
            .maxFontScale(1.3)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .maxLines(this.folded ? 1 : 2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .accessibilityDescription('点击查看问题和全部回答')
            .onClick((): void => {
              this.openQuestion();
            })
          if (this.authorVisible) {
            Row({ space: 4 }) {
              Stack({ alignContent: Alignment.Center }) {
                Circle()
                  .width(18)
                  .height(18)
                  .fill($r('app.color.control_background'))
                if ((this.state()?.authorAvatarUrl ?? '').length > 0) {
                  Image(this.state()?.authorAvatarUrl ?? '')
                    .id('answer_top_author_avatar')
                    .width(18)
                    .height(18)
                    .borderRadius(9)
                    .objectFit(ImageFit.Cover)
                } else if ((this.state()?.authorName ?? '').length > 0) {
                  Text((this.state()?.authorName ?? '').substring(0, 1))
                    .fontSize($r('app.float.caption_font_size'))
                    .maxFontScale(1.3)
                    .fontColor($r('app.color.secondary_text'))
                }
              }
                .width(18)
                .height(18)
                .clip(true)
              // 名称 + 徽章同组：名称 flexShrink 收缩省略，徽章紧跟名字右侧（对齐上游）。
              Row({ space: 4 }) {
                Text(this.state()?.authorName ?? '')
                  .id('answer_top_author')
                  .fontSize($r('app.float.caption_font_size'))
                  .maxFontScale(1.3)
                  .fontColor($r('app.color.secondary_text'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .flexShrink(1)
                // 答主认证徽章（对齐上游 compact AuthorBadge：折叠顶栏名称后 14vp 图标）。
                if ((this.state()?.authorBadgeIconUrl ?? '').length > 0) {
                  Image(this.state()?.authorBadgeIconUrl ?? '')
                    .id('answer_top_author_badge')
                    .width(14)
                    .height(14)
                    .objectFit(ImageFit.Contain)
                    .draggable(false)
                    .flexShrink(0)
                }
              }
              .alignItems(VerticalAlign.Center)
              .layoutWeight(1)
            }
            .width('100%')
            // 答主行淡入 + 轻微上移，避免标题从两行硬切成"单行 + 答主"。
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.translate({ y: 6 })))
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .transition(TransitionEffect.OPACITY)
      } else {
        Text('回答')
          .id('answer_top_placeholder')
          .fontSize(20)
          .maxFontScale(1.3)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .height(48)
    .backgroundBlurStyle(this.state()?.materialVisible ? BlurStyle.COMPONENT_ULTRA_THIN : BlurStyle.NONE)
    .padding({
      left: $r('app.float.page_padding'),
      right: $r('app.float.page_padding')
    })
    .alignItems(VerticalAlign.Center)
    // 过滑切换进行中：关闭整栏命中，避免移动中的返回键仍可点。
    .hitTestBehavior(this.overscrollActive ? HitTestMode.None : HitTestMode.Transparent)
  }
}
