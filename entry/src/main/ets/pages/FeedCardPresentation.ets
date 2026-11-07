import {
  CollectionContentItem,
  CollectionContentKind,
  FeedItem,
  FeedTargetKind
} from 'data';
import { ReadHistoryItem, readHistoryKindLabel, readHistoryTimeLabel } from './ReadHistoryState';

/**
 * 主页信息流卡片与收藏内容卡片共用的中立展示模型：由页面领域对象经纯适配函数生成，
 * 生成后按不可变值使用；组件以整体替换（重新赋值）的方式接收新值。
 * 用 class 承载（@Prop 仅支持基本类型与 class/Object），字段缺失即走对应降级布局。
 */
export class FeedCardPresentation {
  /** 标题：完整展示，不截断、不限行数。 */
  title: string = '';
  /** 摘要：空白串表示没有摘要，组件不绘制该 Text。 */
  excerpt: string = '';
  /** 作者姓名：undefined 表示没有作者行，不补“知乎用户”等占位。 */
  authorName?: string;
  /** 作者头像：undefined/空串表示只展示姓名，不保留头像槽。 */
  authorAvatarUrl?: string;
  /** 封面/缩略图：undefined/空串表示无图布局（受“显示信息流缩略图”开关二次控制）。 */
  thumbnailUrl?: string;
  /** 摘要下方的补充说明行（主页推荐理由/来源标注）；收藏来源不提供，不造兜底文案。 */
  supplementaryText?: string;
  /** 页脚统计文字，语义由来源决定（问题=回答数、想法=赞），组件不做二次解释。 */
  detailsText: string = '';
  /** 主体点击的无障碍描述，如“打开回答：标题”或“已屏蔽：原因”。 */
  accessibilityLabel: string = '';
  /** 质量屏蔽分支：组件改为渲染“已屏蔽 + 原因”，不再展示标题/作者/摘要/图片。 */
  isBlocked: boolean = false;
  blockedReason: string = '';
}

/**
 * 摘要行数策略（与主页共用）：带图时让右侧文字按左侧大图高度铺满，
 * 多列卡宽收窄后减少行数；无图时单列三行、多列两行。
 */
export function feedCardExcerptMaxLines(showsThumbnail: boolean, columns: number): number {
  if (showsThumbnail) {
    return columns > 2 ? 4 : 6;
  }
  return columns > 1 ? 2 : 3;
}

export function feedKindLabel(kind: FeedTargetKind): string {
  switch (kind) {
    case FeedTargetKind.QUESTION:
      return '问题';
    case FeedTargetKind.ANSWER:
      return '回答';
    case FeedTargetKind.ARTICLE:
      return '文章';
    case FeedTargetKind.VIDEO:
      return '视频';
  }
}

export function homeFeedActionLabel(item: FeedItem): string {
  // 对齐上游：LOCAL 模式显示本地推荐理由（reasonDisplay），其余模式显示来源标注
  // （移动端卡「手机版推荐」/ Web 卡 action_text），均缺失时兜底「推荐内容」。
  const reason = item.recommendationReason?.trim() ?? '';
  if (reason.length > 0) {
    return reason;
  }
  const actionText = item.actionText?.trim() ?? '';
  return actionText.length > 0 ? actionText : '推荐内容';
}

/** 对齐上游 details：类型标注（回答/文章等）与统计拼成页脚文字。 */
export function homeFeedDetailsLabel(item: FeedItem): string {
  if (item.target.mobileFooterText !== undefined) {
    // 移动卡片保留服务端页脚原文（已含“手机版推荐”来源标注），不重复拼接。
    return homeFeedFooterLabel(item);
  }
  // Web 卡对齐上游 detailsText：`回答 · N 赞同 · N 评论`。
  const stats = `${item.target.voteupCount ?? '—'} 赞同 · ${item.target.commentCount ?? '—'} 评论`;
  return `${feedKindLabel(item.target.kind)} · ${stats}`;
}

