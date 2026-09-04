import { ContentRepository, FeedTargetKind, FeedTargetSummary, Question } from 'data';

/** 热榜不提供浏览量；仅在卡片进入可见区域后补取问题统计。 */
@Component
export struct HotQuestionStatistics {
  @Prop @Watch('resetStatistics') target: FeedTargetSummary = {
    kind: FeedTargetKind.QUESTION, id: '', title: '', excerpt: '', url: '', voteupCount: 0,
    commentCount: 0, topicIds: []
  };
  repositoryFactory: () => ContentRepository | undefined = () => undefined;
  @State private question?: Question = undefined;
  private repository?: ContentRepository;
  private generation: number = 0;
  private loading: boolean = false;
  private visible: boolean = false;

  aboutToDisappear(): void {
    this.visible = false;
    this.cancelRequest();
  }

  private cancelRequest(): void {
    this.generation += 1;
    this.repository?.cancel();
    this.repository = undefined;
    this.loading = false;
  }

  private resetStatistics(): void {
    this.cancelRequest();
    this.question = undefined;
    if (this.visible) {
      this.loadStatistics();
    }
  }

  private async loadStatistics(): Promise<void> {
    if (this.loading || this.question !== undefined || this.target.kind !== FeedTargetKind.QUESTION) {
      return;
    }
    const repository = this.repositoryFactory();
    if (repository === undefined) {
      return;
    }
    this.repository = repository;
    this.loading = true;
    const generation = this.generation;
    try {
      const question = await repository.getQuestion(this.target.id);
      if (generation === this.generation) {
        this.question = question;
      }
    } catch (_error) {
      // 补查失败保留热榜已有统计，缺失浏览量显示占位符。
    } finally {
      if (generation === this.generation) {
        this.loading = false;
        this.repository = undefined;
      }
    }
  }

  build() {
    Flex({ wrap: FlexWrap.Wrap }) {
      Text(`${this.question?.answerCount ?? this.target.answerCount ?? '—'} 回答`)
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .margin({ right: 12, bottom: 4 })
      Text(`${this.question?.visitCount ?? this.target.visitCount ?? '—'} 浏览`)
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .margin({ right: 12, bottom: 4 })
      Text(`${this.question?.commentCount ?? this.target.commentCount} 评论`)
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .margin({ right: 12, bottom: 4 })
      Text(`${this.question?.followerCount ?? this.target.followerCount ?? '—'} 关注`)
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .margin({ right: 12, bottom: 4 })
    }
    .width('100%')
    .id(`p2_channel_hot_statistics_${this.target.id}`)
    // 使用正阈值，确保首次从完全不可见进入屏幕时触发补查。
    .onVisibleAreaChange([0.01], (visible: boolean): void => {
      this.visible = visible;
      if (visible) {
        this.loadStatistics();
      }
    })
  }
}
