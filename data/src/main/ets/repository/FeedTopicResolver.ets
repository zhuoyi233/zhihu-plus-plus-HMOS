import { FeedItem, FeedTargetKind, QuestionTopicSummary } from '../domain/DomainModels';
import { ContentRepository } from './ContentRepository';

/** 移动推荐只给出内容链接；打开菜单时查询真实话题，不从标题猜测或生成关键词。 */
export async function resolveFeedTopics(item: FeedItem, repository: ContentRepository | undefined):
  Promise<Array<QuestionTopicSummary>> {
  if ((item.target.topics?.length ?? 0) > 0) {
    return item.target.topics ?? [];
  }
  if (repository === undefined || item.target.kind === FeedTargetKind.VIDEO) {
    return [];
  }
  switch (item.target.kind) {
    case FeedTargetKind.ANSWER:
      const questionId = item.target.questionId ?? (await repository.getAnswer(item.target.id)).questionId;
      return (await repository.getQuestion(questionId)).topics ?? [];
    case FeedTargetKind.QUESTION:
      return (await repository.getQuestion(item.target.id)).topics ?? [];
    case FeedTargetKind.ARTICLE:
      return (await repository.getArticle(item.target.id)).topics ?? [];
    default:
      return [];
  }
}
