export enum ContentVoteState {
  NEUTRAL = 'neutral',
  UP = 'up',
  DOWN = 'down'
}

/** 作者认证徽章（对齐上游 OfficialBadge 的 display 精简模型，详情页作者名旁渲染）。 */
export interface AuthorBadge {
  readonly title: string;
  readonly description: string;
  readonly iconUrl: string;
}

export interface UserProfile {
  id: string;
  name: string;
  urlToken?: string;
  headline: string;
  avatarUrl?: string;
  followerCount: number;
  isFollowing: boolean;
  isOrganization: boolean;
  /** 作者认证徽章（badge_v2）；未返回时缺省。 */
  badge?: AuthorBadge;
}

export interface PeopleProfile extends UserProfile {
  followingCount: number;
  answerCount: number;
  articleCount: number;
  canonicalUrl: string;
}

export interface PinTopic {
  id: string;
  name: string;
}

export interface PinDetail {
  id: string;
  contentHtml: string;
  url: string;
  likeCount: number;
  commentCount: number;
  createdAt: number;
  updatedAt: number;
  author: UserProfile;
  topics: Array<PinTopic>;
}

export interface QuestionTopicSummary {
  id: string;
  name: string;
}

export interface Question {
  id: string;
  title: string;
  detailHtml: string;
  url: string;
  answerCount: number;
  commentCount: number;
  followerCount: number;
  /** 浏览数（详情 include 的 visit_count）；未返回时缺省。 */
  visitCount?: number;
  createdAt: number;
  updatedAt: number;
  author?: UserProfile;
  /** 当前登录用户是否已关注该问题；详情接口未返回时缺省。 */
  isFollowing?: boolean;
  /** 问题关联话题（详情 include 的 topics）；未返回时缺省。 */
  topics?: QuestionTopicSummary[];
}

export interface AnswerEndorsementDisplay {
  readonly text: string;
  /** 徽章背景色 token 组（如 GBK/GBL/GRD/GYL 前缀）；未知回退主题色。 */
  readonly backgroundColorGroup?: string;
  readonly backgroundColorAlpha: number;
  readonly textColorGroup?: string;
  readonly textColorAlpha: number;
  /** 前导图标 key（如 zhicon_icon_24_chat_bubble_hash_fill → # 图标）；未返回时缺省。 */
  readonly leadingIconKey?: string;
  /** 尾随图标 key（如 zhicon_icon_16_arrow_right / arrow_down → 箭头）；未返回时缺省。 */
  readonly trailingIconKey?: string;
}

export interface Answer {
  id: string;
  questionId: string;
  /** 回答所属问题标题；详情接口未返回时缺省。 */
  questionTitle?: string;
  contentHtml: string;
  excerpt: string;
  url: string;
  voteupCount: number;
  commentCount: number;
  createdAt: number;
  updatedAt: number;
  author?: UserProfile;
  /** 当前登录用户的投票关系；详情接口未返回时缺省。 */
  voteState?: ContentVoteState;
  /** 感谢数量；详情接口未返回时缺省。 */
  thanksCount?: number;
  /** 当前登录用户是否已感谢；详情接口未返回时缺省。 */
  isThanked?: boolean;
  /** 回答认可徽章流（对齐上游 Answer.endorsements 的 display 精简模型）。 */
  endorsements?: Array<AnswerEndorsementDisplay>;
  /** IP 属地（如「广东」）；接口未返回时缺省。 */
  ipInfo?: string;
  /** 正文他人划线（segment_infos）：渲染高亮与点赞。接口未返回时缺省。 */
  segmentInfos?: SegmentInfoParagraph[];
  /** 是否允许划线互动（0/1 兼容布尔）；接口未返回时缺省。 */
  allowSegmentInteraction?: boolean;
}

export interface Article {
  id: string;
  title: string;
  contentHtml: string;
  excerpt: string;
  url: string;
  voteupCount: number;
  commentCount: number;
  createdAt: number;
  updatedAt: number;
  author?: UserProfile;
  /** 当前登录用户的投票关系；详情接口未返回时缺省。 */
  voteState?: ContentVoteState;
  /** 感谢数量；详情接口未返回时缺省。 */
  thanksCount?: number;
  /** 当前登录用户是否已感谢；详情接口未返回时缺省。 */
  isThanked?: boolean;
  /** 文章认可徽章流（对齐上游 Article.endorsements）。 */
  endorsements?: Array<AnswerEndorsementDisplay>;
  /** 文章话题（详情 include 的 topics，信息头胶囊流展示）；未返回时缺省。 */
  topics?: QuestionTopicSummary[];
  /** IP 属地（如「广东」）；接口未返回时缺省。 */
  ipInfo?: string;
  /** 正文他人划线（segment_infos）：渲染高亮与点赞。接口未返回时缺省。 */
  segmentInfos?: SegmentInfoParagraph[];
  /** 是否允许划线互动（0/1 兼容布尔）；接口未返回时缺省。 */
  allowSegmentInteraction?: boolean;
}

