export enum ContentVoteState {
  NEUTRAL = 'neutral',
  UP = 'up',
  DOWN = 'down'
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

export interface Question {
  id: string;
  title: string;
  detailHtml: string;
  url: string;
  answerCount: number;
  commentCount: number;
  followerCount: number;
  createdAt: number;
  updatedAt: number;
  author?: UserProfile;
  /** 当前登录用户是否已关注该问题；详情接口未返回时缺省。 */
  isFollowing?: boolean;
}

export interface AnswerEndorsementDisplay {
  readonly text: string;
  /** 徽章背景色 token 组（如 GBK/GBL/GRD/GYL 前缀）；未知回退主题色。 */
  readonly backgroundColorGroup?: string;
  readonly backgroundColorAlpha: number;
  readonly textColorGroup?: string;
  readonly textColorAlpha: number;
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
  /** IP 属地（如「广东」）；接口未返回时缺省。 */
  ipInfo?: string;
}

export enum FeedTargetKind {
  QUESTION = 'question',
  ANSWER = 'answer',
  ARTICLE = 'article'
}

export interface FeedTargetSummary {
  kind: FeedTargetKind;
  id: string;
  title: string;
  excerpt: string;
  url: string;
  voteupCount: number;
  commentCount: number;
  author?: UserProfile;
  topicIds: Array<string>;
}

export interface FeedItem {
  id: string;
  verb: string;
  actionText?: string;
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
