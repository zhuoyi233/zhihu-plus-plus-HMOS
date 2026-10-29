import { describe, expect, it } from '@ohos/hypium';
import { Answer, ContentDetailKind } from 'data';
import { LoadedAnswerDetail } from '../main/ets/pages/ContentDetailState';
import { ANSWER_PANE_MAX, AnswerPaneLayout, answerPaneIdentity } from '../main/ets/pages/AnswerPaneLayout';

function pane(id: string, generation: number): LoadedAnswerDetail {
  const answer: Answer = {
    id: id,
    questionId: '1',
    questionTitle: '问题',
    contentHtml: `<p>${id}</p>`,
    excerpt: '',
    url: '',
    voteupCount: 0,
    commentCount: 0,
    createdAt: 0,
    updatedAt: 0,
    author: {
      id: `author-${id}`,
      name: id,
      headline: '',
      followerCount: 0,
      isFollowing: false,
      isOrganization: false
    }
  };
  return { kind: ContentDetailKind.ANSWER, loadGeneration: generation, value: answer };
}

export default function answerPaneLayoutTest(): void {
  describe('answerPaneLayoutTest', () => {
    it('ordersPreviousCurrentNextAndRecordsDirections', 0, () => {
      const layout = new AnswerPaneLayout();
      const previous = pane('1', 11);
      const current = pane('2', 12);
      const next = pane('3', 13);
      const panes = layout.arrange(previous, current, next);
      expect(panes.length).assertEqual(3);
      expect(panes[0].value.id).assertEqual('1');
      expect(panes[1].value.id).assertEqual('2');
      expect(panes[2].value.id).assertEqual('3');
      expect(layout.directionOf(previous)).assertEqual(-1);
      expect(layout.directionOf(current)).assertEqual(0);
      expect(layout.directionOf(next)).assertEqual(1);
      expect(layout.size()).assertEqual(ANSWER_PANE_MAX);
    });

    it('keepsCurrentOnlyWhenNeighborsAreNotPrepared', 0, () => {
      const layout = new AnswerPaneLayout();
      const current = pane('2', 21);
      const panes = layout.arrange(undefined, current, undefined);
      expect(panes.length).assertEqual(1);
      expect(layout.directionOf(current)).assertEqual(0);
      // 未登记的正文不占位，页面按"非邻答"隐藏，避免与当前正文重叠。
      expect(layout.directionOf(pane('9', 99))).assertEqual(0);
      expect(layout.has(pane('9', 99))).assertFalse();
    });

    it('dropsDuplicateIdentityInsteadOfMountingTwice', 0, () => {
      const layout = new AnswerPaneLayout();
      const current = pane('2', 31);
      // 同一份正文不得同时出现在两个方向（会撞 ForEach 实例键）。
      const panes = layout.arrange(current, current, current);
      expect(panes.length).assertEqual(1);
      expect(layout.directionOf(current)).assertEqual(-1);
      expect(layout.size()).assertEqual(1);
    });

    it('treatsSameAnswerReloadAsDifferentDocument', 0, () => {
      const layout = new AnswerPaneLayout();
      const first = pane('2', 41);
      const reloaded = pane('2', 42);
      expect(answerPaneIdentity(first) === answerPaneIdentity(reloaded)).assertFalse();
      layout.arrange(undefined, first, undefined);
      expect(layout.has(reloaded)).assertFalse();
      layout.arrange(undefined, reloaded, undefined);
      expect(layout.has(first)).assertFalse();
      expect(layout.has(reloaded)).assertTrue();
    });

    it('mirrorsRolesAcrossAnswerRoundTripWithoutNewInstances', 0, () => {
      const layout = new AnswerPaneLayout();
      const answerA = pane('a', 51);
      const answerB = pane('b', 52);
      // A → 预挂载 B（下一答）
      let panes = layout.arrange(undefined, answerA, answerB);
      expect(panes.length).assertEqual(2);
      expect(layout.directionOf(answerB)).assertEqual(1);
      // 提交到 B：离开的 A 保留为上一答，仍是同一份正文
      panes = layout.arrange(answerA, answerB, undefined);
      expect(panes.length).assertEqual(2);
      expect(layout.directionOf(answerA)).assertEqual(-1);
      expect(layout.directionOf(answerB)).assertEqual(0);
      // 回到 A：B 转为下一答，A 转正
      panes = layout.arrange(undefined, answerA, answerB);
      expect(panes.length).assertEqual(2);
      expect(layout.directionOf(answerA)).assertEqual(0);
      expect(layout.directionOf(answerB)).assertEqual(1);
      expect(answerPaneIdentity(answerA)).assertEqual('a:51');
      expect(answerPaneIdentity(answerB)).assertEqual('b:52');
    });

    it('neverExceedsThreePanesAfterContinuousSwitching', 0, () => {
      const layout = new AnswerPaneLayout();
      const ids: string[] = ['1', '2', '3', '4', '5'];
      for (let index = 0; index < ids.length - 1; index++) {
        const current = pane(ids[index + 1], 60 + index);
        const previous = pane(ids[index], 60 + index + 100);
        const next = index + 2 < ids.length ? pane(ids[index + 2], 60 + index + 200) : undefined;
        const panes = layout.arrange(previous, current, next);
        expect(panes.length <= ANSWER_PANE_MAX).assertTrue();
        expect(layout.size() <= ANSWER_PANE_MAX).assertTrue();
      }
    });
  });
}
