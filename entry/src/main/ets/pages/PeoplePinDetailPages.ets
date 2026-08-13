import { P1Destination, P1DestinationName } from 'core';
import {
  LoginSessionGateway,
  OpenedContentStore,
  PeopleDetailRepository,
  PeopleProfile,
  PinDetail,
  PinRepository,
  PinTopic
} from 'data';
import {
  PeopleDetailController,
  PeopleDetailViewState,
  PinDetailController,
  PinDetailViewState,
  ReadOnlyDetailPhase
} from './PeoplePinDetailState';
import { NativeContentDocument } from './NativeContentDocument';

@Component
struct ReadOnlyDetailStatusPanel {
  kind: string = '';
  message: string = '';
  loading: boolean = false;
  requiresLogin: boolean = false;
  onRetry: () => void = (): void => {
  };
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {
  };

  build() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      if (this.loading) {
        LoadingProgress()
          .id(`p2_${this.kind}_detail_loading_progress`)
          .width(40)
          .height(40)
          .color($r('app.color.brand_primary'))
      }
      Text(this.message)
        .id(`p2_${this.kind}_detail_status`)
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .textAlign(TextAlign.Center)
        .width('100%')
      if (!this.loading) {
        if (this.requiresLogin) {
          Button('去登录')
            .id(`p2_${this.kind}_detail_login`)
            .onClick((): void => this.navigate({ name: P1DestinationName.LOGIN }))
        } else {
          Button('重新加载')
            .id(`p2_${this.kind}_detail_retry`)
            .onClick((): void => this.onRetry())
        }
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .height('100%')
    .padding($r('app.float.p1_page_padding'))
  }
}

@Component
export struct PeopleDetailPage {
  identifier: string = '';
  repository: PeopleDetailRepository | undefined = undefined;
  session: LoginSessionGateway | undefined = undefined;
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {
  };
  @State private phase: ReadOnlyDetailPhase = ReadOnlyDetailPhase.IDLE;
  @State private profile: PeopleProfile | undefined = undefined;
  @State private errorMessage: string = '';
  @State private requiresLogin: boolean = false;
  private controller?: PeopleDetailController;

  aboutToAppear(): void {
    if (this.repository === undefined || this.session === undefined) {
      this.phase = ReadOnlyDetailPhase.ERROR;
      this.errorMessage = '用户主页数据源未配置';
      return;
    }
    this.controller = new PeopleDetailController(
      this.repository,
      this.session,
      (state: PeopleDetailViewState): void => this.applyState(state)
    );
    this.controller.activate();
    this.controller.load(this.identifier);
  }

  aboutToDisappear(): void {
    this.controller?.deactivate();
    this.controller = undefined;
  }

