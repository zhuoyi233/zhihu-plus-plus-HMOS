import { P1Destination, P1DestinationName } from 'core';
import {
  CommentItem,
  CommentRepository,
  CommentSortOrder,
  DEFAULT_THEME_COLOR,
  emojiStore,
  LoginSessionGateway,
  onThemeColor,
  themeColorContainerColor
} from 'data';
import {
  CommentController,
  commentContentKind,
  CommentPhase,
  CommentViewState
} from './CommentState';
import { CommentLikeButton } from './CommentLikeButton';
import { CommentLikeState, CommentLikeStateStore } from './CommentLikeState';
import { EmojiText } from './EmojiText';
/** 全屏评论页：根评论与子评论共用一个页面实例，返回操作按层级逐级退出。 */
@Component
export struct CommentPage {
  contentType: string = 'answer';
  contentId: string = '';
  repository: CommentRepository | undefined = undefined;
  session: LoginSessionGateway | undefined = undefined;
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {
  };
  @State private rootDraft: string = '';
  @State private replyDraft: string = '';
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
  @State private deleting: boolean = false;
  @State private actionMessage: string = '';
  @State private actionRequiresLogin: boolean = false;
  @State private likeStates: Record<string, CommentLikeState> = {};
  @StorageProp('emojiCatalogVersion') @Watch('onEmojiCatalogChanged') emojiCatalogVersion: number = 0;
  @StorageProp('commentPageBackTick') @Watch('onCommentPageBack') commentPageBackTick: number = 0;
  @StorageProp('statusBarHeight') private statusBarHeightVp: number = 0;
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @State private emojiTick: number = 0;
  @State private showEmojiPicker: boolean = false;
  @State private pickerColumns: number = 7;
  private caretPosition: number = -1;
  private inputController: TextInputController = new TextInputController();
  private controller?: CommentController;
  private readonly likeStateStore: CommentLikeStateStore = new CommentLikeStateStore();
  private rootScroller: Scroller = new Scroller();
  private childScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.ensureEmojiCatalog();
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
    this.controller.loadInitial();
  }

  aboutToDisappear(): void {
    this.controller?.deactivate();
    this.controller = undefined;
  }

  /** 表情表懒加载，加载完成后经 emojiCatalogVersion 广播刷新选择面板与行内渲染。 */
  private ensureEmojiCatalog(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    emojiStore.ensureLoaded(context);
  }

  onEmojiCatalogChanged(): void {
    this.emojiTick = this.emojiCatalogVersion;
  }

  onCommentPageBack(): void {
    const contentType = AppStorage.get<string>('commentPageBackContentType') ?? '';
    const contentId = AppStorage.get<string>('commentPageBackContentId') ?? '';
    if (contentType !== this.contentType || contentId !== this.contentId) {
      return;
    }
    this.handleBack();
  }

  private handleBack(): void {
    if (this.activeRoot !== undefined) {
      this.controller?.closeChildComments();
      return;
    }
    this.onDismiss();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.sheetBody()
        if (this.phase === CommentPhase.READY || this.phase === CommentPhase.EMPTY) {
          this.inputBar()
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: Math.max(this.statusBarHeightVp, 0) + 56 })
      this.pageHeader()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private pageHeader() {
    Column() {
      Blank()
        .height(Math.max(this.statusBarHeightVp, 0))
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
          .id('p3_comments_back')
          .width(40)
          .height(40)
          .padding(0)
          .backgroundColor($r('app.color.surface_background'))
          .accessibilityText(this.activeRoot === undefined ? '返回详情' : '返回评论')
          .onClick((): void => {
            this.handleBack();
          })
        Text(this.activeRoot === undefined ? '评论' : '回复')
          .textAlign(TextAlign.Center)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Blank().width(40)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .height(Math.max(this.statusBarHeightVp, 0) + 56)
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private sortChip(order: CommentSortOrder, label: string, testId: string) {
    Button(label, { type: ButtonType.ROUNDED_RECTANGLE })
      .id(testId)
      .fontSize($r('app.float.p1_secondary_font_size'))
      .fontColor(this.sortOrder === order ? this.resolvedThemeColor : $r('app.color.secondary_text'))
      .fontWeight(this.sortOrder === order ? FontWeight.Medium : FontWeight.Normal)
      .height(32)
      .padding({ left: 16, right: 16 })
      .backgroundColor(this.sortOrder === order
        ? themeColorContainerColor(this.resolvedThemeColor) : $r('app.color.control_background'))
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
                .backgroundColor(this.resolvedThemeColor)
                .fontColor(onThemeColor(this.resolvedThemeColor))
                .id('p3_comments_login')
                .fontSize($r('app.float.p1_secondary_font_size'))
                .onClick((): void => this.navigate({ name: P1DestinationName.LOGIN }))
            } else {
              Button('重试')
                .backgroundColor(this.resolvedThemeColor)
                .fontColor(onThemeColor(this.resolvedThemeColor))
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

        if (this.phase === CommentPhase.EMPTY && this.activeRoot === undefined) {
          this.statusPanel(this.activeRoot === undefined ? '暂无评论，来发表第一条吧' : '暂无回复', false)
        } else {
          if (this.activeRoot !== undefined) {
            List({ space: 16, scroller: this.childScroller }) {
              ListItem() {
                this.pinnedRootCard(this.activeRoot)
              }
              if (this.items.length === 0) {
                ListItem() {
                  Text('暂无回复')
                    .fontColor($r('app.color.secondary_text'))
                    .width('100%')
                    .textAlign(TextAlign.Center)
                }
              }
              ForEach(this.items, (comment: CommentItem) => {
                ListItem() {
                  this.commentCard(comment, false)
                }
              }, (comment: CommentItem): string => `child_${comment.id}`)
              if (this.loadingMore) {
                ListItem() {
                  // 上拉加载更多：与首页一致的圆形加载动画（onReachEnd 自动触发）
                  LoadingProgress()
                    .id('p3_comments_children_load_more')
                    .width(40)
                    .height(40)
                    .color(this.resolvedThemeColor)
                }
                .width('100%')
                .padding({ top: 12, bottom: 12 })
              }
            }
            .id('p3_comments_children_list')
            .padding({ left: 16, right: 16, top: 8, bottom: 16 })
            .width('100%')
            .layoutWeight(1)
            .edgeEffect(EdgeEffect.Spring)
            .onReachEnd(() => this.controller?.loadMore())
          } else {
            List({ space: 16, scroller: this.rootScroller }) {
              ListItem() {
                Row({ space: 12 }) {
                  this.sortChip(CommentSortOrder.SCORE, '最热', 'p3_comments_sort_score')
                  this.sortChip(CommentSortOrder.TIME, '最新', 'p3_comments_sort_time')
                }
                .width('100%')
                .justifyContent(FlexAlign.End)
              }
              ForEach(this.items, (comment: CommentItem) => {
                ListItem() {
                  this.commentCard(comment, true)
                }
              }, (comment: CommentItem): string => `root_${comment.id}`)
              if (this.loadingMore) {
                ListItem() {
                  // 上拉加载更多：与首页一致的圆形加载动画（onReachEnd 自动触发）
                  LoadingProgress()
                    .id('p3_comments_root_load_more')
                    .width(40)
                    .height(40)
                    .color(this.resolvedThemeColor)
                }
                .width('100%')
                .padding({ top: 12, bottom: 12 })
              }
            }
            .id('p3_comments_root_list')
            .padding({ left: 16, right: 16, top: 8, bottom: 16 })
            .width('100%')
            .scrollBar(BarState.Off)
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
      if (this.phase === CommentPhase.LOADING || this.phase === CommentPhase.IDLE) {
        LoadingProgress()
          .id('p3_comments_loading_progress')
          .width(40)
          .height(40)
          .color(this.resolvedThemeColor)
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
            .backgroundColor(this.resolvedThemeColor)
            .fontColor(onThemeColor(this.resolvedThemeColor))
            .id('p3_comments_status_login')
            .fontSize($r('app.float.p1_body_font_size'))
            .onClick((): void => this.navigate({ name: P1DestinationName.LOGIN }))
        } else {
          Button('重新加载')
            .backgroundColor(this.resolvedThemeColor)
            .fontColor(onThemeColor(this.resolvedThemeColor))
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
    Column({ space: 8 }) {
      this.commentRow(comment, true)
      if (showChildSection && comment.childCommentCount > 0) {
        this.childSection(comment)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private pinnedRootCard(comment: CommentItem) {
    Column({ space: 16 }) {
      this.commentRow(comment, false)
      Divider().color($r('app.color.control_background'))
    }
    .width('100%')
  }

  @Builder
  private commentRow(comment: CommentItem, showDelete: boolean) {
    Row({ space: 8 }) {
      this.avatar(comment)
      Column({ space: 4 }) {
        this.authorRow(comment)
        EmojiText({
          text: stripCommentHtml(comment.contentHtml),
          fontSize: 16,
          lineHeight: 25.6,
          fontColor: $r('app.color.primary_text'),
          copyOption: CopyOptions.LocalDevice,
          componentId: `p3_comments_content_${comment.id}`
        })
        if (commentImageUrl(comment.contentHtml).length > 0) {
          Image(commentImageUrl(comment.contentHtml))
            .id(`p3_comments_image_${comment.id}`)
            .width(200)
            .height(100)
            .constraintSize({ maxWidth: '100%' })
            .objectFit(ImageFit.Contain)
            .borderRadius(12)
            .margin({ top: 4 })
            .accessibilityText('查看评论图片')
            .onClick((): void => {
              AppStorage.setOrCreate('p2ImagePreviewUrl', commentImageUrl(comment.contentHtml));
              // 预览叠层仍由详情页持有，退出评论页后展示。
              this.onDismiss();
            })
        }
        this.commentFooter(comment, showDelete)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
    .gesture(
      PanGesture({ direction: PanDirection.Left, distance: 60 })
        .onActionEnd((): void => this.controller?.setReplyTarget(comment))
    )
  }

  @Builder
  private avatar(comment: CommentItem) {
    Stack({ alignContent: Alignment.Center }) {
      Text(authorInitial(comment.author.name))
        .fontSize(16)
        .fontColor(onThemeColor(this.resolvedThemeColor))
        .textAlign(TextAlign.Center)
        .width(36)
        .height(36)
        .backgroundColor(this.resolvedThemeColor)
      if (commentAvatarUrl(comment.author.avatarUrl).length > 0) {
        Image(commentAvatarUrl(comment.author.avatarUrl))
          .id(`p3_comments_avatar_${comment.id}`)
          .width(36)
          .height(36)
          .objectFit(ImageFit.Cover)
      }
    }
    .width(36)
    .height(36)
    .borderRadius(18)
    .clip(true)
    .accessibilityText(comment.author.name)
    .onClick((): void => this.openAuthor(comment))
  }

  @Builder
  private authorRow(comment: CommentItem) {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      Text(comment.author.name)
        .id(`p3_comments_author_${comment.id}`)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .onClick((): void => this.openAuthor(comment))
      if (comment.authorTag !== undefined) {
        Text(comment.authorTag)
          .fontSize(12)
          .fontColor($r('app.color.secondary_text'))
          .padding({ left: 3, right: 3 })
          .margin({ left: 4 })
          .borderRadius(3)
          .border({ width: 0.5, color: $r('app.color.secondary_text') })
      }
      if (comment.replyToAuthor !== undefined) {
        Text('回复')
          .fontSize(14)
          .fontColor($r('app.color.secondary_text'))
          .margin({ left: 4, right: 4 })
        Text(comment.replyToAuthor.name)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .onClick((): void => {
            const author = comment.replyToAuthor;
            if (author !== undefined) {
              this.navigate({ name: P1DestinationName.PEOPLE,
                id: author.urlToken.length > 0 ? author.urlToken : author.id });
            }
          })
      }
    }
    .width('100%')
  }

  @Builder
  private commentFooter(comment: CommentItem, showDelete: boolean) {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      Text(formatCommentTime(comment.createdAt))
        .fontSize(12)
        .fontColor($r('app.color.secondary_text'))
      if (this.ipLocation(comment).length > 0) {
        Text(this.ipLocation(comment))
          .fontSize(12)
          .fontColor($r('app.color.secondary_text'))
          .margin({ left: 8 })
      }
      Blank().layoutWeight(1)
      if (showDelete && comment.isAuthor) {
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.more'))
            .fontSize(16)
            .fontColor([$r('app.color.secondary_text')])
        }
        .id(`p3_comments_more_button_${comment.id}`)
        .width(28)
        .height(28)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText('更多操作')
        .bindMenu(this.commentMenu(comment))
      }
      Button({ type: ButtonType.Normal }) {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.message'))
            .fontSize(16)
            .fontColor([$r('app.color.secondary_text')])
          if (comment.childCommentCount > 0) {
            Text(`${comment.childCommentCount}`)
              .fontSize(12)
              .fontColor($r('app.color.secondary_text'))
          }
        }
      }
      .id(`p3_comments_reply_button_${comment.id}`)
      .height(28)
      .padding({ left: 4, right: 4 })
      .backgroundColor(Color.Transparent)
      .accessibilityText('回复')
      .onClick((): void => this.openReplies(comment))
      CommentLikeButton({
        state: this.likeStates[comment.id],
        interactionEnabled: !this.submitting && !this.deleting,
        onToggle: (): void => { this.controller?.toggleLike(comment); }
      })
    }
    .width('100%')
  }

  @Builder
  private commentMenu(comment: CommentItem) {
    Menu() {
      MenuItem(this.deleteMenuLabel())
        .id(`p3_comments_delete_button_${comment.id}`)
        .onClick((): void => {
          this.getUIContext().showAlertDialog({
            title: '删除评论',
            message: '删除后无法恢复，确认删除这条评论吗？',
            primaryButton: { value: '取消', action: (): void => {} },
            secondaryButton: { value: '删除', action: (): void => { this.controller?.deleteComment(comment.id); } }
          });
        })
    }
  }

  @Builder
  private deleteMenuLabel() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(16)
        .fontColor([$r('app.color.error_text')])
      Text('删除').fontColor($r('app.color.error_text'))
    }
    .padding(12)
  }

  @Builder
  private childSection(comment: CommentItem) {
    Column({ space: 8 }) {
      ForEach(comment.childComments, (child: CommentItem) => {
        this.commentRow(child, false)
      }, (child: CommentItem): string => `preview_${comment.id}_${child.id}`)
      Button({ type: ButtonType.Capsule }) {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.message'))
            .fontSize(16)
            .fontColor([$r('app.color.secondary_text')])
          Text(`查看 ${comment.childCommentCount} 条子评论`)
            .fontSize(12)
            .fontColor($r('app.color.primary_text'))
        }
      }
      .id(`p3_comments_child_button_${comment.id}`)
      .height(28)
      .padding({ left: 16, right: 16 })
      .backgroundColor($r('app.color.control_background'))
      .enabled(!this.submitting && !this.deleting)
      .onClick((): void => { this.controller?.openChildComments(comment); })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 40 })
  }

  private openAuthor(comment: CommentItem): void {
    this.navigate({ name: P1DestinationName.PEOPLE,
      id: comment.author.urlToken.length > 0 ? comment.author.urlToken : comment.author.id });
  }

  private openReplies(comment: CommentItem): void {
    if (this.activeRoot !== undefined) {
      this.controller?.setReplyTarget(comment);
      return;
    }
    const root = this.items.find((item: CommentItem): boolean =>
      item.id === comment.id || item.childComments.some((child: CommentItem): boolean => child.id === comment.id));
    if (root !== undefined) {
      this.controller?.openChildComments(root);
    }
  }
  /** 对齐上游 GridCells.Adaptive(minSize = 48dp)：按面板实际宽度自适应列数，默认 7 列。 */
  private emojiColumnsTemplate(): string {
    const columns = this.pickerColumns > 0 ? this.pickerColumns : 7;
    return '1fr '.repeat(columns).trim();
  }

  /** 作为 TextInput 自定义键盘呈现：占据软键盘位置并与其互斥（对齐上游评论区表情面板）。 */
  @Builder
  private emojiPickerPanel() {
    Column() {
      if (emojiStore.placeholders().length === 0) {
        Text('暂无可用表情')
          .id('p3_comments_emoji_picker')
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .textAlign(TextAlign.Center)
          .width('100%')
          .height('100%')
      } else {
        Grid() {
          ForEach(emojiStore.placeholders(), (placeholder: string, index: number) => {
            GridItem() {
              Image(emojiStore.path(placeholder))
                .width(36)
                .height(36)
                .objectFit(ImageFit.Contain)
                .accessibilityText(placeholder)
                .onClick((): void => this.insertEmoji(placeholder))
            }
            .height(48)
            .id(`p3_comments_emoji_item_${index}`)
          }, (placeholder: string): string => `${this.emojiTick}_${placeholder}`)
        }
          .id('p3_comments_emoji_picker')
          .columnsTemplate(this.emojiColumnsTemplate())
          .height('100%')
          .width('100%')
          .padding(8)
          .scrollBar(BarState.Off)
          .onAreaChange((_oldValue: Area, newValue: Area): void => {
            const widthVp = typeof newValue.width === 'number'
              ? newValue.width : Number(newValue.width);
            const columns = Math.max(1, Math.floor((widthVp - 16) / 48));
            if (columns !== this.pickerColumns) {
              this.pickerColumns = columns;
            }
          })
      }
    }
    .width('100%')
    .height(240)
    .backgroundColor($r('app.color.card_background'))
  }

  private insertEmoji(placeholder: string): void {
    const current = this.currentDraft();
    const index = this.caretPosition >= 0 && this.caretPosition <= current.length
      ? this.caretPosition : current.length;
    const next = current.slice(0, index) + placeholder + current.slice(index);
    if (this.activeRoot !== undefined) {
      this.replyDraft = next;
    } else {
      this.rootDraft = next;
    }
    const caret = index + placeholder.length;
    setTimeout((): void => this.inputController.caretPosition(caret), 0);
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
          Button({ type: ButtonType.Normal }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(16)
              .fontColor([$r('app.color.secondary_text')])
          }
            .id('p3_comments_cancel_reply')
            .width(28)
            .height(28)
            .padding(0)
            .backgroundColor(Color.Transparent)
            .accessibilityText('取消回复')
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
              .backgroundColor(this.resolvedThemeColor)
              .fontColor(onThemeColor(this.resolvedThemeColor))
              .id('p3_comments_action_login')
              .fontSize($r('app.float.p1_secondary_font_size'))
              .onClick((): void => this.navigate({ name: P1DestinationName.LOGIN }))
          }
        }
        .width('100%')
        .padding($r('app.float.p1_spacing_small'))
      }
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph(this.showEmojiPicker
            ? $r('sys.symbol.keyboard') : $r('sys.symbol.face_smiling'))
            .fontSize(22)
            .fontColor([this.showEmojiPicker
              ? this.resolvedThemeColor : $r('app.color.secondary_text')])
        }
          .id('p3_comments_emoji_button')
          .width(40)
          .height(40)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .focusable(false)
          .accessibilityText(this.showEmojiPicker ? '切换到键盘' : '选择表情')
          .onClick((): void => {
            if (this.showEmojiPicker) {
              this.showEmojiPicker = false;
              this.getUIContext().getFocusController().requestFocus('p3_comments_input');
              return;
            }
            // 对齐上游：开面板时清焦点、收软键盘，面板与键盘互斥。
            this.getUIContext().getFocusController().clearFocus();
            this.inputController.stopEditing();
            this.showEmojiPicker = true;
          })
        TextInput({
          text: this.activeRoot !== undefined ? this.replyDraft : this.rootDraft,
          placeholder: this.replyTarget !== undefined
            ? `回复 ${this.replyTarget.author.name}...`
            : (this.activeRoot !== undefined ? '写下你的回复...' : '写下你的评论...'),
          controller: this.inputController
        })
          .id('p3_comments_input')
          .layoutWeight(1)
          .maxLength(1000)
          .onTextSelectionChange((start: number, end: number): void => {
            this.caretPosition = end;
          })
          .onFocus((): void => {
            // 对齐上游 onFocusChanged：输入框聚焦即收起表情面板、让位软键盘。
            this.showEmojiPicker = false;
          })
          .onChange((value: string): void => {
            if (this.activeRoot !== undefined) {
              this.replyDraft = value;
            } else {
              this.rootDraft = value;
            }
          })
        Button({ type: ButtonType.Normal }) {
          if (this.submitting) {
            LoadingProgress().width(24).height(24)
          } else {
            SymbolGlyph($r('sys.symbol.paperplane'))
              .fontSize(24)
              .fontColor([this.currentDraft().trim().length > 0
                ? this.resolvedThemeColor : $r('app.color.secondary_text')])
          }
        }
          .id('p3_comments_send_button')
          .width(40)
          .height(40)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText(this.submitting ? '发送中' : '发送')
          .fontSize($r('app.float.p1_body_font_size'))
          .enabled(!this.submitting && this.currentDraft().trim().length > 0)
          .onClick((): void => {
            this.submitCurrentDraft();
          })
      }
      .width('100%')
      .padding($r('app.float.p1_spacing_small'))
      if (this.showEmojiPicker) {
        this.emojiPickerPanel()
      }
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
          this.replyDraft = '';
        } else {
          this.rootDraft = '';
        }
      }
    });
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
    if (state.activeRoot !== undefined) {
      this.likeStateStore.sync([state.activeRoot]);
    }
    this.likeStateStore.sync(state.items);
    this.likeStates = this.likeStateStore.snapshot();
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

function commentImageUrl(html: string): string {
  const anchors = html.match(/<a\b[^>]*>/gi) ?? [];
  for (const anchor of anchors) {
    if (!/\bclass\s*=\s*["'][^"']*\bcomment_(img|gif|sticker)\b/i.test(anchor)) {
      continue;
    }
    const href = anchor.match(/\bhref\s*=\s*["']([^"']+)["']/i);
    if (href !== null) {
      const url = commentAvatarUrl(href[1].replace(/&amp;/gi, '&'));
      if (/^https:\/\/(?:picx?|pic[0-9]+)\.zhimg\.com\//i.test(url)) {
        return url;
      }
    }
  }
  return '';
}

function stripCommentHtml(html: string): string {
  const content = commentImageUrl(html).length > 0
    ? html.replace(/<a\b[^>]*\bclass\s*=\s*["'][^"']*\bcomment_(img|gif|sticker)\b[^"']*["'][^>]*>[\s\S]*?<\/a>/gi, '')
    : html;
  let text = content
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
