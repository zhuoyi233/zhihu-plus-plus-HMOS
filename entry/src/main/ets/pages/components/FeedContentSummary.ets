import { FeedTargetKind, FeedTargetSummary } from 'data';

/** 信息流和问题回答卡片共享正文、作者及统计的排版。 */
@Component
export struct FeedContentSummary {
  target: FeedTargetSummary = {
    kind: FeedTargetKind.ANSWER, id: '', title: '', excerpt: '', url: '', voteupCount: 0, commentCount: 0,
    topicIds: []
  };
  showTitle: boolean = true;
  showStatistics: boolean = true;

  build() {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      if (this.showTitle && this.target.title.length > 0) {
        Text(this.target.title)
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      Row({ space: 8 }) {
        if ((this.target.author?.avatarUrl ?? '').length > 0) {
          Image(this.target.author?.avatarUrl)
            .width(24).height(24).borderRadius(12).objectFit(ImageFit.Cover)
        }
        Text(this.target.author?.name || '知乎用户')
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      }.width('100%')
      if (this.target.excerpt.trim().length > 0) {
        Text(this.target.excerpt)
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.primary_text'))
          .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      }
      if (this.showStatistics) {
        Text(`${this.target.voteupCount} 赞同 · ${this.target.commentCount} 评论`)
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
