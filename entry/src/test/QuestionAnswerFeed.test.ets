import { describe, expect, it } from '@ohos/hypium';
import {
  buildQuestionAnswerFeedRequestUrl, ChannelContentItem, ChannelFeedItemKind, decodeQuestionAnswerFeedPage,
  FeedTargetKind, QuestionAnswerFeedPage, QuestionAnswerFeedRepository, QuestionAnswerSortOrder
} from 'data';
import { QuestionAnswersController, QuestionAnswersPhase, QuestionAnswersViewState } from '../main/ets/pages/QuestionAnswersState';
import { QuestionAnswerNavigator } from '../main/ets/pages/QuestionAnswerNavigator';

class FakeQuestionAnswerRepository implements QuestionAnswerFeedRepository {
  readonly pages: QuestionAnswerFeedPage[];
  calls: number = 0;
  constructor(pages: QuestionAnswerFeedPage[]) { this.pages = pages; }
  loadPage(_questionId: string, _order: QuestionAnswerSortOrder, _cursor?: string,
    _reset?: boolean): Promise<QuestionAnswerFeedPage> {
    const page = this.pages[Math.min(this.calls, this.pages.length - 1)];
    this.calls += 1;
    return Promise.resolve(page);
  }
  cancel(): void {}
}

function content(id: string): ChannelContentItem {
  return {
    kind: ChannelFeedItemKind.CONTENT,
    feedItem: {
      id: id, verb: '', createdAt: 1, updatedAt: 2,
      target: { kind: FeedTargetKind.ANSWER, id: id, title: '', excerpt: '摘要', url: '', voteupCount: 3,
        commentCount: 4, topicIds: [], author: { id: 'u', name: '作者', headline: '', followerCount: 0,
          isFollowing: false, isOrganization: false } }
    },
    topicIds: []
  };
}