/** 正文划线（segment_infos）的元信息：他人在句子上留下的高亮与点赞数据。 */
export interface SegmentInfoMeta {
  /** 划线唯一标识列表（点赞/评论时作为 seg_id 传参）。 */
  segIds: Array<string>;
  /** 当前用户是否已点赞该划线。 */
  isLike: boolean;
  /** 点赞总数。 */
  likeCount: number;
  /** 评论总数。 */
  commentCount: number;
  /** 当前用户自己的评论数。 */
  myCommentCount: number;
  /** 是否为整句跨段划线。 */
  isSpan: boolean;
}

/** 单段内的一个高亮区间。 */
export interface SegmentInfoMark {
  startIndex: number;
  endIndex: number;
  segInfo?: SegmentInfoMeta;
  masterSegInfo?: SegmentInfoMeta;
}

/** 一段正文（对应 HTML 的 p[data-pid] / li[data-pid]）的全部划线。 */
export interface SegmentInfoParagraph {
  pid: string;
  text: string;
  marks: Array<SegmentInfoMark>;
}

/**
 * 取划线的有效元信息：优先 segInfo，回退 masterSegInfo。
 * 对齐上游 SegmentInfoMark.effectiveSegInfo。
 */
export function effectiveSegmentMeta(mark: SegmentInfoMark): SegmentInfoMeta | undefined {
  return mark.segInfo !== undefined ? mark.segInfo : mark.masterSegInfo;
}

export enum FeedTargetKind {
  QUESTION = 'question',
  ANSWER = 'answer',
  ARTICLE = 'article',
  VIDEO = 'video'
}

export interface FeedTargetSummary {
  kind: FeedTargetKind;
  id: string;
  title: string;
  excerpt: string;
  url: string;
  voteupCount?: number;
  commentCount?: number;
  thumbnailUrl?: string;
  answerCount?: number;
  visitCount?: number;
  followerCount?: number;
  author?: UserProfile;
  /** 回答所属问题的提问者；仅使用上游真实字段，不按名称推断身份。 */
  questionAuthor?: UserProfile;
  /** Feed 响应中实际返回的作者质量信号；缺省表示上游未返回，不能按 0/未关注处理。 */
  authorFollowerCount?: number;
  authorIsFollowing?: boolean;
  topicIds: Array<string>;
  content?: string;
  isPaid?: boolean;
  qualityFilterReason?: string;
}

export interface FeedItem {
  id: string;
  verb: string;
  actionText?: string;
  /** 本地推荐（LOCAL 模式）理由标注，对齐上游 reasonDisplay；仅在本地排序页写入。 */
  recommendationReason?: string;
  createdAt: number;
  updatedAt: number;
  target: FeedTargetSummary;
}

export function feedItemIdentity(item: FeedItem): string {
  return `${item.target.kind}:${item.target.id}`;
}

export interface PageCursor {
  isEnd: boolean;
  isStart: boolean;
  next?: string;
  previous?: string;
  page: number;
  total: number;
}

export interface FeedPage {
  items: Array<FeedItem>;
  cursor: PageCursor;
}

export enum PeopleContentSection {
  ANSWERS = 'answers',
  ARTICLES = 'articles',
  ACTIVITIES = 'activities'
}

export enum PeopleContentKind {
  ANSWER = 'answer',
  ARTICLE = 'article',
  PIN = 'pin'
}

export interface PeopleContentItem {
  kind: PeopleContentKind;
  id: string;
  title: string;
  excerpt: string;
  voteupCount: number;
  commentCount: number;
  createdAt: number;
}

export interface PeopleContentPage {
  items: Array<PeopleContentItem>;
  cursor: PageCursor;
}

export function peopleContentIdentity(item: PeopleContentItem): string {
  return `${item.kind}:${item.id}`;
}
