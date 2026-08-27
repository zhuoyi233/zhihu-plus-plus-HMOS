import { describe, expect, it } from '@ohos/hypium';
import {
  Answer,
  Article,
  ContentDetailKind,
  ContentRepository,
  HttpFailure,
  HttpFailureKind,
  Question
} from 'data';
import {
  ContentDetailController,
  ContentDetailPhase,
  contentDetailIdentity
} from '../main/ets/pages/ContentDetailState';
import {
  contentAuthorLine,
  contentContextTitle,
  contentEmptyMessage,
  contentHtml,
  contentStatistics,
  contentTitle
} from '../main/ets/pages/ContentDetailPages';
import { parseZhihuHtml, ReaderBlockKind, ReaderInlineKind } from 'reader';

interface PendingQuestion {
  resolve: (question: Question) => void;
  reject: (error: Error) => void;
}

class ControlledContentRepository implements ContentRepository {
  readonly pendingQuestions: Array<PendingQuestion> = [];
  cancelCount: number = 0;
  answer: Answer = answerFixture();
  article: Article = articleFixture();

  getQuestion(_id: string): Promise<Question> {
    return new Promise<Question>((resolve: (question: Question) => void,
      reject: (error: Error) => void): void => {
      this.pendingQuestions.push({ resolve: resolve, reject: reject });
    });
  }

  getAnswer(_id: string): Promise<Answer> {
    return Promise.resolve(this.answer);
  }

  getArticle(_id: string): Promise<Article> {
    return Promise.resolve(this.article);
  }

  cancel(): void {
    this.cancelCount += 1;
  }
}

class HttpFailingContentRepository implements ContentRepository {
  private readonly failure: HttpFailure;
  cancelCount: number = 0;

  constructor(failure: HttpFailure) {
    this.failure = failure;
  }

  async getQuestion(_id: string): Promise<Question> {
    throw this.failure;
  }

  async getAnswer(_id: string): Promise<Answer> {
    throw this.failure;
  }

  async getArticle(_id: string): Promise<Article> {
    throw this.failure;
  }

  cancel(): void {
    this.cancelCount += 1;
  }
}

