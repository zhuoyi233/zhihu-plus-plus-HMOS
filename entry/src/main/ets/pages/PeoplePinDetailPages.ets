import { CenteredOverlayDialog } from './CenteredOverlayDialog';
import {
  consumeTopBarAction,
  publishTopBarActionState,
  removeTopBarActionState
} from '../common/style/TopBarActionBus';
import { floatingTitleBarOffset } from './AppPageChrome';
import { AppDestination, AppDestinationName } from 'core';
import {
  BlockedFeedHistoryGateway,
  BlockingRuleGateway,
  DEFAULT_THEME_COLOR,
  FollowMutationResult,
  FollowRepository,
  LoginSessionGateway,
  onThemeColor,
  ReadHistoryUploadRepository,
  PeopleContentItem,
  PeopleContentKind,
  PeopleContentRepository,
  PeopleContentSection,
  PeopleDetailRepository,
  PeopleProfile,
  themeColorContainerColor
} from 'data';
import {
  PeopleDetailController,
  PeopleDetailViewState,
  ReadOnlyDetailPhase
} from './PeoplePinDetailState';
import { FollowController, FollowViewState } from './ContentInteractionState';
import { PeopleContentController, PeopleContentPhase, PeopleContentViewState } from './PeopleContentState';
import { publishPeopleTitle, removePeopleTitle } from './PeopleTitleBar';
import {
  BlockingActionController,
  BlockingActionViewState,
  BlockingUserCandidate
} from './BlockingActionState';
import { adaptiveOverlayWidth, isWideOverlayContainer, ADAPTIVE_OVERLAY_MENU_WIDTH_VP } from '../common/style/AdaptiveOverlayLayout';

/** 本页在顶栏动作通道里的注册 id（与 AppShell 常量一致）。 */
const PEOPLE_DETAIL_TOP_BAR_ID: string = 'people_detail';

/**
 * 只读详情的统一加载/错误面板（用户主页与想法详情共用）。
 * 覆盖式顶栏页面经 topInsetVp 让开顶栏，底部经 bottomInsetVp 让开系统手势区。
 */
@Component
export struct ReadOnlyDetailStatusPanel {
  kind: string = '';
  message: string = '';
  loading: boolean = false;
  requiresLogin: boolean = false;
  topInsetVp: number = 0;
  bottomInsetVp: number = 0;
  onRetry: () => void = (): void => {
  };
  navigate: (destination: AppDestination) => void = (_destination: AppDestination): void => {
  };
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;

