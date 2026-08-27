import { P1Destination } from 'core';
import {
  BlockedFeedHistoryGateway,
  BlockingRuleGateway,
  ChannelFeedRepository,
  ChannelFeedSource
} from 'data';
import { ChannelFeedPage } from './ChannelFeedPage';

/**
 * 与上游 FollowScreen 一致：关注顶层页内继续区分推荐与动态。
 * 两个页签各自持有仓储和 ChannelFeedPage，切换时不会串用分页游标或已加载内容。
 */
@Component
export struct FollowingFeedPage {
  recommendRepository: ChannelFeedRepository | undefined = undefined;
  dynamicRepository: ChannelFeedRepository | undefined = undefined;
  rules: BlockingRuleGateway | undefined = undefined;
  history: BlockedFeedHistoryGateway | undefined = undefined;
  @Prop reloadToken: number = 0;
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {
  };
  @State private selectedTab: number = 0;

  build() {
    Tabs({ barPosition: BarPosition.Start, index: $$this.selectedTab }) {
      TabContent() {
        ChannelFeedPage({
          source: ChannelFeedSource.FOLLOWING_RECOMMEND,
          showHeader: false,
          repository: this.recommendRepository,
          reloadToken: this.reloadToken,
          navigate: this.navigate,
          rules: this.rules,
          history: this.history
        });
      }
      .id('p2_following_recommend_content')
      .tabBar('推荐')

      TabContent() {
        ChannelFeedPage({
          source: ChannelFeedSource.FOLLOWING,
          showHeader: false,
          repository: this.dynamicRepository,
          reloadToken: this.reloadToken,
          navigate: this.navigate,
          rules: this.rules,
          history: this.history
        });
      }
      .id('p2_following_dynamic_content')
      .tabBar('动态')
    }
    .id('p2_following_tabs')
    .width('100%')
    .height('100%')
    .barMode(BarMode.Fixed)
    .scrollable(false)
    .backgroundColor($r('app.color.page_background'))
    .onChange((index: number): void => {
      if (index === 0 || index === 1) {
        this.selectedTab = index;
      }
    })
  }
}
