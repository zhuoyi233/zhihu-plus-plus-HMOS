import { HarmonyOSCapabilities } from '../common/platform/HarmonyOSCapabilities';
import { materialCanvas } from './components/MaterialCanvas';

/** 评论页标题栏状态；用内容来源作键，避免返回被覆盖的评论页时串到其他页面。 */
export interface CommentTitleState {
  id: string;
  replying: boolean;
}

export function commentTitleStateId(contentType: string, contentId: string): string {
  return `${contentType}:${contentId}`;
}

export function publishCommentTitle(state: CommentTitleState): void {
  const states = AppStorage.get<CommentTitleState[]>('commentTitleStates') ?? [];
  const previous = states.find((item: CommentTitleState): boolean => item.id === state.id);
  if (previous?.replying === state.replying) {
    return;
  }
  AppStorage.setOrCreate('commentTitleStates',
    states.filter((item: CommentTitleState): boolean => item.id !== state.id).concat([state]));
}

export function removeCommentTitle(id: string): void {
  const states = AppStorage.get<CommentTitleState[]>('commentTitleStates') ?? [];
  AppStorage.setOrCreate('commentTitleStates',
    states.filter((item: CommentTitleState): boolean => item.id !== id));
}

/**
 * 评论页 HDS 标题栏内容：标题栏的滚动态材质由 HdsNavDestination 承载，返回键
 * 单独复用详情页的沉浸光感画布，根评论/子评论标题经 AppStorage 跨构建树更新。
 */
@Component
export struct CommentTitleBar {
  stateId: string = '';
  onBack: () => void = (): void => {
  };
  @StorageProp('commentTitleStates') private states: CommentTitleState[] = [];

  private replying(): boolean {
    return this.states.find((item: CommentTitleState): boolean => item.id === this.stateId)?.replying ?? false;
  }

  build() {
    Row({ space: $r('app.float.p1_spacing_small') }) {
      Stack({ alignContent: Alignment.Center }) {
        if (HarmonyOSCapabilities.supportsImmersiveMaterial()) {
          materialCanvas(52, 52)
        }
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
          .id('p3_comments_back')
          .width(40)
          .height(40)
          .padding(0)
          .borderRadius(20)
          .backgroundColor(HarmonyOSCapabilities.supportsImmersiveMaterial()
            ? Color.Transparent : $r('app.color.surface_background'))
          .accessibilityText(this.replying() ? '返回评论' : '返回详情')
          .onClick((): void => {
            this.onBack();
          })
      }
      .width(44)
      .height(44)
      .borderRadius(22)
      .clip(true)

      Text(this.replying() ? '回复' : '评论')
        .id('p3_comments_title')
        .textAlign(TextAlign.Center)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .layoutWeight(1)

      Blank().width(44)
    }
    .width('100%')
    .height(48)
    .padding({
      left: $r('app.float.p1_page_padding'),
      right: $r('app.float.p1_page_padding')
    })
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
