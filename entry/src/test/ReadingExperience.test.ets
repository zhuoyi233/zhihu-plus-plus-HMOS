import { describe, expect, it } from '@ohos/hypium';
import {
  AnswerSwitchStyle,
  CommentPage,
  FeedItem,
  FeedPage,
  FeedRepository,
  FeedTargetKind,
  HomeSearchBarStyle,
  PageCursor,
  preloadCache,
  PreloadCacheTier,
  PreloadOptimizationMode,
  PRELOAD_CACHE_BUDGET_2GB,
  PRELOAD_CACHE_QUOTA_DEFAULT_BYTES,
  preloadAnswerKey,
  readPreloadJson,
  ScrollFeelPreset,
  writePreloadJson
} from 'data';
import {
  answerSwitchDurationMs,
  answerSwitchPaneOpacity,
  answerSwitchPaneScale,
  answerSwitchProgressRatio,
  answerSwitchTranslate
} from '../main/ets/pages/ReadingTweaks';
import { HomePendingFeed } from '../main/ets/pages/PreloadCenter';
import {
  answerSwitchStyleFromIndex,
  answerSwitchStyleIndex,
  answerSwitchStyleLabel,
  homeSearchBarStyleFromIndex,
  homeSearchBarStyleIndex,
  hotCommentCountFromIndex,
  hotCommentCountIndex,
  preloadOptimizationFromIndex,
  preloadOptimizationIndex,
  preloadOptimizationLabel,
  scrollFeelPresetFromIndex,
  scrollFeelSelectIndex
} from '../main/ets/pages/ReadingTweaks';
import { scrollFeelAdjustedOffset, scrollFeelProfile } from '../main/ets/pages/ReadingTweaks';

function pageCursor(): PageCursor {
  return { isEnd: true, isStart: true, page: 0, total: 0 };
}

function feedPage(count: number): FeedPage {
  const items: Array<FeedItem> = [];
  for (let index = 0; index < count; index += 1) {
    const id: string = `answer-${index}`;
    items.push({
      id: id,
      verb: 'answer',
      createdAt: 0,
      updatedAt: 0,
      target: { kind: FeedTargetKind.ANSWER, id: id, title: '', excerpt: '', url: '', topicIds: [] }
    });
  }
  return { items: items, cursor: pageCursor() };
}

/** 冲干净 pending 预取的微任务链：仓库返回已决议的 Promise，落到 then/finally 需要几跳。 */
function settlePendingFeed(): Promise<void> {
  return Promise.resolve().then((): void => {
  }).then((): void => {
  }).then((): void => {
  });
}

class StubFeedRepository implements FeedRepository {
  private readonly page: FeedPage;
  loadCount: number = 0;

  constructor(page: FeedPage) {
    this.page = page;
  }

  loadHomePage(_cursor?: string): Promise<FeedPage> {
    this.loadCount += 1;
    return Promise.resolve(this.page);
  }

  cancel(): void {
  }
}

/**
 * 阅读体验与预加载的纯策略验证。
 *
 * 覆盖：滚动增益曲线、切答过渡参数、首页双缓冲的提交判定、设置项下标换算、内存缓存的
 * 关闭/回填/作废与损坏数据自愈。真实手感、动画观感与预取命中率属设备回归，不在本文件。
 */
