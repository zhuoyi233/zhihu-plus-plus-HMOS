import { P1Destination, P1DestinationName } from 'core';
import {
  CollectionRepository,
  CollectionSummary,
  LoginSessionGateway
} from 'data';
import {
  CollectionFavoriteController,
  CollectionFavoritePhase,
  CollectionFavoriteViewState
} from './CollectionFavoriteState';

@Component
export struct CollectionDialogComponent {
  contentType: string = 'answer';
  contentId: string = '';
  repository: CollectionRepository | undefined = undefined;
  session: LoginSessionGateway | undefined = undefined;
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {
  };
  onDismiss: () => void = (): void => {
  };
  @State private phase: CollectionFavoritePhase = CollectionFavoritePhase.IDLE;
  @State private collections: Array<CollectionSummary> = [];
  @State private busyCollectionId?: string = undefined;
  @State private requiresLogin: boolean = false;
  @State private message: string = '';
  @State private showCreate: boolean = false;
  @State private createTitle: string = '';
  @State private createDescription: string = '';
  @State private createIsPublic: boolean = false;
  private controller?: CollectionFavoriteController;

  aboutToAppear(): void {
    const repository = this.repository;
    const session = this.session;
    if (repository === undefined || session === undefined) {
      this.phase = CollectionFavoritePhase.ERROR;
      this.message = '收藏数据源未配置';
      return;
    }
    this.controller = new CollectionFavoriteController(
      repository,
      session,
      (state: CollectionFavoriteViewState): void => this.applyState(state)
    );
    this.controller.activate();
    this.controller.load(this.contentType, this.contentId);
  }

  aboutToDisappear(): void {
    this.controller?.deactivate();
    this.controller = undefined;
  }

  build() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Text('选择收藏夹')
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Button('关闭')
          .id('p3_favorite_dialog_close')
          .fontSize($r('app.float.p1_secondary_font_size'))
          .onClick((): void => this.onDismiss())
      }
      .width('100%')

      if (this.phase === CollectionFavoritePhase.LOADING || this.phase === CollectionFavoritePhase.IDLE) {
        LoadingProgress()
          .id('p3_favorite_dialog_loading')
          .width(40)
          .height(40)
          .color($r('app.color.brand_primary'))
      } else if (this.phase === CollectionFavoritePhase.ERROR) {
        Column({ space: $r('app.float.p1_spacing_small') }) {
          Text(this.message)
            .id('p3_favorite_dialog_error')
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
          if (this.requiresLogin) {
            Button('去登录')
              .id('p3_favorite_dialog_login')
              .onClick((): void => this.navigate({ name: P1DestinationName.LOGIN }))
          } else {
            Button('重试')
              .id('p3_favorite_dialog_retry')
              .onClick((): void => {
                this.controller?.load(this.contentType, this.contentId);
              })
          }
        }
        .width('100%')
      } else {
        if (!this.showCreate) {
          Button('新建收藏夹')
            .id('p3_favorite_dialog_create')
            .width('100%')
            .fontSize($r('app.float.p1_body_font_size'))
            .enabled(this.busyCollectionId === undefined)
            .onClick((): void => {
              this.createTitle = '';
              this.createDescription = '';
              this.createIsPublic = false;
              this.showCreate = true;
            })
        }

        if (this.showCreate) {
          this.createForm()
        }

        if (this.message.length > 0) {
          Text(this.message)
            .id('p3_favorite_dialog_message')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor(this.requiresLogin ? $r('app.color.error_text') : $r('app.color.secondary_text'))
            .width('100%')
        }

        List({ space: 8 }) {
          ForEach(this.collections, (collection: CollectionSummary) => {
            ListItem() {
              this.collectionRow(collection)
            }
          }, (collection: CollectionSummary): string => collection.id)
        }
        .id('p3_favorite_dialog_list')
        .layoutWeight(1)
        .width('100%')
      }
    }
    .id('p3_favorite_dialog')
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .padding($r('app.float.p1_page_padding'))
    .backgroundColor($r('app.color.surface_background'))
    .borderRadius({ topLeft: $r('app.float.p1_card_radius'), topRight: $r('app.float.p1_card_radius') })
  }

  @Builder
  private collectionRow(collection: CollectionSummary) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Column({ space: 2 }) {
          Text(collection.title)
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.primary_text'))
            .width('100%')
          Text(`${collection.itemCount} 篇内容`)
            .fontSize($r('app.float.p1_caption_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
        }
        .layoutWeight(1)
        Text(collection.isFavorited ? '已收藏' : '未收藏')
          .id(`p3_favorite_dialog_item_${collection.id}`)
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor(collection.isFavorited ? $r('app.color.brand_primary') : $r('app.color.secondary_text'))
      }
      .width('100%')
    }
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
    .borderRadius($r('app.float.p1_card_radius'))
    .backgroundColor($r('app.color.card_background'))
    .enabled(this.busyCollectionId === undefined || this.busyCollectionId === collection.id)
    .onClick((): void => {
      this.controller?.toggle(collection, this.contentType, this.contentId);
    })
  }

  @Builder
  private createForm() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Text('新建收藏夹')
        .fontSize($r('app.float.p1_body_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      TextInput({ text: this.createTitle, placeholder: '收藏夹名称' })
        .id('p3_favorite_dialog_create_title')
        .width('100%')
        .maxLength(50)
        .onChange((value: string): void => {
          this.createTitle = value;
        })
      TextInput({ text: this.createDescription, placeholder: '描述（可选）' })
        .id('p3_favorite_dialog_create_description')
        .width('100%')
        .maxLength(200)
        .onChange((value: string): void => {
          this.createDescription = value;
        })
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Text('公开收藏夹')
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.createIsPublic })
          .id('p3_favorite_dialog_create_public')
          .onChange((value: boolean): void => {
            this.createIsPublic = value;
          })
      }
      .width('100%')
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Button('取消')
          .layoutWeight(1)
          .enabled(this.busyCollectionId === undefined)
          .onClick((): void => {
            this.showCreate = false;
          })
        Button(this.busyCollectionId === 'creating' ? '创建中…' : '创建并收藏')
          .id('p3_favorite_dialog_create_submit')
          .layoutWeight(1)
          .enabled(this.busyCollectionId === undefined && this.createTitle.trim().length > 0)
          .onClick((): void => {
            this.controller?.createAndAdd(
              this.createTitle,
              this.createDescription,
              this.createIsPublic,
              this.contentType,
              this.contentId
            ).then((created: boolean): void => {
              if (created) {
                this.showCreate = false;
              }
            });
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding($r('app.float.p1_spacing_medium'))
    .borderRadius($r('app.float.p1_card_radius'))
    .backgroundColor($r('app.color.page_background'))
  }

  private applyState(state: CollectionFavoriteViewState): void {
    this.phase = state.phase;
    this.collections = state.collections;
    this.busyCollectionId = state.busyCollectionId;
    this.requiresLogin = state.requiresLogin;
    this.message = state.message ?? '';
  }
}
