/**
 * 阅读与首页相关的两个 UI 组件（本轮新增）：
 * 1. HomeSearchBar：首页顶部搜索栏三档皮肤（默认蓝细边白底）；
 * 2. AnswerCommentComposer：回答底部独立评论框。
 *
 * 二者都不改动上游组件：搜索栏替换 AppShell 里的内联胶囊，评论框与 HotCommentSection 并列。
 */

import { DEFAULT_THEME_COLOR, decodeHomeSearchBarStyle, HomeSearchBarStyle, onThemeColor } from 'data';
import { TOP_BAR_GLASS_MATERIAL } from '../../common/style/TopBarGlass';
import { TOP_BAR_SEARCH_PILL_HEIGHT_VP } from '../../common/style/TopBarMaterial';
/** 知乎搜索框的品牌蓝：固定值，不跟随自定义主题色（对齐官方 App 的首页搜索栏）。 */
export const ZHIHU_SEARCH_BAR_BLUE: string = '#056DE8';

/** 搜索占位文案：三档样式共用，避免各自维护一份。 */
export const HOME_SEARCH_BAR_PLACEHOLDER: string = '搜索内容';

/**
 * 首页顶部搜索栏（一级页签的标题槽）。
 *
 * 三档皮肤（`homeSearchBarStyle`）：
 * - `outlined`（默认）：白底 + 1vp 品牌蓝细边 + 蓝色图标文字，知乎网页/官方 App 的搜索框观感；
 * - `filled`：品牌蓝实底白字；
 * - `glass`：沿用 #127 的沉浸光感胶囊（API 26 系统材质，低版本退回模糊兜底）。
 *
 * 轮廓恒为高度的一半圆角，三档只改表面，不改尺寸与位置，切换时不产生跳动。
 */
@Component
export struct HomeSearchBar {
  @StorageProp('homeSearchBarStyle') private homeSearchBarStyle: string = HomeSearchBarStyle.OUTLINED;
  onAction: () => void = (): void => {
  };

  private style(): HomeSearchBarStyle {
    return decodeHomeSearchBarStyle(this.homeSearchBarStyle);
  }

  private isGlass(): boolean {
    return this.style() === HomeSearchBarStyle.GLASS;
  }

  private isOutlined(): boolean {
    return this.style() === HomeSearchBarStyle.OUTLINED;
  }

  private surfaceColor(): ResourceColor {
    if (this.style() === HomeSearchBarStyle.FILLED) {
      return ZHIHU_SEARCH_BAR_BLUE;
    }
    return this.isOutlined() ? Color.White : Color.Transparent;
  }

  private contentColor(): ResourceColor {
    if (this.style() === HomeSearchBarStyle.FILLED) {
      return Color.White;
    }
    return this.isOutlined() ? ZHIHU_SEARCH_BAR_BLUE : $r('app.color.secondary_text');
  }

  private strokeOptions(): BorderOptions {
    const radius: number = TOP_BAR_SEARCH_PILL_HEIGHT_VP / 2;
    return this.isOutlined()
      ? { width: 1, color: ZHIHU_SEARCH_BAR_BLUE, radius: radius }
      : { width: 0, color: Color.Transparent, radius: radius };
  }

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: $r('app.float.spacing_small') }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(18)
          .fontColor([this.contentColor()])
        Text(HOME_SEARCH_BAR_PLACEHOLDER)
          .fontSize($r('app.float.body_font_size'))
          .fontColor(this.contentColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .id('home_titlebar_search')
    .width('100%')
    .height(TOP_BAR_SEARCH_PILL_HEIGHT_VP)
    .padding({ left: 14, right: 14, top: 0, bottom: 0 })
    .backgroundColor(this.surfaceColor())
    // 玻璃胶囊才走材质；实底与描边样式必须清掉材质，否则系统材质会盖住纯色底。
    .backgroundBlurStyle(this.isGlass()
      ? (TOP_BAR_GLASS_MATERIAL === undefined ? BlurStyle.COMPONENT_ULTRA_THIN : BlurStyle.NONE)
      : BlurStyle.NONE)
    .systemMaterial(this.isGlass() ? TOP_BAR_GLASS_MATERIAL : undefined)
    .borderRadius(TOP_BAR_SEARCH_PILL_HEIGHT_VP / 2)
    .border(this.strokeOptions())
    .clip(true)
    .accessibilityText('打开搜索')
    .onClick((): void => {
      this.onAction();
    })
  }
}


/**
 * 回答底部的独立评论框（对齐知乎网页版）：不离开正文即可写一条根评论。
 *
 * 与完整评论页互不影响：草稿、发送状态、错误提示都在组件内部；发送成功后由宿主刷新热评。
 * 抽成独立组件的意义是不碰上游 `HotCommentSection`——热评有没有内容、显示几条，
 * 与这个评论入口无关，两者可以各自出现或消失。
 */
@Component
export struct AnswerCommentComposer {
  /** 返回空串表示发送成功，否则为展示给用户的错误文案。 */
  onSubmit: (text: string) => Promise<string> = (_text: string): Promise<string> => Promise.resolve('');
  /** 宿主侧的发送状态：提交期间禁用输入与按钮，避免重复提交。 */
  @Prop submitting: boolean = false;
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;

  @State private draft: string = '';
  @State private message: string = '';

  private async submitDraft(): Promise<void> {
    const text: string = this.draft.trim();
    if (text.length === 0 || this.submitting) {
      return;
    }
    this.message = '';
    const failure: string = await this.onSubmit(text);
    if (failure.length === 0) {
      this.draft = '';
      this.message = '评论已发送';
    } else {
      this.message = failure;
    }
  }

  build() {
    Column({ space: $r('app.float.spacing_xsmall') }) {
      Row({ space: $r('app.float.spacing_small') }) {
        TextInput({ text: this.draft, placeholder: '写下你的评论…' })
          .id('content_detail_hot_comment_input')
          .layoutWeight(1)
          .height(40)
          .maxLength(1000)
          .enabled(!this.submitting)
          .onChange((value: string): void => {
            this.draft = value;
          })
          .onSubmit((): void => {
            void this.submitDraft();
          })
        Button(this.submitting ? '发送中…' : '发送')
          .id('content_detail_hot_comment_send')
          .height(36)
          .fontSize($r('app.float.secondary_font_size'))
          .backgroundColor(this.resolvedThemeColor)
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .enabled(this.draft.trim().length > 0 && !this.submitting)
          .onClick((): void => {
            void this.submitDraft();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.message.length > 0) {
        Text(this.message)
          .id('content_detail_hot_comment_message')
          .fontSize($r('app.float.caption_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }
    }
    .id('content_detail_hot_comment_composer')
    .width('100%')
    .padding($r('app.float.card_padding'))
    .borderRadius(16)
    .backgroundColor($r('app.color.surface_background'))
  }
}