export default function questionAnswerFeedTest(): void {
  describe('questionAnswerFeedTest', () => {
    it('buildsCanonicalSortUrlsAndRejectsCursorInjection', 0, () => {
      expect(buildQuestionAnswerFeedRequestUrl('123', QuestionAnswerSortOrder.UPDATED)).assertEqual(
        'https://www.zhihu.com/api/v4/questions/123/feeds?limit=20&order=updated');
      let rejected = false;
      try { buildQuestionAnswerFeedRequestUrl('123', QuestionAnswerSortOrder.DEFAULT, 'https://evil.test/'); }
      catch (_error) { rejected = true; }
      expect(rejected).assertTrue();
    });

    it('decodesQuestionFeedCardAndPaging', 0, () => {
      const page = decodeQuestionAnswerFeedPage('{"data":[{"type":"question_feed_card","target":{' +
        '"type":"answer","id":456,"excerpt":"正文","voteup_count":7,"comment_count":2,' +
        '"author":{"id":"u1","name":"用户","avatar_url":"https://picx.zhimg.com/a.jpg"}}}],' +
        '"paging":{"is_end":false,"next":"https://www.zhihu.com/api/v4/questions/123/feeds?limit=20&offset=20"}}');
      expect(page.items.length).assertEqual(1);
      expect((page.items[0] as ChannelContentItem).feedItem.target.id).assertEqual('456');
      expect(page.cursor.isEnd).assertFalse();
    });

    it('controllerSkipsEmptyFilteredPages', 0, async () => {
      const repository = new FakeQuestionAnswerRepository([
        { items: [], cursor: { isEnd: false, isStart: true, next: 'next', page: 1, total: 2 } },
        { items: [content('2')], cursor: { isEnd: true, isStart: false, page: 2, total: 2 } }
      ]);
      let state: QuestionAnswersViewState | undefined;
      const controller = new QuestionAnswersController(repository, '123', (next): void => { state = next; });
      controller.activate();
      await new Promise<void>((resolve): void => { setTimeout(resolve, 0); });
      expect(repository.calls).assertEqual(2);
      expect(state?.phase).assertEqual(QuestionAnswersPhase.READY);
      expect(state?.items.length).assertEqual(1);
    });

    it('navigatorLoadsNextPageAndKeepsPreviousItems', 0, async () => {
      const seed: QuestionAnswersViewState = {
        phase: QuestionAnswersPhase.READY, items: [content('1'), content('2')], loadingMore: false,
        canLoadMore: true, sortOrder: QuestionAnswerSortOrder.DEFAULT, errorMessage: '', requiresLogin: false,
        nextCursor: 'next'
      };
      const repository = new FakeQuestionAnswerRepository([
        { items: [content('3')], cursor: { isEnd: true, isStart: false, page: 2, total: 3 } }
      ]);
      const navigator = new QuestionAnswerNavigator('123', '2', seed, repository);
      expect(await navigator.move(-1)).assertEqual('1');
      expect(await navigator.move(1)).assertEqual('2');
      expect(await navigator.move(1)).assertEqual('3');
      expect(repository.calls).assertEqual(1);
      navigator.dispose();
    });

    it('navigatorSeedlessLocatesCurrentAndMovesToNext', 0, async () => {
      // 信息流直达：无种子，控制器自动拉取问题回答列表后回填当前索引。
      const repository = new FakeQuestionAnswerRepository([
        { items: [content('1'), content('2'), content('3')],
          cursor: { isEnd: false, isStart: true, next: 'next', page: 1, total: 3 } }
      ]);
      const navigator = new QuestionAnswerNavigator('123', '2', undefined, repository);
      expect(navigator.hasNext()).assertFalse();
      await new Promise<void>((resolve): void => { setTimeout(resolve, 0); });
      expect(navigator.currentId()).assertEqual('2');
      expect(navigator.hasNext()).assertTrue();
      const preview = navigator.nextAnswerPreview();
      expect(preview?.answerId).assertEqual('3');
      expect(preview?.authorName).assertEqual('作者');
      const previousPreview = navigator.previousAnswerPreview();
      expect(previousPreview?.answerId).assertEqual('1');
      expect(previousPreview?.authorName).assertEqual('作者');
      expect(await navigator.move(1)).assertEqual('3');
      expect(await navigator.move(-1)).assertEqual('2');
      navigator.dispose();
    });

    it('navigatorPreviousPreviewNoneOnFirstAnswer', 0, async () => {
      // 首答固定无上一答：预览接口返回 undefined，对应顶部过滑不生效。
      const seed: QuestionAnswersViewState = {
        phase: QuestionAnswersPhase.READY, items: [content('1'), content('2')], loadingMore: false,
        canLoadMore: false, sortOrder: QuestionAnswerSortOrder.DEFAULT, errorMessage: '', requiresLogin: false
      };
      const repository = new FakeQuestionAnswerRepository([
        { items: [], cursor: { isEnd: true, isStart: true, next: '', page: 1, total: 2 } }
      ]);
      const navigator = new QuestionAnswerNavigator('123', '2', seed, repository);
      const preview = navigator.previousAnswerPreview();
      expect(preview?.answerId).assertEqual('1');
      expect(preview?.authorName).assertEqual('作者');
      expect(await navigator.move(-1)).assertEqual('1');
      expect(navigator.hasPrevious()).assertFalse();
      expect(navigator.previousAnswerPreview()).assertUndefined();
      navigator.dispose();
    });

    it('navigatorSeedlessFallsBackToFirstWhenCurrentAbsent', 0, async () => {
      // 当前回答不在列表里（如被过滤）：首个非当前回答作为下一答。
      const repository = new FakeQuestionAnswerRepository([
        { items: [content('7'), content('8')],
          cursor: { isEnd: true, isStart: true, page: 1, total: 2 } }
      ]);
      const navigator = new QuestionAnswerNavigator('123', '99', undefined, repository);
      await new Promise<void>((resolve): void => { setTimeout(resolve, 0); });
      expect(navigator.hasNext()).assertTrue();
      const preview = navigator.nextAnswerPreview();
      expect(preview?.answerId).assertEqual('7');
      expect(await navigator.move(1)).assertEqual('7');
      expect(navigator.hasPrevious()).assertFalse();
      navigator.dispose();
    });
  });
}