  build() {
    Column() {
      if (this.phase === ReadOnlyDetailPhase.IDLE || this.phase === ReadOnlyDetailPhase.LOADING) {
        ReadOnlyDetailStatusPanel({
          kind: 'people',
          message: '正在加载用户主页…',
          loading: true,
          navigate: this.navigate
        })
      } else if (this.phase === ReadOnlyDetailPhase.ERROR) {
        ReadOnlyDetailStatusPanel({
          kind: 'people',
          message: this.errorMessage,
          requiresLogin: this.requiresLogin,
          onRetry: (): void => {
            this.controller?.load(this.identifier);
          },
          navigate: this.navigate
        })
      } else if (this.profile !== undefined) {
        this.loadedProfile(this.profile)
      }
    }
    .id('p2_people_detail_page')
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private loadedProfile(profile: PeopleProfile) {
    Scroll() {
      Column({ space: $r('app.float.p1_spacing_large') }) {
        if (profile.avatarUrl !== undefined) {
          Image(profile.avatarUrl)
            .id('p2_people_detail_avatar')
            .width(88)
            .height(88)
            .borderRadius(44)
            .objectFit(ImageFit.Cover)
        } else {
          Text(profile.name.charAt(0))
            .id('p2_people_detail_avatar_fallback')
            .width(88)
            .height(88)
            .borderRadius(44)
            .backgroundColor($r('app.color.surface_background'))
            .fontSize($r('app.float.p1_display_font_size'))
            .fontColor($r('app.color.brand_primary'))
            .textAlign(TextAlign.Center)
        }

        Column({ space: $r('app.float.p1_spacing_small') }) {
          Text(profile.name)
            .id('p2_people_detail_name')
            .fontSize($r('app.float.p1_display_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .textAlign(TextAlign.Center)
          if (profile.isOrganization) {
            Text('机构账号')
              .id('p2_people_detail_organization')
              .fontSize($r('app.float.p1_secondary_font_size'))
              .fontColor($r('app.color.brand_primary'))
          }
          if (profile.headline.length > 0) {
            Text(profile.headline)
              .id('p2_people_detail_headline')
              .fontSize($r('app.float.p1_body_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .textAlign(TextAlign.Center)
              .width('100%')
          }
        }
        .alignItems(HorizontalAlign.Center)
        .width('100%')

        Row() {
          this.profileStatistic('回答', profile.answerCount, 'answers')
          this.profileStatistic('文章', profile.articleCount, 'articles')
          this.profileStatistic('关注', profile.followingCount, 'following')
          this.profileStatistic('粉丝', profile.followerCount, 'followers')
        }
        .id('p2_people_detail_statistics')
        .width('100%')
        .justifyContent(FlexAlign.SpaceEvenly)
        .padding($r('app.float.p1_spacing_medium'))
        .backgroundColor($r('app.color.surface_background'))
        .borderRadius(16)

        Text(profile.isFollowing ? '已关注' : '只读资料')
          .id('p2_people_detail_relationship')
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
      }
      .alignItems(HorizontalAlign.Center)
      .width('100%')
      .padding($r('app.float.p1_page_padding'))
    }
    .scrollBar(BarState.Auto)
    .width('100%')
    .height('100%')
  }

  @Builder
  private profileStatistic(label: string, value: number, tag: string) {
    Column({ space: 4 }) {
      Text(`${value}`)
        .id(`p2_people_detail_${tag}_count`)
        .fontSize($r('app.float.p1_heading_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
      Text(label)
        .fontSize($r('app.float.p1_secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
    }
    .alignItems(HorizontalAlign.Center)
  }

  private applyState(state: PeopleDetailViewState): void {
    this.phase = state.phase;
    this.profile = state.profile;
    this.errorMessage = state.errorMessage ?? '';
    this.requiresLogin = state.requiresLogin;
  }
}

@Component
export struct PinDetailPage {
  contentId: string = '';
  repository: PinRepository | undefined = undefined;
  session: LoginSessionGateway | undefined = undefined;
  openedContentStore: OpenedContentStore | undefined = undefined;
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {
  };
  @State private phase: ReadOnlyDetailPhase = ReadOnlyDetailPhase.IDLE;
  @State private pin: PinDetail | undefined = undefined;
  @State private errorMessage: string = '';
  @State private requiresLogin: boolean = false;
  @State private openedRecordFailed: boolean = false;
  private controller?: PinDetailController;

  aboutToAppear(): void {
    if (this.repository === undefined || this.session === undefined) {
      this.phase = ReadOnlyDetailPhase.ERROR;
      this.errorMessage = '想法详情数据源未配置';
      return;
    }
    this.controller = new PinDetailController(
      this.repository,
      this.session,
      this.openedContentStore,
      (state: PinDetailViewState): void => this.applyState(state)
    );
    this.controller.activate();
    this.controller.load(this.contentId);
  }

  aboutToDisappear(): void {
    this.controller?.deactivate();
    this.controller = undefined;
  }

  build() {
    Column() {
      if (this.phase === ReadOnlyDetailPhase.IDLE || this.phase === ReadOnlyDetailPhase.LOADING) {
        ReadOnlyDetailStatusPanel({
          kind: 'pin',
          message: '正在加载想法…',
          loading: true,
          navigate: this.navigate
        })
      } else if (this.phase === ReadOnlyDetailPhase.ERROR) {
        ReadOnlyDetailStatusPanel({
          kind: 'pin',
          message: this.errorMessage,
          requiresLogin: this.requiresLogin,
          onRetry: (): void => {
            this.controller?.load(this.contentId);
          },
          navigate: this.navigate
        })
      } else if (this.pin !== undefined) {
        this.loadedPin(this.pin)
      }
    }
    .id('p2_pin_detail_page')
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private loadedPin(pin: PinDetail) {
    Column() {
      Column({ space: $r('app.float.p1_spacing_small') }) {
        Text(`${pin.author.name}的想法`)
          .id('p2_pin_detail_title')
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .width('100%')
        Text(pin.author.headline.length > 0 ? `${pin.author.name} · ${pin.author.headline}` : pin.author.name)
          .id('p2_pin_detail_author')
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.brand_primary'))
          .width('100%')
          .onClick((): void => {
            this.navigate({
              name: P1DestinationName.PEOPLE,
              id: pin.author.urlToken ?? pin.author.id
            });
          })
        Text(`${pin.likeCount} 赞 · ${pin.commentCount} 条评论`)
          .id('p2_pin_detail_statistics')
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
        if (pin.createdAt > 0) {
          Text(pinTimeText(pin))
            .id('p2_pin_detail_time')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
        }
        if (pin.topics.length > 0) {
          Row({ space: $r('app.float.p1_spacing_small') }) {
            ForEach(pin.topics, (topic: PinTopic) => {
              Text(`# ${topic.name}`)
                .id(`p2_pin_detail_topic_${topic.id}`)
                .fontSize($r('app.float.p1_secondary_font_size'))
                .fontColor($r('app.color.brand_primary'))
            }, (topic: PinTopic): string => topic.id)
          }
          .width('100%')
        }
        if (this.openedRecordFailed) {
          Text('本次打开记录未能保存，阅读不受影响')
            .id('p2_pin_detail_opened_record_failed')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding($r('app.float.p1_page_padding'))
      .backgroundColor($r('app.color.surface_background'))

      NativeContentDocument({
        html: pin.contentHtml,
        emptyMessage: '这条想法暂时没有正文'
      })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }

  private applyState(state: PinDetailViewState): void {
    this.phase = state.phase;
    this.pin = state.pin;
    this.errorMessage = state.errorMessage ?? '';
    this.requiresLogin = state.requiresLogin;
    this.openedRecordFailed = state.openedRecordFailed;
  }
}

function pinTimeText(pin: PinDetail): string {
  const usesUpdatedTime = pin.updatedAt > pin.createdAt;
  const value = usesUpdatedTime ? pin.updatedAt : pin.createdAt;
  const date = new Date(value * 1000);
  return `${usesUpdatedTime ? '更新于' : '发布于'} ${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`;
}