  build() {
    Column({ space: $r('app.float.spacing_medium') }) {
      if (this.loading) {
        LoadingProgress()
          .id(`people_pin_${this.kind}_detail_loading_progress`)
          .width(40)
          .height(40)
          .color(this.resolvedThemeColor)
      }
      Text(this.message)
        .id(`people_pin_${this.kind}_detail_status`)
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .textAlign(TextAlign.Center)
        .width('100%')
      if (!this.loading) {
        if (this.requiresLogin) {
          Button('去登录')
            .backgroundColor(this.resolvedThemeColor)
            .fontColor(onThemeColor(this.resolvedThemeColor))
            .id(`people_pin_${this.kind}_detail_login`)
            .onClick((): void => this.navigate({ name: AppDestinationName.LOGIN }))
        } else {
          Button('重新加载')
            .backgroundColor(this.resolvedThemeColor)
            .fontColor(onThemeColor(this.resolvedThemeColor))
            .id(`people_pin_${this.kind}_detail_retry`)
            .onClick((): void => this.onRetry())
        }
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .height('100%')
    .padding({
      left: $r('app.float.page_padding'),
      right: $r('app.float.page_padding'),
      top: Math.max(0, this.topInsetVp),
      bottom: Math.max(0, this.bottomInsetVp)
    })
  }
}

@Component
export struct PeopleDetailPage {
  identifier: string = '';
  repository: PeopleDetailRepository | undefined = undefined;
  /** 阅读历史上云仓库（对齐上游 addReadHistory；未配置或游客态时不上报）。 */
  historyUploader: ReadHistoryUploadRepository | undefined = undefined;
  contentRepository: PeopleContentRepository | undefined = undefined;
  followRepository: FollowRepository | undefined = undefined;
  session: LoginSessionGateway | undefined = undefined;
  rules: BlockingRuleGateway | undefined = undefined;
  history: BlockedFeedHistoryGateway | undefined = undefined;
  navigate: (destination: AppDestination) => void = (_destination: AppDestination): void => {
  };
  onBack: () => void = (): void => {};
  @State private phase: ReadOnlyDetailPhase = ReadOnlyDetailPhase.IDLE;
  @State private profile: PeopleProfile | undefined = undefined;
  @State private errorMessage: string = '';
  @State private requiresLogin: boolean = false;
  @State private selectedSection: PeopleContentSection = PeopleContentSection.ANSWERS;
  @State private contentPhase: PeopleContentPhase = PeopleContentPhase.IDLE;
  @State private contentItems: Array<PeopleContentItem> = [];
  @State private contentLoadingMore: boolean = false;
  @State private contentCanLoadMore: boolean = false;
  @State private contentRequiresLogin: boolean = false;
  @State private contentErrorMessage: string = '';
  @State private pendingUserBlock?: BlockingUserCandidate = undefined;
  @State private profileActionsSheetShown: boolean = false;
  @State @Watch('userBlockDialogControllerChanged') private userBlockSheetShown: boolean = false;
  @State private overlayWidthVp: number = 0;
  @State private blockingMessage: string = '';
  @State private blockingBusy: boolean = false;
  @State private following: boolean = false;
  @State private followerCount: number = 0;
  @State private followPending: boolean = false;
  @State private followErrorMessage: string = '';
  @State private followRequiresLogin: boolean = false;
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  /** 顶栏“更多”请求：标题与返回由宿主 HDS 标题栏承载，本页只响应动作点击。 */
  @StorageProp('topBarActionTick') @Watch('onTopBarActionTick') private topBarActionTick: number = 0;
  private controller?: PeopleDetailController;
  private contentController?: PeopleContentController;
  private readonly contentScroller: Scroller = new Scroller();
  private titleAnchorVp: number = 0;
  @State private titleScrolled: boolean = false;
  private headerHeightVp: number = 0;
  private listViewportVp: number = 0;
  @State private tabsPinned: boolean = false;
  private blockingAction?: BlockingActionController;
  private followController?: FollowController;

  private userBlockDialogController: CustomDialogController = new CustomDialogController({
    builder: CenteredOverlayDialog({ content: (): void => { this.userBlockDialog(); } }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    maskColor: '#99000000',
    backgroundColor: $r('app.color.surface_background'),
    cancel: (): void => { this.userBlockSheetShown = false; }
  });

  private userBlockDialogControllerChanged(): void {
    if (this.userBlockSheetShown) {
      this.userBlockDialogController.open();
    } else {
      this.userBlockDialogController.close();
    }
  }

  aboutToAppear(): void {
    // 顶栏动作：加载完成前“更多”不可用，失败/未登录状态也保持可返回（返回由 HDS 承载）。
    publishTopBarActionState({ id: PEOPLE_DETAIL_TOP_BAR_ID, available: false, title: '', text: '', enabled: true });
    // P3-7：返回栈重显（页面实例与状态保留）时 aboutToAppear 可能再次触发；
    // 控制器仍存活时直接复用，避免重建控制器并重载内容导致滚动位置丢失。
    if (this.controller !== undefined) {
      this.controller.activate();
      return;
    }
    if (this.repository === undefined || this.session === undefined) {
      this.phase = ReadOnlyDetailPhase.ERROR;
      this.errorMessage = '用户主页数据源未配置';
      return;
    }
    this.controller = new PeopleDetailController(
      this.repository,
      this.session,
      (state: PeopleDetailViewState): void => this.applyState(state),
      this.historyUploader
    );
    this.controller.activate();
    this.controller.load(this.identifier);
    this.createBlockingAction();
  }

  aboutToDisappear(): void {
    removeTopBarActionState(PEOPLE_DETAIL_TOP_BAR_ID);
    removePeopleTitle(this.identifier);
    this.controller?.deactivate();
    this.contentController?.deactivate();
    this.followController?.deactivate();
    this.controller = undefined;
    this.contentController = undefined;
    this.blockingAction = undefined;
    this.pendingUserBlock = undefined;
    this.profileActionsSheetShown = false;
    this.userBlockSheetShown = false;
    this.followController = undefined;
  }

  private createBlockingAction(): void {
    const rules = this.rules;
    const history = this.history;
    if (rules === undefined || history === undefined) {
      return;
    }
    this.blockingAction = new BlockingActionController(rules, history, (state: BlockingActionViewState): void => {
      this.blockingMessage = state.message;
      this.blockingBusy = state.busy;
    });
  }

  build() {
    Column() {
      if (this.phase === ReadOnlyDetailPhase.IDLE || this.phase === ReadOnlyDetailPhase.LOADING) {
        ReadOnlyDetailStatusPanel({
          kind: 'people',
          message: '正在加载用户主页…',
          loading: true,
          topInsetVp: floatingTitleBarOffset(),
          navigate: this.navigate
        })
      } else if (this.phase === ReadOnlyDetailPhase.ERROR) {
        ReadOnlyDetailStatusPanel({
          kind: 'people',
          message: this.errorMessage,
          requiresLogin: this.requiresLogin,
          topInsetVp: floatingTitleBarOffset(),
          onRetry: (): void => {
            this.controller?.load(this.identifier);
          },
          navigate: this.navigate
        })
      } else if (this.profile !== undefined) {
        Stack({ alignContent: Alignment.Top }) {
          this.loadedProfile(this.profile)
          if (this.tabsPinned) {
            // 吸顶后的选项卡条：贴在 HDS 标题栏下沿，列表卡片从其下方透明穿过
            Column() {
              this.contentSectionTabs()
              if (this.contentPhase === PeopleContentPhase.IDLE || this.contentPhase === PeopleContentPhase.LOADING) {
                this.pinnedContentLoading()
              }
            }
            .margin({ top: floatingTitleBarOffset() })
            .width('100%')
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
      // 独立路由的更多菜单：动作按钮在宿主 HDS 标题栏，弹层仍由本页承载。
      Column()
        .bindSheet(this.profileActionsSheetShown, this.profileActionsSheet(), {
          preferType: isWideOverlayContainer(this.overlayWidthVp) ? SheetType.POPUP : SheetType.BOTTOM,
          width: isWideOverlayContainer(this.overlayWidthVp)
            ? adaptiveOverlayWidth(this.overlayWidthVp, ADAPTIVE_OVERLAY_MENU_WIDTH_VP) : '100%',
          height: SheetSize.FIT_CONTENT,
          dragBar: !isWideOverlayContainer(this.overlayWidthVp),
          showClose: false,
          maskColor: '#99000000',
          backgroundColor: $r('app.color.surface_background'),
          onDisappear: (): void => {
            if (this.profileActionsSheetShown) {
              this.profileActionsSheetShown = false;
            }
          }
        })
    }
    .id('people_detail_page')
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      const width = Number(newArea.width);
      if (width > 0) {
        this.overlayWidthVp = width;
      }
    })
    .backgroundColor($r('app.color.page_background'))
  }

  /** 顶栏“更多”：转调本页操作弹层。 */
  private onTopBarActionTick(): void {
    if (consumeTopBarAction(PEOPLE_DETAIL_TOP_BAR_ID) && this.profile !== undefined) {
      this.profileActionsSheetShown = true;
    }
  }

  @Builder
  private loadedProfile(profile: PeopleProfile) {
    List({ scroller: this.contentScroller }) {
      ListItem() {
        Column({ space: $r('app.float.spacing_large') }) {
          if (profile.avatarUrl !== undefined) {
            Image(profile.avatarUrl)
              .id('people_detail_avatar')
              .width(88)
              .height(88)
              .borderRadius(44)
              .objectFit(ImageFit.Cover)
          } else {
            Text(profile.name.charAt(0))
              .id('people_detail_avatar_fallback')
              .width(88)
              .height(88)
              .borderRadius(44)
              .backgroundColor($r('app.color.surface_background'))
              .fontSize($r('app.float.display_font_size'))
              .fontColor(this.resolvedThemeColor)
              .textAlign(TextAlign.Center)
          }

          Column({ space: $r('app.float.spacing_small') }) {
            Text(profile.name)
              .id('people_detail_name')
              .fontSize($r('app.float.display_font_size'))
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))
              .textAlign(TextAlign.Center)
            if (profile.isOrganization) {
              Text('机构账号')
                .id('people_detail_organization')
                .fontSize($r('app.float.secondary_font_size'))
                .fontColor(this.resolvedThemeColor)
            }
            if (profile.headline.length > 0) {
              Text(profile.headline)
                .id('people_detail_headline')
                .fontSize($r('app.float.body_font_size'))
                .fontColor($r('app.color.secondary_text'))
                .textAlign(TextAlign.Center)
                .width('100%')
            }
          }
          .alignItems(HorizontalAlign.Center)
          .width('100%')
          // 顶栏联动阈值：昵称块相对资料列的 y+height 即其底边滚到顶栏下沿所需的偏移（vp）
          .onAreaChange((_oldArea: Area, newArea: Area): void => {
            const bottom = Number(newArea.position.y) + Number(newArea.height);
            if (bottom > 0 && Math.abs(bottom - this.titleAnchorVp) > 1) {
              this.titleAnchorVp = bottom;
            }
          })

          Row() {
            this.profileStatistic('回答', profile.answerCount, 'answers')
            this.profileStatistic('文章', profile.articleCount, 'articles')
            this.profileStatistic('关注', profile.followingCount, 'following')
            this.profileStatistic('粉丝', this.followerCount, 'followers')
          }
          .id('people_detail_statistics')
          .width('100%')
          .justifyContent(FlexAlign.SpaceEvenly)
          .padding($r('app.float.spacing_medium'))
          .backgroundColor($r('app.color.surface_background'))
          .borderRadius(16)

          if (this.followController !== undefined) {
            Row({ space: $r('app.float.spacing_small') }) {
              Button(this.following ? '已关注' : '关注', { type: ButtonType.Capsule })
                .id('people_follow')
                .width('100%')
                .fontSize($r('app.float.body_font_size'))
                .fontColor(this.following ? this.resolvedThemeColor : onThemeColor(this.resolvedThemeColor))
                .backgroundColor(this.following
                  ? themeColorContainerColor(this.resolvedThemeColor)
                  : this.resolvedThemeColor)
                .enabled(!this.followPending)
                .onClick((): void => {
                  this.followController?.toggleFollow();
                })
            }
            .id('people_action_row')
            .width('100%')
          }

          if (this.followErrorMessage.length > 0) {
            Row({ space: $r('app.float.spacing_small') }) {
              Text(this.followErrorMessage)
                .id('people_follow_status')
                .fontSize($r('app.float.secondary_font_size'))
                .fontColor($r('app.color.error_text'))
                .layoutWeight(1)
              if (this.followRequiresLogin) {
                Button('去登录')
                  .backgroundColor(this.resolvedThemeColor)
                  .fontColor(onThemeColor(this.resolvedThemeColor))
                  .id('people_follow_login')
                  .fontSize($r('app.float.secondary_font_size'))
                  .onClick((): void => {
                    this.navigate({ name: AppDestinationName.LOGIN });
                  })
              }
            }
            .width('100%')
          }

          if (this.blockingMessage.length > 0) {
            Text(this.blockingMessage)
              .id('people_detail_blocking_status')
              .fontSize($r('app.float.secondary_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .width('100%')
          }
        }
        .alignItems(HorizontalAlign.Center)
        .width('100%')
        // 顶栏覆盖式透明：静止时资料区从顶栏下方起排，滚动时整块内容从其下穿过
        .padding({ left: $r('app.float.page_padding'), right: $r('app.float.page_padding'),
          top: floatingTitleBarOffset(), bottom: $r('app.float.page_padding') })
        // 选项卡条吸顶阈值：资料块高度即其内容起始位置，滚到顶栏下沿时改由覆盖层承载
        .onAreaChange((_oldArea: Area, newArea: Area): void => {
          const height = Number(newArea.height);
          if (height > 0 && Math.abs(height - this.headerHeightVp) > 1) {
            this.headerHeightVp = height;
          }
        })
      }

      ListItem() {
        if (this.tabsPinned) {
          Column().width('100%').height(44)
        } else {
          this.contentSectionTabs()
        }
      }

      ListItem() {
        this.contentList()
      }
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      const height = Number(newArea.height);
      if (height > 0 && Math.abs(height - this.listViewportVp) > 1) {
        this.listViewportVp = height;
      }
    })
    .onDidScroll((): void => {
      this.updateChromeByScroll(this.contentScroller.currentOffset().yOffset);
    })
    // 左右滑动切换栏目：必须用 priorityGesture——parallelGesture 下卡片的 tap 仍会命中，
    // 横滑会顺带打开卡片；限定向为 Horizontal，不影响列表纵向滚动。
    .priorityGesture(
      PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 60 })
        .onActionEnd((event: GestureEvent): void => {
          this.switchSectionBySwipe(event.offsetX);
        })
    )
  }

  /** 左右滑动切换回答/文章/动态：offsetX 为负（左滑）向后，为正（右滑）向前。 */
  private switchSectionBySwipe(offsetX: number): void {
    const order: Array<PeopleContentSection> = [PeopleContentSection.ANSWERS, PeopleContentSection.ARTICLES,
      PeopleContentSection.ACTIVITIES];
    const step = offsetX < 0 ? 1 : -1;
    const next = order.indexOf(this.selectedSection) + step;
    if (next < 0 || next >= order.length) {
      return;
    }
    this.selectSection(order[next]);
  }

  /** 顶栏文案与选项卡吸顶联动：昵称滚出顶栏后改显昵称；资料块滚过时选项卡条改由覆盖层承载。 */
  private updateChromeByScroll(offset: number): void {
    const profile = this.profile;
    const pinned = this.headerHeightVp > 0 ? offset >= this.headerHeightVp - floatingTitleBarOffset() : false;
    if (pinned !== this.tabsPinned) {
      this.tabsPinned = pinned;
    }
    if (profile === undefined) {
      return;
    }
    const threshold = this.titleAnchorVp > 0 ? this.titleAnchorVp : 260;
    const scrolled = offset > threshold;
    if (scrolled === this.titleScrolled) {
      return;
    }
    this.titleScrolled = scrolled;
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, (): void => {
      publishPeopleTitle({ id: this.identifier, name: profile.name, scrolled: scrolled });
    });
  }

