import { Answer, Article, Question } from '../domain/DomainModels';
import {
  decodeAnswerDetail,
  decodeArticleDetail,
  decodeQuestionDetail
} from '../domain/ContentDetailDecoder';
import { ZhihuHttpClient, ZhihuHttpResponse } from '../network/ZhihuHttpClient';
import { ContentDetailKind, ContentRepository } from './ContentRepository';

export const QUESTION_DETAIL_INCLUDE =
  'read_count,visit_count,answer_count,voteup_count,comment_count,follower_count,detail,excerpt,author,' +
    'relationship.is_following,topics';
export const ANSWER_DETAIL_INCLUDE =
  '.settings,content,editable_content,paid_info,can_comment,excerpt,thanks_count,voteup_count,comment_count,' +
    'visited_count,attachment,reaction,ip_info,pagination_info,endorsements,question.topics,' +
    'reaction.relation.voting,author.badge_v2,settings.table_of_contents.enabled';
export const ARTICLE_DETAIL_INCLUDE =
  'content,topics,paid_info,can_comment,excerpt,thanks_count,voteup_count,comment_count,visited_count,' +
    'relationship,ip_info,relationship.vote,author.badge_v2';

export enum ContentRepositoryFailureKind {
  INVALID_ID = 'invalid_id',
  CANCELLED = 'cancelled'
}

export class ContentRepositoryFailure extends Error {
  readonly kind: ContentRepositoryFailureKind;

  constructor(kind: ContentRepositoryFailureKind) {
    super(kind === ContentRepositoryFailureKind.INVALID_ID ? '内容 ID 无效' : '内容详情请求已取消');
    this.name = 'ContentRepositoryFailure';
    this.kind = kind;
  }
}

export function normalizeContentId(id: string): string {
  if (!/^[1-9][0-9]{0,29}$/.test(id)) {
    throw new ContentRepositoryFailure(ContentRepositoryFailureKind.INVALID_ID);
  }
  return id;
}

export function buildContentDetailUrl(kind: ContentDetailKind, id: string): string {
  const normalizedId = normalizeContentId(id);
  let collection: string;
  let include: string;
  switch (kind) {
    case ContentDetailKind.QUESTION:
      collection = 'questions';
      include = QUESTION_DETAIL_INCLUDE;
      break;
    case ContentDetailKind.ANSWER:
      collection = 'answers';
      include = ANSWER_DETAIL_INCLUDE;
      break;
    case ContentDetailKind.ARTICLE:
      collection = 'articles';
      include = ARTICLE_DETAIL_INCLUDE;
      break;
  }
  return `https://www.zhihu.com/api/v4/${collection}/${normalizedId}?include=${encodeURIComponent(include)}`;
}

export class DefaultContentRepository implements ContentRepository {
  private readonly httpClient: ZhihuHttpClient;
  private generation: number = 0;

  constructor(httpClient: ZhihuHttpClient) {
    this.httpClient = httpClient;
  }

  cancel(): void {
    this.generation += 1;
    this.httpClient.cancel();
  }

  async getQuestion(id: string): Promise<Question> {
    const normalizedId = normalizeContentId(id);
    const response = await this.fetch(ContentDetailKind.QUESTION, normalizedId);
    return decodeQuestionDetail(response.body, normalizedId);
  }

  async getAnswer(id: string): Promise<Answer> {
    const normalizedId = normalizeContentId(id);
    const response = await this.fetch(ContentDetailKind.ANSWER, normalizedId);
    return decodeAnswerDetail(response.body, normalizedId);
  }

  async getArticle(id: string): Promise<Article> {
    const normalizedId = normalizeContentId(id);
    const response = await this.fetch(ContentDetailKind.ARTICLE, normalizedId);
    return decodeArticleDetail(response.body, normalizedId);
  }

  private async fetch(kind: ContentDetailKind, id: string): Promise<ZhihuHttpResponse> {
    const requestGeneration = this.generation;
    const response = await this.httpClient.execute({
      url: buildContentDetailUrl(kind, id),
      accept: 'application/json',
      useSession: true,
      signWithZse: true
    });
    if (requestGeneration !== this.generation) {
      throw new ContentRepositoryFailure(ContentRepositoryFailureKind.CANCELLED);
    }
    return response;
  }
}