export default function contentDetailStateTest(): void {
  describe('contentDetailStateTest', () => {
    it('loadsEveryKindAndMapsSemanticHeaderFields', 0, async () => {
      const repository = new ControlledContentRepository();
      const controller = new ContentDetailController(repository);
      controller.activate();

      await controller.load(ContentDetailKind.ANSWER, '2');
      const answer = controller.snapshot().content;
      expect(answer?.kind).assertEqual(ContentDetailKind.ANSWER);
      if (answer !== undefined) {
        expect(contentTitle(answer)).assertEqual('回答');
        expect(contentContextTitle(answer)).assertEqual('回答所属问题');
        expect(contentAuthorLine(answer)).assertEqual('回答者 · 回答签名');
        expect(contentStatistics(answer)).assertEqual('10 赞同 · 2 条评论');
        expect(contentHtml(answer)).assertEqual('<p>回答正文</p>');
        expect(contentEmptyMessage(answer)).assertEqual('摘要');
      }

      await controller.load(ContentDetailKind.ARTICLE, '3');
      const article = controller.snapshot().content;
      expect(article?.kind).assertEqual(ContentDetailKind.ARTICLE);
      if (article !== undefined) {
        expect(contentTitle(article)).assertEqual('完整文章标题');
        expect(contentContextTitle(article)).assertEqual('完整文章标题');
        expect(contentStatistics(article)).assertEqual('20 赞同 · 4 条评论');
      }
    });

    it('publishesLoadingThenReadyAndReturnsDefensiveCopies', 0, async () => {
      const repository = new ControlledContentRepository();
      const controller = new ContentDetailController(repository);
      controller.activate();
      const loading = controller.load(ContentDetailKind.QUESTION, '1');
      expect(controller.snapshot().phase).assertEqual(ContentDetailPhase.LOADING);
      repository.pendingQuestions[0].resolve(questionFixture());
      await loading;

      const first = controller.snapshot();
      expect(first.phase).assertEqual(ContentDetailPhase.READY);
      if (first.content !== undefined && first.content.value.author !== undefined) {
        first.content.value.author.name = '被外部篡改';
      }
      expect(controller.snapshot().content?.value.author?.name).assertEqual('提问者');
    });

    it('ignoresOldResultAfterDestinationChanges', 0, async () => {
      const repository = new ControlledContentRepository();
      const controller = new ContentDetailController(repository);
      controller.activate();
      const old = controller.load(ContentDetailKind.QUESTION, '1');
      await controller.load(ContentDetailKind.ARTICLE, '3');
      repository.pendingQuestions[0].resolve(questionFixture());
      await old;

      expect(controller.snapshot().content?.kind).assertEqual(ContentDetailKind.ARTICLE);
      expect(repository.cancelCount).assertEqual(1);
    });

    it('cancelsOnLeaveAndBlocksLateWriteBack', 0, async () => {
      const repository = new ControlledContentRepository();
      const controller = new ContentDetailController(repository);
      controller.activate();
      const pending = controller.load(ContentDetailKind.QUESTION, '1');
      controller.deactivate();
      repository.pendingQuestions[0].resolve(questionFixture());
      await pending;

      expect(repository.cancelCount).assertEqual(1);
      expect(controller.snapshot().phase).assertEqual(ContentDetailPhase.LOADING);
    });

    it('usesRecoverableGenericErrorWithoutLeakingRawDetails', 0, async () => {
      const repository = new ControlledContentRepository();
      const controller = new ContentDetailController(repository);
      controller.activate();
      const pending = controller.load(ContentDetailKind.QUESTION, '1');
      repository.pendingQuestions[0].reject(new Error('Cookie z_c0=secret response body'));
      await pending;

      const state = controller.snapshot();
      expect(state.phase).assertEqual(ContentDetailPhase.ERROR);
      expect(state.errorMessage).assertEqual('内容加载失败，请稍后重试');
      expect(state.errorMessage?.includes('secret')).assertFalse();
      expect(state.requiresLogin).assertFalse();
    });

    it('publishesLoginActionForAuthenticationFailure', 0, async () => {
      const repository = new HttpFailingContentRepository(
        new HttpFailure(HttpFailureKind.AUTHENTICATION, 401)
      );
      const controller = new ContentDetailController(repository);
      controller.activate();
      await controller.load(ContentDetailKind.QUESTION, '1');

      const state = controller.snapshot();
      expect(state.phase).assertEqual(ContentDetailPhase.ERROR);
      expect(state.requiresLogin).assertTrue();
      expect(state.errorMessage).assertEqual('登录状态不可用，请重新登录后重试');

      const noStatusRepository = new HttpFailingContentRepository(
        new HttpFailure(HttpFailureKind.AUTHENTICATION)
      );
      const noStatusController = new ContentDetailController(noStatusRepository);
      noStatusController.activate();
      await noStatusController.load(ContentDetailKind.QUESTION, '1');
      expect(noStatusController.snapshot().requiresLogin).assertTrue();
      expect(noStatusController.snapshot().errorMessage).assertEqual('登录状态不可用，请重新登录后重试');
    });

    it('keepsForbiddenResponseOnRetryPathWithoutLoginCta', 0, async () => {
      const repository = new HttpFailingContentRepository(
        new HttpFailure(HttpFailureKind.AUTHENTICATION, 403)
      );
      const controller = new ContentDetailController(repository);
      controller.activate();
      await controller.load(ContentDetailKind.QUESTION, '1');

      const state = controller.snapshot();
      expect(state.phase).assertEqual(ContentDetailPhase.ERROR);
      expect(state.requiresLogin).assertFalse();
      expect(state.errorMessage).assertEqual('内容请求被拒绝，可能需要完成知乎风控验证');
    });

    it('usesStableOpenedIdentityForAllSupportedKinds', 0, () => {
      expect(contentDetailIdentity(ContentDetailKind.QUESTION, '1')).assertEqual('question:1');
      expect(contentDetailIdentity(ContentDetailKind.ANSWER, '2')).assertEqual('answer:2');
      expect(contentDetailIdentity(ContentDetailKind.ARTICLE, '3')).assertEqual('article:3');
    });

    it('feedsHtmlIntoNativeReaderAndKeepsFormulaNodeFallback', 0, () => {
      const blocks = parseZhihuHtml('<p>等式 <img eeimg="1" alt="x+y" src="https://www.zhihu.com/equation?' +
        'tex=x%2By"></p><figure><img data-actualsrc="https://pic1.zhimg.com/image.png" alt="示意图"></figure>');
      expect(blocks.length).assertEqual(2);
      expect(blocks[0].inlineRuns[1].kind).assertEqual(ReaderInlineKind.FORMULA);
      expect(blocks[0].inlineRuns[1].text).assertEqual('x+y');
      expect(blocks[1].kind).assertEqual(ReaderBlockKind.IMAGE);

      const fallback = parseZhihuHtml('<p>恶意公式 <img eeimg="1" alt="secret" ' +
        'src="https://evil.example/formula.svg"></p>');
      expect(fallback[0].inlineRuns.length).assertEqual(0);
      expect(fallback[0].text.includes('secret')).assertTrue();
    });
  });
}

function questionFixture(): Question {
  return {
    id: '1',
    title: '完整问题标题',
    detailHtml: '<p>问题补充</p>',
    url: 'https://www.zhihu.com/question/1',
    answerCount: 3,
    commentCount: 4,
    followerCount: 5,
    createdAt: 1,
    updatedAt: 2,
    author: {
      id: 'author-q',
      name: '提问者',
      headline: '提问签名',
      followerCount: 1,
      isFollowing: false,
      isOrganization: false
    }
  };
}

function answerFixture(): Answer {
  return {
    id: '2',
    questionId: '1',
    questionTitle: '回答所属问题',
    contentHtml: '<p>回答正文</p>',
    excerpt: '摘要',
    url: 'https://www.zhihu.com/question/1/answer/2',
    voteupCount: 10,
    commentCount: 2,
    createdAt: 1,
    updatedAt: 2,
    author: {
      id: 'author-a',
      name: '回答者',
      headline: '回答签名',
      followerCount: 1,
      isFollowing: false,
      isOrganization: false
    }
  };
}

function articleFixture(): Article {
  return {
    id: '3',
    title: '完整文章标题',
    contentHtml: '<p>文章正文</p>',
    excerpt: '摘要',
    url: 'https://zhuanlan.zhihu.com/p/3',
    voteupCount: 20,
    commentCount: 4,
    createdAt: 1,
    updatedAt: 2,
    author: {
      id: 'author-z',
      name: '文章作者',
      headline: '',
      followerCount: 1,
      isFollowing: false,
      isOrganization: false
    }
  };
}