export default function readingExperienceTest(): void {
  describe('readingExperienceTest', () => {
    it('keepsSlowDragsPreciseAndSpeedsUpFastOnes', 0, () => {
      const standard = scrollFeelProfile(ScrollFeelPreset.SMOOTH);
      // 慢速一帧位移很小：增益贴近下限，微调只被轻微放大。
      const slow: number = scrollFeelAdjustedOffset(standard, -2);
      expect(Math.abs(slow)).assertLarger(1.9);
      expect(Math.abs(slow)).assertLess(2.2);
      // 快速拖动放大到接近上限，且方向不变。
      const fast: number = scrollFeelAdjustedOffset(standard, -40);
      expect(fast).assertLess(0);
      expect(Math.abs(fast)).assertLarger(40);
      // 跟随系统档不改写位移。
      expect(scrollFeelAdjustedOffset(scrollFeelProfile(ScrollFeelPreset.SYSTEM), -17)).assertEqual(-17);
      // 越激进的档位摩擦越小，精读档摩擦大于标准档。
      expect(scrollFeelProfile(ScrollFeelPreset.EXTREME).friction)
        .assertLess(scrollFeelProfile(ScrollFeelPreset.SWIFT).friction);
      expect(scrollFeelProfile(ScrollFeelPreset.STEADY).friction)
        .assertLarger(scrollFeelProfile(ScrollFeelPreset.SMOOTH).friction);
    });

    it('followsSwitchStyleWhenChoosingTravelScaleAndDuration', 0, () => {
      const slide = answerSwitchTranslate(AnswerSwitchStyle.SLIDE, false, 100);
      expect(Number(slide.y)).assertEqual(100);
      const fade = answerSwitchTranslate(AnswerSwitchStyle.FADE, true, 100);
      expect(Math.abs(Number(fade.x))).assertLess(100);
      expect(Number(fade.y)).assertEqual(0);
      const stack = answerSwitchTranslate(AnswerSwitchStyle.STACK, false, 100);
      expect(Math.abs(Number(stack.y))).assertLess(100);
      expect(answerSwitchDurationMs(AnswerSwitchStyle.SLIDE)).assertEqual(220);
      expect(answerSwitchDurationMs(AnswerSwitchStyle.STACK)).assertEqual(260);
      // 跟手进度限定在 0~1，跨度非法时按 1 兜底，不产生除零。
      expect(answerSwitchProgressRatio(50, 200)).assertEqual(0.25);
      expect(answerSwitchProgressRatio(500, 200)).assertEqual(1);
      expect(answerSwitchProgressRatio(-200, 0)).assertEqual(1);
      // 缩放只在盖卡片样式生效；淡入淡出才会交接透明度。
      expect(answerSwitchPaneScale(AnswerSwitchStyle.SLIDE, false, 0.5)).assertEqual(1);
      expect(answerSwitchPaneScale(AnswerSwitchStyle.STACK, false, 0)).assertEqual(0.92);
      expect(answerSwitchPaneScale(AnswerSwitchStyle.STACK, false, 1)).assertEqual(1);
      expect(answerSwitchPaneOpacity(AnswerSwitchStyle.SLIDE, true, false, 0.5)).assertEqual(1);
      expect(answerSwitchPaneOpacity(AnswerSwitchStyle.FADE, true, false, 1)).assertEqual(1);
      expect(answerSwitchPaneOpacity(AnswerSwitchStyle.FADE, true, true, 1)).assertEqual(0.1);
      expect(answerSwitchPaneOpacity(AnswerSwitchStyle.FADE, false, true, 0)).assertEqual(0);
    });

    it('commitsPreparedHomePageOnlyWhenItIsUsable', 0, () => {
      const pending = new HomePendingFeed();
      const repository = new StubFeedRepository(feedPage(4));
      const factory = (): FeedRepository => repository;
      // 没有 pending 时交回控制器原有刷新。
      expect(pending.take(0) === undefined).assertTrue();
      // 关闭预加载优化时完全不发请求。
      pending.prefetch(factory, false);
      expect(pending.take(10) === undefined).assertTrue();
      // 开启后请求在微任务里完成，随后可一次取走；取走即清空，不会重复提交。
      pending.prefetch(factory, true);
      return Promise.resolve().then((): Promise<void> => {
        return Promise.resolve().then((): void => {
          expect(repository.loadCount).assertEqual(1);
          const page: FeedPage | undefined = pending.take(10);
          expect(page !== undefined).assertTrue();
          expect(pending.take(10) === undefined).assertTrue();
        });
      });
    });

    it('rejectsPreparedPageThatIsSmallerThanWhatIsShown', 0, () => {
      const pending = new HomePendingFeed();
      pending.prefetch((): FeedRepository => new StubFeedRepository(feedPage(1)), true);
      return Promise.resolve().then((): Promise<void> => {
        return Promise.resolve().then((): void => {
          // 只有一条且当前列表明显更多：不提交，交回控制器刷新。
          expect(pending.take(8) === undefined).assertTrue();
        });
      });
    });

    it('refillsHomePendingRightAfterDiscard', 0, () => {
      const pending = new HomePendingFeed();
      let refills: number = 0;
      pending.attach((): void => {
        refills += 1;
      });
      pending.prefetch((): FeedRepository => new StubFeedRepository(feedPage(1)), true);
      return settlePendingFeed().then((): void => {
        // 丢弃（过期/小页）后必须立刻回补：少这一步，双缓冲会永久停在「没有下一页」。
        expect(pending.take(8) === undefined).assertTrue();
        expect(refills).assertEqual(1);
      });
    });

    it('backsOffWhenSmallPagesRepeat', 0, () => {
      const pending = new HomePendingFeed();
      const repository = new StubFeedRepository(feedPage(1));
      const factory = (): FeedRepository => repository;
      let refills: number = 0;
      pending.attach((): void => {
        refills += 1;
      });
      pending.prefetch(factory, true);
      return settlePendingFeed().then((): Promise<void> => {
        // 第 1 次小页：仍立刻补取，偶发小页不该把双缓冲打断。
        expect(pending.take(8) === undefined).assertTrue();
        expect(refills).assertEqual(1);
        pending.prefetch(factory, true);
        return settlePendingFeed();
      }).then((): void => {
        // 第 2 次连续小页：进入退避，既不再回补，也不在窗口内白打请求。
        expect(pending.take(8) === undefined).assertTrue();
        expect(refills).assertEqual(1);
        const loadsBeforeCooldown: number = repository.loadCount;
        pending.prefetch(factory, true);
        expect(repository.loadCount).assertEqual(loadsBeforeCooldown);
        pending.dispose();
      });
    });

    it('mapsReadingSettingsTheSameWayInBothDirections', 0, () => {
      expect(scrollFeelSelectIndex(ScrollFeelPreset.SWIFT)).assertEqual(3);
      expect(scrollFeelPresetFromIndex(3)).assertEqual(ScrollFeelPreset.SWIFT);
      expect(scrollFeelPresetFromIndex(99)).assertEqual(ScrollFeelPreset.SMOOTH);
      expect(answerSwitchStyleIndex(AnswerSwitchStyle.STACK)).assertEqual(2);
      expect(answerSwitchStyleFromIndex(2)).assertEqual(AnswerSwitchStyle.STACK);
      expect(answerSwitchStyleLabel(AnswerSwitchStyle.FADE)).assertEqual('淡入淡出');
      expect(homeSearchBarStyleIndex(HomeSearchBarStyle.OUTLINED)).assertEqual(0);
      expect(homeSearchBarStyleFromIndex(2)).assertEqual(HomeSearchBarStyle.FILLED);
      expect(hotCommentCountIndex(3)).assertEqual(2);
      expect(hotCommentCountFromIndex(2)).assertEqual(3);
      expect(preloadOptimizationIndex(PreloadOptimizationMode.ON)).assertEqual(1);
      expect(preloadOptimizationFromIndex(0)).assertEqual(PreloadOptimizationMode.OFF);
      expect(preloadOptimizationLabel(PreloadOptimizationMode.OFF)).assertEqual('关闭');
    });

    it('servesPreloadCacheOnlyWhenEnabledAndDropsCorruptEntries', 0, () => {
      // readPreloadJson/writePreloadJson 走全局缓存实例，这里直接用同一个实例验证语义。
      const cache = preloadCache();
      cache.setEnabled(false);
      cache.put('answer:1', 'payload', PreloadCacheTier.ANSWER);
      // 未启用：读写出入均为空，不占用配额。
      expect(cache.get('answer:1') === undefined).assertTrue();
      cache.setEnabled(true);
      expect(cache.get('answer:1') === undefined).assertTrue();
      cache.put('answer:1', 'payload', PreloadCacheTier.ANSWER);
      expect(cache.get('answer:1')).assertEqual('payload');
      // 损坏的 payload 自愈：读取返回 undefined 并作废该键。
      cache.put('answer:2', 'not-json', PreloadCacheTier.ANSWER);
      expect(readPreloadJson('answer:2') === undefined).assertTrue();
      expect(cache.has('answer:2')).assertFalse();
      writePreloadJson('answer:3', JSON.parse('{"id":"3"}') as Object, PreloadCacheTier.ANSWER);
      expect(readPreloadJson('answer:3') !== undefined).assertTrue();
      cache.invalidate('answer:1');
      expect(cache.has('answer:1')).assertFalse();
      // 关闭即整体清空。
      cache.setEnabled(false);
      expect(cache.has('answer:3')).assertFalse();
      expect(preloadAnswerKey('abc')).assertEqual('answer:abc');
    });

    it('repinsWithoutLosingEntriesAndUsesSmallerQuota', 0, () => {
      expect(PRELOAD_CACHE_QUOTA_DEFAULT_BYTES).assertEqual(512 * 1024 * 1024);
      const cache = preloadCache();
      cache.setQuota(PRELOAD_CACHE_BUDGET_2GB);
      expect(cache.quota()).assertEqual(PRELOAD_CACHE_BUDGET_2GB);
      cache.setQuota(PRELOAD_CACHE_QUOTA_DEFAULT_BYTES);
      cache.setEnabled(true);
      cache.put(preloadAnswerKey('a'), '{"id":"a"}', PreloadCacheTier.ANSWER);
      cache.put('comments:answer:a', '{"items":[]}', PreloadCacheTier.COMMENTS);
      // 换钉住窗口只会改变层级，不会删数据。
      cache.repin([preloadAnswerKey('a')]);
      expect(cache.get(preloadAnswerKey('a'))).assertEqual('{"id":"a"}');
      cache.repin([]);
      expect(cache.get(preloadAnswerKey('a')) !== undefined).assertTrue();
      cache.setEnabled(false);
    });

    it('roundTripsCachedCommentPage', 0, () => {
      const cache = preloadCache();
      cache.setEnabled(true);
      const page: CommentPage = { items: [], cursor: pageCursor() };
      writePreloadJson('comments:answer:1', page, PreloadCacheTier.COMMENTS);
      const restored = readPreloadJson('comments:answer:1') as CommentPage | undefined;
      expect(restored !== undefined).assertTrue();
      expect(restored?.items.length).assertEqual(0);
      cache.setEnabled(false);
    });
  });
}
