import { DEFAULT_THEME_COLOR, onThemeColor } from 'data';

/** 评论头像尺寸（vp）：沿用原 CommentLayer.avatar() 的 36vp 圆形头像。 */
const COMMENT_AVATAR_SIZE: number = 36;
const COMMENT_AVATAR_RADIUS: number = COMMENT_AVATAR_SIZE / 2;

/**
 * 评论头像。加载期只显示中性圆形底座，图片解码完成后由同一个 Image 覆盖，
 * 避免整排主题色首字在网络头像就绪前闪现；只有无可用地址或加载失败才退回首字兜底。
 *
 * 约束（见 docs/comment-avatar-flicker-fix-plan.md 5.1）：
 * - avatarUrl 必须是调用方规范化后的地址，空串表示没有可信头像（不创建网络 Image）。
 * - Image 只要地址有效就持续挂载，不写 `if (loaded) Image(...)`，否则图片永远不会开始加载。
 * - 内部状态只随图源变化重置；父级点赞、输入、分页等普通更新不会让它重新显示占位或重试。
 */
@Component
export struct CommentAvatar {
  @Prop @Watch('onAvatarUrlChanged') avatarUrl: string = '';
  @Prop authorName: string = '';
  commentId: string = '';
  onTap: () => void = (): void => {
  };
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  /** 加载失败态：图源变化时清空，旧地址的失败结果不会带到新地址。 */
  @State private failed: boolean = false;

  onAvatarUrlChanged(): void {
    this.failed = false;
  }

  private hasImage(): boolean {
    return this.avatarUrl.length > 0;
  }

  /** 首字兜底：无可用地址，或地址加载失败。加载中不显示首字。 */
  private showInitial(): boolean {
    return !this.hasImage() || this.failed;
  }

  private initial(): string {
    const trimmed = this.authorName.trim();
    return trimmed.length > 0 ? trimmed.charAt(0) : '?';
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 底座：有图时用中性语义色（不暴露大面积主题色），无图/失败时才用主题色首字底。
      Column()
        .width(COMMENT_AVATAR_SIZE)
        .height(COMMENT_AVATAR_SIZE)
        .backgroundColor(this.showInitial() ? this.resolvedThemeColor : $r('app.color.control_background'))
      if (this.hasImage()) {
        Image(this.avatarUrl)
          .id(`comments_avatar_${this.commentId}`)
          .width(COMMENT_AVATAR_SIZE)
          .height(COMMENT_AVATAR_SIZE)
          .objectFit(ImageFit.Cover)
          // loadingStatus: 0 数据加载成功，1 解码成功。仅用于纠正误报的失败态，
          // 不替换 Image 节点、不叠加淡入动画。
          .onComplete((event) => {
            if (event !== undefined && event.loadingStatus === 1) {
              this.failed = false;
            }
          })
          .onError((): void => {
            this.failed = true;
          })
      }
      if (this.showInitial()) {
        Text(this.initial())
          .fontSize(16)
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .textAlign(TextAlign.Center)
          .width(COMMENT_AVATAR_SIZE)
          .height(COMMENT_AVATAR_SIZE)
      }
    }
    .width(COMMENT_AVATAR_SIZE)
    .height(COMMENT_AVATAR_SIZE)
    .borderRadius(COMMENT_AVATAR_RADIUS)
    .clip(true)
    .accessibilityText(this.authorName)
    .onClick((): void => this.onTap())
  }
}
