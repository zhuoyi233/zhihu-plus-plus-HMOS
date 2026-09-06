import { P1Destination, P1DestinationName } from 'core';
import { RecentFollowingUser, RecentFollowingUsersRepository } from 'data';

/**
 * 关注推荐页顶部“最近更新的关注用户”头像行，对齐上游 FollowingUsersRow：
 * 横向滚动头像 + 未读红点 + 昵称，点击进入用户主页；加载失败时静默收起整行。
 */
@Component
export struct FollowingUsersRow {
  repository: RecentFollowingUsersRepository | undefined = undefined;
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {
  };
  @State private users: Array<RecentFollowingUser> = [];
  private loaded: boolean = false;

  aboutToAppear(): void {
    this.loadUsers();
  }

  private loadUsers(): void {
    const repository = this.repository;
    if (repository === undefined || this.loaded || this.users.length > 0) {
      return;
    }
    this.loaded = true;
    repository.loadRecentUsers().then((users: Array<RecentFollowingUser>): void => {
      this.users = users;
    }).catch((): void => {
      // 对齐上游：关注行加载失败仅不展示，不打断推荐流。
    });
  }

  build() {
    if (this.users.length > 0) {
      Scroll() {
        Row({ space: 16 }) {
          ForEach(this.users, (user: RecentFollowingUser) => {
            Column({ space: 4 }) {
              Stack({ alignContent: Alignment.TopEnd }) {
                Image(user.actor.avatarUrl)
                  .width(56)
                  .height(56)
                  .borderRadius(28)
                  .objectFit(ImageFit.Cover)
                  .alt(user.actor.name)
                if (user.unreadCount > 0) {
                  Circle()
                    .width(10)
                    .height(10)
                    .fill('#FF4D4F')
                    .stroke('#FFFFFF')
                    .strokeWidth(1.5)
                    .margin({ top: 2, right: 2 })
                }
              }
              .width(56)
              .height(56)
              Text(user.actor.name)
                .fontSize(12)
                .fontColor($r('app.color.secondary_text'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width(60)
                .textAlign(TextAlign.Center)
            }
            .id(`p2_following_users_item_${user.actor.id}`)
            .alignItems(HorizontalAlign.Center)
            .onClick((): void => {
              this.navigate({ name: P1DestinationName.PEOPLE, id: user.actor.urlToken });
            })
          }, (user: RecentFollowingUser): string => user.actor.id)
        }
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      }
      .id('p2_following_users_row')
      .width('100%')
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
  }
}
