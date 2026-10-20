import { AppDestination } from 'core';
import {
  AppPreferencesStore,
  BlockedFeedHistoryGateway,
  BlockingRuleGateway,
  ChannelFeedRepository,
  ChannelFeedSource,
  DEFAULT_THEME_COLOR,
  onThemeColor,
  RecentFollowingUsersRepository
} from 'data';
import { ChannelFeedPage } from './ChannelFeedPage';
import { FollowingUsersRow } from './components/FollowingUsersRow';

/**
 * 关注顶层页内用横向 Swiper 承载“推荐”与“动态”两个子页，
 * 支持左右滑动切换；两个页签各自持有仓储和 ChannelFeedPage，不会串用分页游标。
 * 标题栏页签选择经 AppStorage 广播（@Consume 在 HdsTabs 树下实测不链接）。
 */
@Component
export struct FollowingFeedPage {
  recommendRepository: ChannelFeedRepository | undefined = undefined;
  dynamicRepository: ChannelFeedRepository | undefined = undefined;
  usersRepository: RecentFollowingUsersRepository | undefined = undefined;
  preferences: AppPreferencesStore | undefined = undefined;
  rules: BlockingRuleGateway | undefined = undefined;
  history: BlockedFeedHistoryGateway | undefined = undefined;
  @Prop reloadToken: number = 0;
  @Prop selectedTabIndex: number = 0;
  navigate: (destination: AppDestination) => void = (_destination: AppDestination): void => {
  };
  @State private activeTabIndex: number = 0;
  private readonly swiperController: SwiperController = new SwiperController();
  @StorageProp('followingSelectedTabIndex') @Watch('rememberSelectedTab') followingSelectedTabIndex: number = 0;
  @StorageProp('followingTabSelectionTick') @Watch('onFollowingTabSelectionTick') followingTabSelectionTick: number = 0;
  @StorageProp('followingTimeOrder') @Watch('rememberFollowingOrder') private followingTimeOrder: boolean = false;
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;

  aboutToAppear(): void {
    const selected = AppStorage.get<number>('followingSelectedTabIndex') ?? this.selectedTabIndex;
    const initial = selected === 1 ? 1 : 0;
    this.activeTabIndex = initial;
    if (AppStorage.get<number>('followingSelectedTabIndex') !== initial) {
      AppStorage.setOrCreate('followingSelectedTabIndex', initial);
    }
  }

  private rememberSelectedTab(): void {
    const selected = this.followingSelectedTabIndex;
    if (selected !== 0 && selected !== 1) {
      return;
    }
    this.preferences?.saveFollowingFeedTabIndex(selected).catch((_error: Error): void => {
      this.getUIContext().getPromptAction().showToast({ message: '关注页签保存失败，重启后将恢复原设置' });
    });
  }

  private rememberFollowingOrder(): void {
    this.preferences?.saveFollowingTimeOrder(this.followingTimeOrder).catch((_error: Error): void => {
      this.getUIContext().getPromptAction().showToast({ message: '动态排序保存失败，重启后将恢复原设置' });
    });
  }

  private onFollowingTabSelectionTick(): void {
    const target = this.followingSelectedTabIndex;
    if ((target === 0 || target === 1) && target !== this.activeTabIndex) {
      this.swiperController.changeIndex(target, true);
    }
  }

  @Builder
  private recommendTopContent() {
    FollowingUsersRow({
      repository: this.usersRepository,
      navigate: this.navigate
    })
  }

  @Builder
  private timelineTopContent() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('动态排序')
          .fontSize($r('app.float.secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .layoutWeight(1)
        Button('默认', { type: ButtonType.Capsule })
          .id('following_sort_default')
          .height(32)
          .padding({ left: 12, right: 12 })
          .fontSize($r('app.float.secondary_font_size'))
          .backgroundColor(!this.followingTimeOrder ? this.resolvedThemeColor : $r('app.color.surface_background'))
          .fontColor(!this.followingTimeOrder ? onThemeColor(this.resolvedThemeColor) : $r('app.color.secondary_text'))
          .onClick((): void => { AppStorage.setOrCreate('followingTimeOrder', false); })
        Button('按时间', { type: ButtonType.Capsule })
          .id('following_sort_time')
          .height(32)
          .padding({ left: 12, right: 12 })
          .fontSize($r('app.float.secondary_font_size'))
          .backgroundColor(this.followingTimeOrder ? this.resolvedThemeColor : $r('app.color.surface_background'))
          .fontColor(this.followingTimeOrder ? onThemeColor(this.resolvedThemeColor) : $r('app.color.secondary_text'))
          .onClick((): void => { AppStorage.setOrCreate('followingTimeOrder', true); })
      }
      .width('100%')
    }
    .width('100%')
    .padding($r('app.float.card_padding'))
  }

  build() {
    Swiper(this.swiperController) {
      ChannelFeedPage({
        source: ChannelFeedSource.FOLLOWING_RECOMMEND,
        showHeader: false,
        topContent: (): void => {
          this.recommendTopContent()
        },
        topContentVisible: true,
        repository: this.recommendRepository,
        reloadToken: this.reloadToken,
        navigate: this.navigate,
        rules: this.rules,
        history: this.history
      })
        .id('following_recommend_content')

      ChannelFeedPage({
        source: ChannelFeedSource.FOLLOWING,
        showHeader: false,
        topContent: (): void => {
          this.timelineTopContent()
        },
        topContentVisible: true,
        repository: this.dynamicRepository,
        reloadToken: this.reloadToken,
        navigate: this.navigate,
        rules: this.rules,
        history: this.history
      })
        .id('following_dynamic_content')
    }
    .id('following_pager')
    .index(this.activeTabIndex)
    .loop(false)
    .indicator(false)
    .cachedCount(1)
    .nestedScroll(SwiperNestedScrollMode.SELF_FIRST)
    .onChange((index: number): void => {
      if (index === this.activeTabIndex) {
        return;
      }
      this.activeTabIndex = index;
      AppStorage.setOrCreate('followingSelectedTabIndex', index);
    })
    .width('100%')
    .layoutWeight(1)
    .backgroundColor($r('app.color.page_background'))
  }

}
