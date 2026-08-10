import { Answer, Article, Question } from '../domain/DomainModels';

export interface ContentRepository {
  getQuestion(id: string): Promise<Question>;
  getAnswer(id: string): Promise<Answer>;
  getArticle(id: string): Promise<Article>;
}
