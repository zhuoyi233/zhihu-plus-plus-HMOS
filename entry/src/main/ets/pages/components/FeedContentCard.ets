import { FEED_DIVIDER_ITEM_HORIZONTAL_PADDING_VP } from '../AppPageChrome';
import { feedCardExcerptMaxLines, FeedCardPresentation } from '../FeedCardPresentation';
import { FeedThumbnail } from './FeedThumbnail';

/**
 * “更多”按钮的图标内容（18fp ellipsis_circle、secondary_text）。
 * 页脚布局由 FeedContentCard 负责，按钮与 bindMenu 业务由页面槽位提供；
 * 两页按钮用同一 Builder 保证视觉规格一致。
 */
@Builder
export function feedCardMoreButtonContent() {
  SymbolGlyph($r('sys.symbol.ellipsis_circle'))
    .fontSize(18)
    .fontColor([$r('app.color.secondary_text')])
}

/** 未提供槽位时的空实现：页脚只渲染统计文字。 */
@Builder
function feedCardEmptyMoreSlot() {
}

/**
 * 主页信息流与收藏内容共用的单条内容卡片：外壳（Button + 卡片/分割线两种表面）、
 * 标题、作者行、图文摘要、页脚与“更多”槽位。展示模型经 FeedCardPresentation 适配
 * 后整体传入；组件不持有 repository/controller/session，也不识别页面来源
 * （测试 ID 与点击回调由页面显式传入）。
 */
@Component
export struct FeedContentCard {
  /** 展示模型：整体替换式不可变值；isBlocked 时组件改渲染屏蔽分支。 */
  @Prop presentation: FeedCardPresentation = new FeedCardPresentation();
  /** 当前最终列数（1~4）：决定摘要行数策略。 */
  @Prop columns: number = 1;
  /** 卡片外观：'card' 圆角表面 / 'divider' 底部分割线（与主页 feedCardStyle 同值域）。 */
  @Prop cardStyle: string = 'divider';
  /** “显示信息流缩略图”偏好：false 时按无图布局与行数渲染。 */
  @Prop showThumbnail: boolean = true;
  /** 根节点 / 页脚 / 屏蔽分支的测试 ID，由页面显式传入。 */
  @Prop cardTestId: string = '';
  @Prop footerTestId: string = '';
  @Prop blockedTestId: string = '';
  @Prop blockedRuleTestId: string = '';
  /** 主体点击回调（打开内容）。 */
  onOpen: () => void = (): void => {
  };
  /** 页脚“更多”按钮槽位：按钮与 bindMenu 业务由页面提供，组件只负责布局位置。 */
  @BuilderParam moreSlot: () => void = feedCardEmptyMoreSlot;

  private usesCardSurface(): boolean {
    return this.cardStyle === 'card';
  }

  /** 是否实际显示缩略图：偏好开启且展示模型带有效地址（FeedThumbnail 内再做 https 校验）。 */
  private hasThumbnail(): boolean {
    return this.showThumbnail && (this.presentation.thumbnailUrl ?? '').length > 0;
  }

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Column({ space: $r('app.float.spacing_xsmall') }) {
        if (this.presentation.isBlocked) {
          // 对齐上游 FeedDisplayItem（isFiltered）：标题显示“已屏蔽”，原因放摘要位置，
          // 标题/摘要/作者/来源与图片均不展示，页脚与菜单行保留。
          Text('已屏蔽')
            .id(this.blockedTestId)
            .fontSize($r('app.float.heading_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .width('100%')
          Text(this.presentation.blockedReason)
            .id(this.blockedRuleTestId)
            .fontSize($r('app.float.body_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
        } else {
          // 标题完整展示：不截断、不限行数，长问题换行后卡片高度自然增长（瀑布流不强行对齐行）。
          Text(this.presentation.title)
            .fontSize($r('app.float.heading_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .width('100%')

          if (this.presentation.authorName !== undefined) {
            Row({ space: $r('app.float.spacing_xsmall') }) {
              if ((this.presentation.authorAvatarUrl ?? '').length > 0) {
                Image(this.presentation.authorAvatarUrl)
                  .width(20)
                  .height(20)
                  .borderRadius(10)
                  .alt('用户头像')
              }
              Text(this.presentation.authorName ?? '')
                .fontSize($r('app.float.secondary_font_size'))
                .fontColor($r('app.color.secondary_text'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(VerticalAlign.Center)
          }

          // 图片/视频封面为左侧大图，摘要与补充说明排在右侧（对齐主页示意）。
          Row({ space: $r('app.float.spacing_small') }) {
            if (this.hasThumbnail()) {
              FeedThumbnail({ url: this.presentation.thumbnailUrl ?? '' })
                .width('42%')
                .aspectRatio(1)
                .constraintSize({ maxHeight: 150 })
                .borderRadius($r('app.float.spacing_small'))
            }
            Column({ space: $r('app.float.spacing_xsmall') }) {
              if (this.presentation.excerpt.trim().length > 0) {
                Text(this.presentation.excerpt)
                  .fontSize($r('app.float.body_font_size'))
                  .fontColor($r('app.color.secondary_text'))
                  // 多列卡宽收窄，摘要由三行收至两行；带图时按左侧大图高度铺满。
                  .maxLines(feedCardExcerptMaxLines(this.hasThumbnail(), this.columns))
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }
              if ((this.presentation.supplementaryText?.trim() ?? '').length > 0) {
                Text(this.presentation.supplementaryText ?? '')
                  .fontSize($r('app.float.secondary_font_size'))
                  .fontColor($r('app.color.secondary_text'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }
        // 对齐上游 FeedCardContent：页脚（details）行与右下角“更多”菜单同排。
        Row({ space: $r('app.float.spacing_small') }) {
          Text(this.presentation.detailsText)
            .id(this.footerTestId)
            .fontSize($r('app.float.secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          this.moreSlot()
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .id(this.cardTestId)
    .width('100%')
    // 分割线样式与正文页两侧留白对齐（容器 page_padding + 这里的 8vp = 20vp）；
    // 卡片样式保留 card_padding，卡面内需要内缩。
    .padding({
      left: this.usesCardSurface() ? $r('app.float.card_padding') : FEED_DIVIDER_ITEM_HORIZONTAL_PADDING_VP,
      right: this.usesCardSurface() ? $r('app.float.card_padding') : FEED_DIVIDER_ITEM_HORIZONTAL_PADDING_VP,
      top: $r('app.float.card_padding'),
      bottom: $r('app.float.card_padding')
    })
    .borderRadius(this.usesCardSurface() ? $r('app.float.card_radius') : 0)
    .backgroundColor(this.usesCardSurface() ? $r('app.color.surface_background') : Color.Transparent)
    // border 的 radius 优先级高于 borderRadius 属性（未指定时按 0 处理），
    // 卡片模式必须把圆角同步写进 border，否则背景圆角被重置成直角。
    .border({
      width: { bottom: !this.usesCardSurface() ? 1 : 0 },
      color: $r('app.color.divider_color'),
      radius: this.usesCardSurface() ? $r('app.float.card_radius') : 0
    })
    .accessibilityText(this.presentation.accessibilityLabel)
    .onClick((): void => this.onOpen())
  }
}
