import { P1Destination } from 'core';
import {
  BlockedFeedHistoryGateway,
  BlockingRuleGateway,
  ChannelFeedRepository,
  ChannelFeedSource,
  RecentFollowingUsersRepository
} from 'data';
import { ChannelFeedPage } from './ChannelFeedPage';
import { FollowingUsersRow } from './components/FollowingUsersRow';

/**
 * 与上游 FollowScreen 一致：关注顶层页内用横向 Swiper 承载“推荐”与“动态”两个子页，
 * 支持左右滑动切换；两个页签各自持有仓储和 ChannelFeedPage，不会串用分页游标。
 * 标题栏页签选择经 AppStorage 广播（@Consume 在 HdsTabs 树下实测不链接）。
 */
@Component
export struct FollowingFeedPage {
  recommendRepository: ChannelFeedRepository | undefined = undefined;
  dynamicRepository: ChannelFeedRepository | undefined = undefined;
  usersRepository: RecentFollowingUsersRepository | undefined = undefined;
  rules: BlockingRuleGateway | undefined = undefined;
  history: BlockedFeedHistoryGateway | undefined = undefined;
  @Prop reloadToken: number = 0;
  @Prop selectedTabIndex: number = 0;
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {
  };
  @State private activeTabIndex: number = 0;
  private readonly swiperController: SwiperController = new SwiperController();
  @StorageProp('followingSelectedTabIndex') followingSelectedTabIndex: number = 0;
  @StorageProp('followingTabSelectionTick') @Watch('onFollowingTabSelectionTick') followingTabSelectionTick: number = 0;

  aboutToAppear(): void {
    const initial = this.selectedTabIndex === 1 ? 1 : 0;
    this.activeTabIndex = initial;
    if (AppStorage.get<number>('followingSelectedTabIndex') !== initial) {
      AppStorage.setOrCreate('followingSelectedTabIndex', initial);
    }
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
        .id('p2_following_recommend_content')

      ChannelFeedPage({
        source: ChannelFeedSource.FOLLOWING,
        showHeader: false,
        repository: this.dynamicRepository,
        reloadToken: this.reloadToken,
        navigate: this.navigate,
        rules: this.rules,
        history: this.history
      })
        .id('p2_following_dynamic_content')
    }
    .id('p2_following_pager')
    .index(this.activeTabIndex)
    .loop(false)
    .indicator(false)
    .cachedCount(1)
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
