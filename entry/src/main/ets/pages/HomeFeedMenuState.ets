import { ContentRepository, FeedItem, FeedTargetKind, QuestionTopicSummary, UserProfile } from 'data';
import { BlockingUserCandidate } from './BlockingActionState';

export enum HomeFeedMenuAction {
  BLOCK_USER = 'block_user',
  BLOCK_QUESTION_AUTHOR = 'block_question_author',
  BLOCK_TOPIC = 'block_topic',
  APPEARANCE = 'appearance',
  QUALITY_FILTER = 'quality_filter'
}

export interface HomeFeedMenuItem {
  action: HomeFeedMenuAction;
  label: string;
  topic?: QuestionTopicSummary;
}

/** 对齐 HomeScreen + FeedCardMenuBox；安卓 Lite 不提供关键词提取屏蔽入口。 */
export function homeFeedMenuItems(item: FeedItem, topics: Array<QuestionTopicSummary> = item.target.topics ?? []): Array<HomeFeedMenuItem> {
  const menu: Array<HomeFeedMenuItem> = [{ action: HomeFeedMenuAction.BLOCK_USER, label: '屏蔽用户' }];
  if (item.target.kind === FeedTargetKind.ANSWER || item.target.kind === FeedTargetKind.QUESTION) {
    menu.push({ action: HomeFeedMenuAction.BLOCK_QUESTION_AUTHOR, label: '屏蔽提问者' });
  }
  topics.forEach((topic: QuestionTopicSummary): void => {
    menu.push({ action: HomeFeedMenuAction.BLOCK_TOPIC, label: `屏蔽「${topic.name}」`, topic: topic });
  });
  menu.push({ action: HomeFeedMenuAction.APPEARANCE, label: '外观设置' });
  if ((item.target.qualityFilterReason ?? '').length > 0) {
    menu.push({ action: HomeFeedMenuAction.QUALITY_FILTER, label: '调整质量屏蔽' });
  }
  return menu;
}

/** 优先使用卡片真实作者；移动卡信息不足时按需查询详情，不能用回答作者代替提问者。 */
export async function resolveHomeFeedBlockUser(item: FeedItem, repository: ContentRepository | undefined,
  questionAuthor: boolean): Promise<BlockingUserCandidate | undefined> {
  const target = item.target;
  let author: UserProfile | undefined = undefined;
  if (questionAuthor) {
    if (target.kind !== FeedTargetKind.QUESTION && target.kind !== FeedTargetKind.ANSWER) {
      return undefined;
    }
    author = target.kind === FeedTargetKind.QUESTION ? target.author : target.questionAuthor;
    if (author === undefined && repository !== undefined) {
      let questionId = target.kind === FeedTargetKind.QUESTION ? target.id : target.questionId;
      if (questionId === undefined) {
        questionId = (await repository.getAnswer(target.id)).questionId;
      }
      author = (await repository.getQuestion(questionId)).author;
    }
  } else {
    author = target.author;
    if (author === undefined && repository !== undefined) {
      switch (target.kind) {
        case FeedTargetKind.ANSWER:
          author = (await repository.getAnswer(target.id)).author;
          break;
        case FeedTargetKind.QUESTION:
          author = (await repository.getQuestion(target.id)).author;
          break;
        case FeedTargetKind.ARTICLE:
          author = (await repository.getArticle(target.id)).author;
          break;
      }
    }
  }
  return author === undefined || author.id.trim().length === 0 || author.name.trim().length === 0
    ? undefined : { userId: author.id, userName: author.name };
}

export { resolveFeedTopics as resolveHomeFeedTopics } from 'data';
