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
}

export interface Answer {
  id: string;
  questionId: string;
  contentHtml: string;
  excerpt: string;
  url: string;
  voteupCount: number;
  commentCount: number;
  createdAt: number;
  updatedAt: number;
  author?: UserProfile;
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
