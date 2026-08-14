import { ContentVoteState } from '../domain/DomainModels';

export interface ContentVoteResult {
  /** 服务端返回的最新赞同数；响应未提供时为 undefined，调用方沿用乐观值。 */
  readonly voteupCount?: number;
}

export interface ContentThankResult {
  /** 服务端返回的最新感谢数；响应未提供时为 undefined，调用方沿用乐观值。 */
  readonly thanksCount?: number;
  /** 服务端返回的最新感谢状态；响应未提供时为 undefined，调用方沿用乐观值。 */
  readonly thanked?: boolean;
}

export interface VoteRepository {
  /** 对回答投票：up/down/neutral（与上游 ArticleViewModel 一致，走 /voters 端点）。 */
  voteAnswer(id: string, state: ContentVoteState): Promise<ContentVoteResult>;
  /** 对文章投票：voting=1 表示赞同，否则 0（与上游 ArticleViewModel 一致）。 */
  voteArticle(id: string, state: ContentVoteState): Promise<ContentVoteResult>;
  /** 感谢/取消感谢回答。 */
  thankAnswer(id: string, thanked: boolean): Promise<ContentThankResult>;
  cancel(): void;
}