export function homeFeedFooterLabel(item: FeedItem): string {
  const mobileFooter = item.target.mobileFooterText;
  if (mobileFooter !== undefined) {
    return mobileFooter.trim().length > 0 ? `${mobileFooter} · 手机版推荐` : '手机版推荐';
  }
  return `${item.target.voteupCount ?? '—'} 赞同 · ${item.target.commentCount ?? '—'} 评论`;
}

/** 主页信息流卡展示适配：忠实搬运 homeFeedPage 卡片的取数与文案规则。 */
export function homeFeedCardPresentation(item: FeedItem): FeedCardPresentation {
  const presentation = new FeedCardPresentation();
  const blockedReason = item.target.qualityFilterReason ?? '';
  presentation.detailsText = homeFeedDetailsLabel(item);
  if (blockedReason.length > 0) {
    // 对齐上游 FeedDisplayItem（isFiltered）：屏蔽卡不携带标题/作者/摘要/图片，
    // 只显示“已屏蔽”与原因，页脚与菜单行保留。
    presentation.isBlocked = true;
    presentation.blockedReason = blockedReason;
    presentation.accessibilityLabel = `已屏蔽：${blockedReason}`;
    return presentation;
  }
  presentation.title = item.target.title;
  presentation.excerpt = item.target.excerpt;
  presentation.authorName = item.target.author?.name;
  presentation.authorAvatarUrl = item.target.author?.avatarUrl;
  presentation.thumbnailUrl = item.target.thumbnailUrl;
  const reason = item.recommendationReason?.trim() ?? '';
  // 与主页卡片一致：有推荐理由，或移动卡没有独立页脚但有来源标注时才显示补充行。
  if (reason.length > 0 ||
    (item.target.mobileFooterText === undefined && (item.actionText?.trim() ?? '').length > 0)) {
    presentation.supplementaryText = homeFeedActionLabel(item);
  }
  presentation.accessibilityLabel = `打开${feedKindLabel(item.target.kind)}：${item.target.title}`;
  return presentation;
}

/**
 * 历史记录卡展示适配（在线阅读历史与本地历史共用）：页脚沿用原顶栏元信息
 * “类型 · 时间”的语义；封面仅在在线响应提供 cover_image 时透传（本地记录无图），
 * 不补造推荐理由或作者头像（响应 header.icon 为固定类型图标，非头像）。
 */
export function readHistoryCardPresentation(item: ReadHistoryItem): FeedCardPresentation {
  const presentation = new FeedCardPresentation();
  const title = item.title.trim();
  presentation.title = title.length > 0 ? title : `${readHistoryKindLabel(item.kind)} #${item.id}`;
  presentation.excerpt = item.summary;
  presentation.authorName = item.authorName;
  presentation.thumbnailUrl = item.thumbnailUrl;
  presentation.detailsText = `${readHistoryKindLabel(item.kind)} · ${readHistoryTimeLabel(item.openedAt)}`;
  presentation.accessibilityLabel = `打开${readHistoryKindLabel(item.kind)}：${presentation.title}`;
  return presentation;
}

export function collectionContentKindLabel(kind: CollectionContentKind): string {
  switch (kind) {
    case CollectionContentKind.ANSWER:
      return '回答';
    case CollectionContentKind.ARTICLE:
      return '文章';
    case CollectionContentKind.QUESTION:
      return '问题';
    case CollectionContentKind.PIN:
      return '想法';
  }
}

/**
 * 收藏内容卡展示适配：页脚沿用收藏模型的 details（问题=回答数、想法=赞的语义保留），
 * 不生成推荐理由/推荐来源行；头像与封面使用响应中已核验的可选字段，缺失即降级。
 */
export function collectionFeedCardPresentation(item: CollectionContentItem): FeedCardPresentation {
  const presentation = new FeedCardPresentation();
  presentation.title = item.title;
  presentation.excerpt = item.excerpt;
  presentation.authorName = item.authorName;
  presentation.authorAvatarUrl = item.authorAvatarUrl;
  presentation.thumbnailUrl = item.thumbnailUrl;
  presentation.detailsText = item.details;
  presentation.accessibilityLabel = `打开${collectionContentKindLabel(item.kind)}：${item.title}`;
  return presentation;
}