  @Builder
  private profileStatistic(label: string, value: number, tag: string) {
    Column({ space: 4 }) {
      Text(`${value}`)
        .id(`people_detail_${tag}_count`)
        .fontSize($r('app.float.heading_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
      Text(label)
        .fontSize($r('app.float.secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
    }
    .alignItems(HorizontalAlign.Center)
  }

  private applyState(state: PeopleDetailViewState): void {
    this.phase = state.phase;
    this.profile = state.profile;
    // “更多”可用性随加载结果更新（加载中/失败时宿主只画标题，不留无效动作）。
    publishTopBarActionState({
      id: PEOPLE_DETAIL_TOP_BAR_ID,
      available: state.profile !== undefined,
      title: '',
      text: '',
      enabled: true
    });
    this.errorMessage = state.errorMessage ?? '';
    this.requiresLogin = state.requiresLogin;
    if (state.phase === ReadOnlyDetailPhase.READY && this.contentController === undefined) {
      this.activateContent();
    }
    if (state.phase === ReadOnlyDetailPhase.READY && state.profile !== undefined) {
      this.activateFollow(state.profile);
      publishPeopleTitle({
        id: this.identifier,
        name: state.profile.name,
        scrolled: this.titleScrolled
      });
    }
  }

  private activateFollow(profile: PeopleProfile): void {
    if (this.followController !== undefined || this.followRepository === undefined || this.session === undefined) {
      return;
    }
    const repository = this.followRepository;
    const session = this.session;
    const identifier = profile.urlToken ?? profile.id;
    this.followController = new FollowController(
      repository,
      session,
      (follow: boolean): Promise<FollowMutationResult> => repository.followUser(identifier, follow),
      (state: FollowViewState): void => this.applyFollowState(state)
    );
    this.followController.activate();
    this.followController.applyInitial(profile.isFollowing, profile.followerCount);
  }

  private applyFollowState(state: FollowViewState): void {
    this.following = state.following;
    this.followerCount = state.followerCount;
    this.followPending = state.pending;
    this.followErrorMessage = state.errorMessage ?? '';
    this.followRequiresLogin = state.requiresLogin;
  }

  @Builder
  private contentSectionTabs() {
    Scroll() {
      Row({ space: $r('app.float.spacing_small') }) {
        this.contentTab('回答', PeopleContentSection.ANSWERS)
        this.contentTab('文章', PeopleContentSection.ARTICLES)
        this.contentTab('动态', PeopleContentSection.ACTIVITIES)
      }
      .padding({ left: $r('app.float.spacing_small'), right: $r('app.float.spacing_small') })
    }
    .scrollBar(BarState.Off)
    .id('people_content_tabs')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    // 吸顶后不铺色、也不用 COMPONENT_* 材质（自带白纱会把穿过的卡片糊成一条白带）：
    // backgroundEffect 的蒙版色默认透明，只留纯高斯模糊，卡片从选项卡下方透光穿过。
    // uiMaterial 为 API 26 专属，禁止引入。
    .padding({ left: $r('app.float.page_padding'), right: $r('app.float.page_padding') })
    .backgroundColor(Color.Transparent)
    .backgroundEffect({ radius: this.tabsPinned ? 24 : 0 })
    .width('100%')
    .height(44)
  }

  @Builder
  private contentTab(label: string, section: PeopleContentSection) {
    Button(label, { type: ButtonType.Normal, stateEffect: true })
      .id(`people_content_tab_${section}`)
      .height(44)
      .padding({ left: $r('app.float.spacing_medium'), right: $r('app.float.spacing_medium') })
      .fontSize($r('app.float.body_font_size'))
      .fontWeight(this.selectedSection === section ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.selectedSection === section ? this.resolvedThemeColor : $r('app.color.primary_text'))
      .backgroundColor(Color.Transparent)
      .border({
        width: { bottom: this.selectedSection === section ? 2 : 0 },
        color: this.resolvedThemeColor
      })
      .onClick((): void => this.selectSection(section))
  }

  @Builder
  private contentList() {
    Column({ space: $r('app.float.spacing_small') }) {
      if (this.contentPhase === PeopleContentPhase.IDLE || this.contentPhase === PeopleContentPhase.LOADING) {
        if (this.tabsPinned) {
          // 转圈改挂到选项卡条覆盖层下方；这里只占位，避免列表塌缩把滚动偏移钳回顶部
          Column()
            .width('100%')
            .height(this.listViewportVp > 0 ? this.listViewportVp : 360)
        } else {
          this.contentLoadingIndicator()
        }
      } else if (this.contentPhase === PeopleContentPhase.ERROR) {
        this.contentStatus(true)
      } else if (this.contentPhase === PeopleContentPhase.EMPTY) {
        Text('暂时没有可展示的内容')
          .id('people_content_empty')
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.secondary_text'))
      } else {
        ForEach(this.contentItems, (item: PeopleContentItem) => {
          this.contentCard(item)
        }, (item: PeopleContentItem): string => `${item.kind}:${item.id}`)
        if (this.contentErrorMessage.length > 0) {
          this.contentStatus(false)
        }
        if (this.contentLoadingMore || this.contentCanLoadMore) {
          Button(this.contentLoadingMore ? '正在加载更多…' : '加载更多')
            .backgroundColor(this.resolvedThemeColor)
            .fontColor(onThemeColor(this.resolvedThemeColor))
            .id('people_content_load_more')
            .width('100%')
            .enabled(!this.contentLoadingMore)
            .onClick((): void => {
              this.contentController?.loadMore();
            })
        }
      }
    }
    .id('people_content_list')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: $r('app.float.page_padding'), right: $r('app.float.page_padding') })
    .width('100%')
  }

  @Builder
  private contentLoadingIndicator() {
    Row() {
      this.contentLoadingSpinner()
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Top)
    .width('100%')
    // 占满一屏：切换栏目时列表内容不会塌缩，滚动偏移不被钳位，吸顶位置保持不变
    .height(this.listViewportVp > 0 ? this.listViewportVp : 360)
    .padding({ top: 12, bottom: 12 })
  }

  // 吸顶时列表内容塌缩会把流内转圈顶到屏幕最上沿，故挂在选项卡条覆盖层下方固定位置
  @Builder
  private pinnedContentLoading() {
    Row() {
      this.contentLoadingSpinner()
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .padding({ top: 12 })
    // 只做指示，不能挡住下方卡片的点击
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private contentLoadingSpinner() {
    LoadingProgress()
      .id('people_content_loading')
      .width(40)
      .height(40)
      .color(this.resolvedThemeColor)
  }

  @Builder
  private contentStatus(initial: boolean) {
    Column({ space: $r('app.float.spacing_small') }) {
      Text(this.contentErrorMessage)
        .id('people_content_status')
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      if (this.contentRequiresLogin) {
        Button('去登录')
          .backgroundColor(this.resolvedThemeColor)
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .id('people_content_login')
          .onClick((): void => this.navigate({ name: AppDestinationName.LOGIN }))
      } else {
        Button(initial ? '重新加载' : '重试加载更多')
          .backgroundColor(this.resolvedThemeColor)
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .id('people_content_retry')
          .onClick((): void => {
            this.contentController?.retry();
          })
      }
    }
    .width('100%')
  }

  @Builder
  private contentCard(item: PeopleContentItem) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Column({ space: $r('app.float.spacing_small') }) {
        Text(peopleContentKindLabel(item.kind))
          .fontSize($r('app.float.secondary_font_size'))
          .fontColor(this.resolvedThemeColor)
        Text(item.title)
          .fontSize($r('app.float.heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .width('100%')
        if (item.excerpt.trim().length > 0) {
          Text(item.excerpt)
            .fontSize($r('app.float.body_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
            .maxLines(3)
        }
        Text(`${item.voteupCount} 赞同 · ${item.commentCount} 评论`)
          .fontSize($r('app.float.secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .id(`people_content_${item.kind}_${item.id}`)
    .width('100%')
    .padding($r('app.float.card_padding'))
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.surface_background'))
    .onClick((): void => this.navigate(peopleContentDestination(item)))
  }

  private selectSection(section: PeopleContentSection): void {
    if (this.selectedSection === section) {
      return;
    }
    this.contentController?.deactivate();
    this.contentController = undefined;
    this.selectedSection = section;
    this.contentItems = [];
    this.contentErrorMessage = '';
    this.contentPhase = PeopleContentPhase.IDLE;
    this.activateContent();
  }

  private activateContent(): void {
    if (this.contentRepository === undefined) {
      this.contentPhase = PeopleContentPhase.ERROR;
      this.contentErrorMessage = '用户内容数据源未配置';
      return;
    }
    this.contentController = new PeopleContentController(
      // 内容接口按 url_token 定位（上游 person.userTokenOrId）：搜索进入时路由是哈希 id，
      // members/{哈希 id}/articles 会 404。
      this.profile?.urlToken ?? this.identifier,
      this.selectedSection,
      this.contentRepository,
      (state: PeopleContentViewState): void => this.applyContentState(state)
    );
    this.contentController.activate();
    this.contentController.loadInitial();
  }

  private applyContentState(state: PeopleContentViewState): void {
    this.contentPhase = state.phase;
    this.contentItems = state.items;
    this.contentLoadingMore = state.loadingMore;
    this.contentCanLoadMore = state.canLoadMore;
    this.contentRequiresLogin = state.requiresLogin;
    this.contentErrorMessage = state.errorMessage ?? '';
  }

  @Builder
  private profileActionsSheet() {
    Column({ space: $r('app.float.spacing_medium') }) {
      Row({ space: $r('app.float.spacing_small') }) {
        Text(this.profile?.name ?? '用户主页操作')
          .fontSize($r('app.float.heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
          .maxLines(1)
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
          .id('people_detail_actions_close')
          .width(40)
          .height(40)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText('关闭用户主页操作')
          .onClick((): void => {
            this.profileActionsSheetShown = false;
          })
      }
      .width('100%')
      Button('查看收藏夹')
        .id('people_detail_collections')
        .fontColor(onThemeColor(this.resolvedThemeColor))
        .backgroundColor(this.resolvedThemeColor)
        .width('100%')
        .enabled(this.profile !== undefined)
        .onClick((): void => {
          this.profileActionsSheetShown = false;
          this.navigate({ name: AppDestinationName.COLLECTIONS, id: this.identifier });
        })
      Button('屏蔽该用户')
        .id('people_detail_block_user')
        .width('100%')
        .fontColor($r('app.color.error_text'))
        .backgroundColor(Color.Transparent)
        .enabled(!this.blockingBusy && this.blockingAction !== undefined && this.profile !== undefined)
        .onClick((): void => {
          const profile = this.profile;
          this.profileActionsSheetShown = false;
          if (profile !== undefined) {
            this.pendingUserBlock = { userId: profile.id, userName: profile.name };
            this.userBlockSheetShown = true;
          }
        })
    }
    .width('100%')
    .padding($r('app.float.spacing_medium'))
    .backgroundColor($r('app.color.surface_background'))
  }

  @Builder
  private userBlockDialog() {
    Column({ space: $r('app.float.spacing_small') }) {
      Text(`确定要屏蔽用户「${this.pendingUserBlock?.userName ?? ''}」吗？`)
        .fontSize($r('app.float.body_font_size'))
        .width('100%')
      Text('屏蔽后，该作者的内容将不再显示。')
        .fontSize($r('app.float.secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      Row({ space: $r('app.float.spacing_small') }) {
        Button('取消')
          .backgroundColor($r('app.color.control_background'))
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
          .enabled(!this.blockingBusy)
          .onClick((): void => {
            this.userBlockSheetShown = false;
            this.pendingUserBlock = undefined;
          })
        Button('确定屏蔽')
          .backgroundColor(this.resolvedThemeColor)
          .fontColor(onThemeColor(this.resolvedThemeColor))
          .id('people_detail_confirm_block_user')
          .layoutWeight(1)
          .enabled(!this.blockingBusy)
          .onClick((): void => this.confirmUserBlock())
      }
      .width('100%')
    }
    .width('100%')
    .padding($r('app.float.spacing_medium'))
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.card_radius'))
  }

  private confirmUserBlock(): void {
    const pending = this.pendingUserBlock;
    const action = this.blockingAction;
    const profile = this.profile;
    if (pending === undefined || action === undefined || profile === undefined) {
      return;
    }
    this.userBlockSheetShown = false;
    this.pendingUserBlock = undefined;
    action.blockUser(pending.userId, pending.userName, {
      contentTitle: `${profile.name}的主页`,
      contentKind: 'people',
      contentId: profile.id
    });
  }
}

function peopleContentKindLabel(kind: PeopleContentKind): string {
  if (kind === PeopleContentKind.ANSWER) {
    return '回答';
  }
  if (kind === PeopleContentKind.ARTICLE) {
    return '文章';
  }
  return '想法';
}

function peopleContentDestination(item: PeopleContentItem): AppDestination {
  if (item.kind === PeopleContentKind.ANSWER) {
    return { name: AppDestinationName.ANSWER, id: item.id };
  }
  if (item.kind === PeopleContentKind.ARTICLE) {
    return { name: AppDestinationName.ARTICLE, id: item.id };
  }
  return { name: AppDestinationName.PIN, id: item.id };
}
