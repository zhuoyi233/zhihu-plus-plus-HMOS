import { P1Destination, P1DestinationName } from 'core';
import {
  CommentContentKind,
  CommentItem,
  CommentRepository,
  CommentSortOrder,
  LoginSessionGateway
} from 'data';
import {
  CommentController,
  commentContentKind,
  CommentPhase,
  CommentViewState
} from './CommentState';

const COMMENT_EXPANDED_IDS_LIMIT = 200;

/**
 * 评论弹层组件：常驻详情页组合树内（以 visibility 切换显隐），
 * 避免关闭弹层时销毁内部状态——与上游 CommentScreenComponent
 * 「不要在 if 条件中使用，否则内部状态丢失」的约定一致。
 * 草稿由弹层外的页面持有（跨关闭保留），本组件只读草稿并回调修改。
 */
@Component
export struct CommentLayer {
  contentType: string = 'answer';
  contentId: string = '';
  repository: CommentRepository | undefined = undefined;
  session: LoginSessionGateway | undefined = undefined;
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {
  };
  @Prop @Watch('onShowCommentsChange') showComments: boolean = false;
  rootDraft: string = '';
  replyDraft: string = '';
  onRootDraftChange: (value: string) => void = (_value: string): void => {
  };
  onReplyDraftChange: (value: string) => void = (_value: string): void => {
  };
  onDismiss: () => void = (): void => {
  };
  @State private phase: CommentPhase = CommentPhase.IDLE;
  @State private items: Array<CommentItem> = [];
  @State private loadingMore: boolean = false;
  @State private canLoadMore: boolean = false;
  @State private requiresLogin: boolean = false;
  @State private errorMessage: string = '';
  @State private sortOrder: CommentSortOrder = CommentSortOrder.SCORE;
  @State private activeRoot?: CommentItem = undefined;
  @State private replyTarget?: CommentItem = undefined;
  @State private submitting: boolean = false;
  @State private likeBusy: boolean = false;
  @State private deleting: boolean = false;
  @State private actionMessage: string = '';
  @State private actionRequiresLogin: boolean = false;
  @State private expandedRootIds: Array<string> = [];
  private controller?: CommentController;
  private rootScroller: Scroller = new Scroller();
  private childScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    const repository = this.repository;
    const session = this.session;
    if (repository === undefined || session === undefined) {
      this.phase = CommentPhase.ERROR;
      this.errorMessage = '评论数据源未配置';
      return;
    }
    const kind = commentContentKind(this.contentType);
    if (kind === undefined) {
      this.phase = CommentPhase.ERROR;
      this.errorMessage = '评论内容类型无效';
      return;
    }
    this.controller = new CommentController(
      kind,
      this.contentId,
      repository,
      session,
      (state: CommentViewState): void => this.applyState(state)
    );
    this.controller.activate();
  }

  aboutToDisappear(): void {
    this.controller?.deactivate();
    this.controller = undefined;
  }

  onShowCommentsChange(): void {
    if (this.showComments && this.phase === CommentPhase.IDLE) {
      this.controller?.loadInitial();
    }
  }

  build() {
    Stack() {
      Column() {
        Blank()
          .onClick((): void => {
            this.onDismiss();
          })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#66000000')

      Column() {
        this.sheetHeader()
        this.sheetBody()
        if (this.phase === CommentPhase.READY || this.phase === CommentPhase.EMPTY) {
          this.inputBar()
        }
      }
      .width('100%')
      .height('86%')
      .align(Alignment.Bottom)
      .backgroundColor($r('app.color.surface_background'))
      .borderRadius({ topLeft: $r('app.float.p1_card_radius'), topRight: $r('app.float.p1_card_radius') })
    }
    .width('100%')
    .height('100%')
    .visibility(this.showComments ? Visibility.Visible : Visibility.None)
  }

  @Builder
  private sheetHeader() {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        if (this.activeRoot !== undefined) {
          Button('← 返回')
            .id('p3_comments_back')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .onClick((): void => {
              this.controller?.closeChildComments();
            })
          Text('回复')
            .fontSize($r('app.float.p1_heading_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .layoutWeight(1)
        } else {
          Text('评论')
            .fontSize($r('app.float.p1_heading_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .layoutWeight(1)
          if (this.phase === CommentPhase.READY || this.phase === CommentPhase.EMPTY) {
            this.sortChip(CommentSortOrder.SCORE, '最热', 'p3_comments_sort_score')
            this.sortChip(CommentSortOrder.TIME, '最新', 'p3_comments_sort_time')
          }
        }
        Button('✕')
          .id('p3_comments_close')
          .fontSize($r('app.float.p1_body_font_size'))
          .onClick((): void => {
            this.onDismiss();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
  }

  @Builder
  private sortChip(order: CommentSortOrder, label: string, testId: string) {
    Button(label, { type: ButtonType.Capsule })
      .id(testId)
      .fontSize($r('app.float.p1_secondary_font_size'))
      .fontColor(this.sortOrder === order ? $r('app.color.on_brand') : $r('app.color.primary_text'))
      .backgroundColor(this.sortOrder === order
        ? $r('app.color.brand_primary')
        : $r('app.color.control_background'))
      .onClick((): void => {
        this.controller?.changeSortOrder(order);
      })
  }

  @Builder
  private sheetBody() {
    if (this.phase === CommentPhase.IDLE || this.phase === CommentPhase.LOADING) {
      this.statusPanel('正在加载评论…', false)
    } else if (this.phase === CommentPhase.ERROR) {
      this.statusPanel(this.errorMessage.length > 0 ? this.errorMessage : '评论加载失败', true)
    } else {
      Column() {
        if (this.errorMessage.length > 0) {
          Row({ space: $r('app.float.p1_spacing_small') }) {
            Text(this.errorMessage)
              .fontSize($r('app.float.p1_secondary_font_size'))
              .fontColor($r('app.color.error_text'))
              .layoutWeight(1)
            if (this.requiresLogin) {
              Button('去登录')
                .id('p3_comments_login')
                .fontSize($r('app.float.p1_secondary_font_size'))
                .onClick((): void => this.navigate({ name: P1DestinationName.LOGIN }))
            } else {
              Button('重试')
                .id('p3_comments_retry_more')
                .fontSize($r('app.float.p1_secondary_font_size'))
                .onClick(() => this.controller?.retry())
            }
          }
          .width('100%')
          .padding($r('app.float.p1_spacing_small'))
          .borderRadius($r('app.float.p1_card_radius'))
          .backgroundColor($r('app.color.surface_background'))
        }

        if (this.phase === CommentPhase.EMPTY) {
          this.statusPanel(this.activeRoot === undefined ? '暂无评论，来发表第一条吧' : '暂无回复', false)
        } else {
          if (this.activeRoot !== undefined) {
            List({ space: 10, scroller: this.childScroller }) {
              ListItem() {
                this.pinnedRootCard(this.activeRoot)
              }
              ForEach(this.items, (comment: CommentItem) => {
                ListItem() {
                  this.commentCard(comment, false)
                }
              }, (comment: CommentItem): string => `child_${comment.id}`)
              if (this.loadingMore || this.canLoadMore) {
                ListItem() {
                  Button(this.loadingMore ? '正在加载更多…' : '加载更多')
                    .id('p3_comments_children_load_more')
                    .width('100%')
                    .fontSize($r('app.float.p1_secondary_font_size'))
                    .enabled(!this.loadingMore && !this.submitting && !this.deleting)
                    .onClick(() => this.controller?.loadMore())
                }
              }
            }
            .id('p3_comments_children_list')
            .width('100%')
            .layoutWeight(1)
            .edgeEffect(EdgeEffect.Spring)
            .onReachEnd(() => this.controller?.loadMore())
          } else {
            List({ space: 10, scroller: this.rootScroller }) {
              ForEach(this.items, (comment: CommentItem) => {
                ListItem() {
                  this.commentCard(comment, true)
                }
              }, (comment: CommentItem): string => `root_${comment.id}`)
              if (this.loadingMore || this.canLoadMore) {
                ListItem() {
                  Button(this.loadingMore ? '正在加载更多…' : '加载更多')
                    .id('p3_comments_root_load_more')
                    .width('100%')
                    .fontSize($r('app.float.p1_secondary_font_size'))
                    .enabled(!this.loadingMore && !this.submitting && !this.deleting)
                    .onClick(() => this.controller?.loadMore())
                }
              }
            }
            .id('p3_comments_root_list')
            .width('100%')
            .layoutWeight(1)
            .edgeEffect(EdgeEffect.Spring)
            .onReachEnd(() => this.controller?.loadMore())
          }
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
  }

  @Builder
  private statusPanel(message: string, retry: boolean) {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      if (!retry) {
        LoadingProgress()
          .id('p3_comments_loading_progress')
          .width(40)
          .height(40)
          .color($r('app.color.brand_primary'))
      }
      Text(message)
        .id('p3_comments_status')
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .textAlign(TextAlign.Center)
        .width('100%')
      if (retry) {
        if (this.requiresLogin) {
          Button('去登录')
            .id('p3_comments_status_login')
            .fontSize($r('app.float.p1_body_font_size'))
            .onClick((): void => this.navigate({ name: P1DestinationName.LOGIN }))
        } else {
          Button('重新加载')
            .id('p3_comments_status_retry')
            .fontSize($r('app.float.p1_body_font_size'))
            .onClick(() => this.controller?.retry())
        }
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .layoutWeight(1)
    .padding($r('app.float.p1_page_padding'))
  }

  @Builder
  private commentCard(comment: CommentItem, showChildSection: boolean) {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      this.authorRow(comment)
      if (comment.replyToAuthor !== undefined) {
        Text(`回复 ${comment.replyToAuthor.name}`)
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
      }
      Text(stripCommentHtml(comment.contentHtml))
        .id(`p3_comments_content_${comment.id}`)
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      this.commentFooter(comment, true)
      if (showChildSection && comment.childCommentCount > 0) {
        this.childSection(comment)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
    .borderRadius($r('app.float.p1_card_radius'))
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private pinnedRootCard(comment: CommentItem) {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      this.authorRow(comment)
      Text(stripCommentHtml(comment.contentHtml))
        .id(`p3_comments_pinned_${comment.id}`)
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      this.commentFooter(comment, false)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
    .borderRadius($r('app.float.p1_card_radius'))
    .backgroundColor($r('app.color.surface_background'))
  }

  @Builder
  private authorRow(comment: CommentItem) {
    Row({ space: $r('app.float.p1_spacing_small') }) {
      Stack({ alignContent: Alignment.Center }) {
        // 底层占位：名字首字，头像缺失或加载失败时可见。
        Text(authorInitial(comment.author.name))
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.on_brand'))
          .textAlign(TextAlign.Center)
          .width(32)
          .height(32)
          .borderRadius(16)
          .backgroundColor($r('app.color.brand_primary'))
        // 顶层真实头像：加载成功覆盖占位（加载失败保持透明，露出首字）。
        if (commentAvatarUrl(comment.author.avatarUrl).length > 0) {
          Image(commentAvatarUrl(comment.author.avatarUrl))
            .id(`p3_comments_avatar_${comment.id}`)
            .width(32)
            .height(32)
            .borderRadius(16)
            .objectFit(ImageFit.Cover)
        }
      }
      .width(32)
      .height(32)
      .clip(true)
      Text(comment.author.name)
        .id(`p3_comments_author_${comment.id}`)
        .fontSize($r('app.float.p1_body_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .onClick((): void => {
          this.navigate({
            name: P1DestinationName.PEOPLE,
            id: comment.author.urlToken.length > 0 ? comment.author.urlToken : comment.author.id
          });
        })
      if (comment.authorTag !== undefined) {
        Text(comment.authorTag)
          .fontSize($r('app.float.p1_caption_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .padding({ left: 4, right: 4, top: 1, bottom: 1 })
          .borderRadius(3)
          .border({ width: 0.5, color: $r('app.color.secondary_text') })
      }
    }
    .width('100%')
  }

  @Builder
  private commentFooter(comment: CommentItem, showDelete: boolean) {
    Row() {
      Text(formatCommentTime(comment.createdAt))
        .fontSize($r('app.float.p1_caption_font_size'))
        .fontColor($r('app.color.secondary_text'))
      Text(this.ipLocation(comment))
        .fontSize($r('app.float.p1_caption_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .margin({ left: $r('app.float.p1_spacing_small') })

      Blank()

      Row({ space: 2 }) {
        Text('回复')
          .fontSize($r('app.float.p1_caption_font_size'))
          .fontColor($r('app.color.secondary_text'))
        if (comment.childCommentCount > 0) {
          Text(`${comment.childCommentCount}`)
            .fontSize($r('app.float.p1_caption_font_size'))
            .fontColor($r('app.color.secondary_text'))
        }
      }
      .id(`p3_comments_reply_button_${comment.id}`)
      .onClick((): void => {
        this.controller?.setReplyTarget(comment);
      })

      Row({ space: 2 }) {
        Text(comment.liked ? '已赞' : '点赞')
          .fontSize($r('app.float.p1_caption_font_size'))
          .fontColor(comment.liked ? $r('app.color.brand_primary') : $r('app.color.secondary_text'))
        Text(`${comment.likeCount}`)
          .fontSize($r('app.float.p1_caption_font_size'))
          .fontColor(comment.liked ? $r('app.color.brand_primary') : $r('app.color.secondary_text'))
      }
      .id(`p3_comments_like_button_${comment.id}`)
      .margin({ left: $r('app.float.p1_spacing_medium') })
      .onClick((): void => {
        this.controller?.toggleLike(comment);
      })

      if (showDelete && comment.isAuthor) {
        Text('删除')
          .id(`p3_comments_delete_button_${comment.id}`)
          .fontSize($r('app.float.p1_caption_font_size'))
          .fontColor($r('app.color.error_text'))
          .margin({ left: $r('app.float.p1_spacing_medium') })
          .onClick((): void => {
            this.controller?.deleteComment(comment.id);
          })
      }
    }
    .width('100%')
  }

  @Builder
  private childSection(comment: CommentItem) {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      if (comment.childComments.length > 0 && this.isExpanded(comment.id)) {
        ForEach(comment.childComments, (child: CommentItem) => {
          Row({ space: $r('app.float.p1_spacing_small') }) {
            Text(child.author.name)
              .fontSize($r('app.float.p1_secondary_font_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.primary_text'))
              .onClick((): void => {
                this.navigate({
                  name: P1DestinationName.PEOPLE,
                  id: child.author.urlToken.length > 0 ? child.author.urlToken : child.author.id
                });
              })
            Text(stripCommentHtml(child.contentHtml))
              .fontSize($r('app.float.p1_secondary_font_size'))
              .fontColor($r('app.color.primary_text'))
              .layoutWeight(1)
            Text(`${child.likeCount}`)
              .fontSize($r('app.float.p1_caption_font_size'))
              .fontColor($r('app.color.secondary_text'))
          }
          .width('100%')
        }, (child: CommentItem): string => `child_${comment.id}_${child.id}`)
        Button('收起回复')
          .id(`p3_comments_collapse_${comment.id}`)
          .fontSize($r('app.float.p1_caption_font_size'))
          .onClick((): void => {
            this.toggleExpanded(comment.id);
          })
      } else if (comment.childComments.length > 0) {
        Button('展开回复')
          .id(`p3_comments_expand_${comment.id}`)
          .fontSize($r('app.float.p1_caption_font_size'))
          .onClick((): void => {
            this.toggleExpanded(comment.id);
          })
      }
      Button(`查看全部 ${comment.childCommentCount} 条回复`)
        .id(`p3_comments_child_button_${comment.id}`)
        .fontSize($r('app.float.p1_caption_font_size'))
        .enabled(!this.submitting && !this.deleting)
        .onClick((): void => {
          this.controller?.openChildComments(comment);
        })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private inputBar() {
    Column() {
      if (this.replyTarget !== undefined) {
        Row({ space: $r('app.float.p1_spacing_small') }) {
          Text(`回复 ${this.replyTarget.author.name}`)
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .layoutWeight(1)
          Button('取消回复')
            .id('p3_comments_cancel_reply')
            .fontSize($r('app.float.p1_caption_font_size'))
            .onClick((): void => {
              this.controller?.setReplyTarget(undefined);
            })
        }
        .id('p3_comments_reply_banner')
        .width('100%')
        .padding($r('app.float.p1_spacing_small'))
        .backgroundColor($r('app.color.control_background'))
      }
      if (this.actionMessage.length > 0) {
        Row({ space: $r('app.float.p1_spacing_small') }) {
          Text(this.actionMessage)
            .id('p3_comments_action_status')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.error_text'))
            .layoutWeight(1)
          if (this.actionRequiresLogin) {
            Button('去登录')
              .id('p3_comments_action_login')
              .fontSize($r('app.float.p1_secondary_font_size'))
              .onClick((): void => this.navigate({ name: P1DestinationName.LOGIN }))
          }
        }
        .width('100%')
        .padding($r('app.float.p1_spacing_small'))
      }
      Row({ space: $r('app.float.p1_spacing_small') }) {
        TextInput({
          text: this.activeRoot !== undefined ? this.replyDraft : this.rootDraft,
          placeholder: this.replyTarget !== undefined
            ? `回复 ${this.replyTarget.author.name}...`
            : (this.activeRoot !== undefined ? '写下你的回复...' : '写下你的评论...')
        })
          .id('p3_comments_input')
          .layoutWeight(1)
          .maxLength(1000)
          .onChange((value: string): void => {
            if (this.activeRoot !== undefined) {
              this.onReplyDraftChange(value);
            } else {
              this.onRootDraftChange(value);
            }
          })
        Button(this.submitting ? '发送中…' : '发送')
          .id('p3_comments_send_button')
          .fontSize($r('app.float.p1_body_font_size'))
          .enabled(!this.submitting && this.currentDraft().trim().length > 0)
          .onClick((): void => {
            this.submitCurrentDraft();
          })
      }
      .width('100%')
      .padding($r('app.float.p1_spacing_small'))
    }
    .width('100%')
    .backgroundColor($r('app.color.card_background'))
  }

  private currentDraft(): string {
    return this.activeRoot !== undefined ? this.replyDraft : this.rootDraft;
  }

  private submitCurrentDraft(): void {
    if (this.submitting || this.deleting) {
      return;
    }
    this.controller?.submitComment(this.currentDraft()).then((submitted: boolean): void => {
      if (submitted) {
        if (this.activeRoot !== undefined) {
          this.onReplyDraftChange('');
        } else {
          this.onRootDraftChange('');
        }
      }
    });
  }

  private isExpanded(commentId: string): boolean {
    return this.expandedRootIds.includes(commentId);
  }

  private toggleExpanded(commentId: string): void {
    if (this.expandedRootIds.includes(commentId)) {
      this.expandedRootIds = this.expandedRootIds.filter((value: string): boolean => value !== commentId);
    } else {
      const next = this.expandedRootIds.concat([commentId]);
      this.expandedRootIds = next.length > COMMENT_EXPANDED_IDS_LIMIT
        ? next.slice(next.length - COMMENT_EXPANDED_IDS_LIMIT)
        : next;
    }
  }

  private ipLocation(comment: CommentItem): string {
    for (const tag of comment.commentTags) {
      if (tag.type === 'ip_info' && tag.text.trim().length > 0) {
        return tag.text;
      }
    }
    return '';
  }

  private applyState(state: CommentViewState): void {
    this.phase = state.phase;
    this.items = state.items;
    this.loadingMore = state.loadingMore;
    this.canLoadMore = state.canLoadMore;
    this.requiresLogin = state.requiresLogin;
    this.errorMessage = state.errorMessage ?? '';
    this.sortOrder = state.sortOrder;
    this.activeRoot = state.activeRoot;
    this.replyTarget = state.replyTarget;
    this.submitting = state.submitting;
    this.likeBusy = state.likeBusy;
    this.deleting = state.deleting;
    this.actionMessage = state.actionMessage ?? '';
    this.actionRequiresLogin = state.actionRequiresLogin;
  }
}

function authorInitial(name: string): string {
  const trimmed = name.trim();
  return trimmed.length > 0 ? trimmed.charAt(0) : '?';
}

/** 评论用户头像 URL：http 归一化为 https，缺失或不受信返回空串（走首字占位）。 */
function commentAvatarUrl(raw: string): string {
  const trimmed = raw.trim();
  const url = trimmed.startsWith('http://') ? `https://${trimmed.substring(7)}` : trimmed;
  if (!/^https:\/\/[A-Za-z0-9.-]+/.test(url)) {
    return '';
  }
  return url;
}

function stripCommentHtml(html: string): string {
  let text = html
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(p|div|h[1-6]|li|blockquote)>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/g, '\'')
    .replace(/\n{3,}/g, '\n\n');
  return text.trim();
}

function twoDigits(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

function formatCommentTime(createdAtSeconds: number): string {
  if (!Number.isFinite(createdAtSeconds) || createdAtSeconds <= 0) {
    return '';
  }
  const date = new Date(createdAtSeconds * 1000);
  const now = new Date();
  const sameDay = date.getFullYear() === now.getFullYear() &&
    date.getMonth() === now.getMonth() && date.getDate() === now.getDate();
  if (sameDay) {
    return `${twoDigits(date.getHours())}:${twoDigits(date.getMinutes())}`;
  }
  const sameYear = date.getFullYear() === now.getFullYear();
  const datePart = sameYear
    ? `${twoDigits(date.getMonth() + 1)}-${twoDigits(date.getDate())}`
    : `${date.getFullYear()}-${twoDigits(date.getMonth() + 1)}-${twoDigits(date.getDate())}`;
  return `${datePart} ${twoDigits(date.getHours())}:${twoDigits(date.getMinutes())}`;
}
